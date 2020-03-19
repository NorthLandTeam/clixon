/*
 *
  ***** BEGIN LICENSE BLOCK *****
 
  Copyright (C) 2009-2019 Olof Hagsand and Benny Holmgren

  This file is part of CLIXON.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

  Alternatively, the contents of this file may be used under the terms of
  the GNU General Public License Version 3 or later (the "GPL"),
  in which case the provisions of the GPL are applicable instead
  of those above. If you wish to allow use of your version of this file only
  under the terms of the GPL, and not to allow others to
  use your version of this file under the terms of Apache License version 2, 
  indicate your decision by deleting the provisions above and replace them with
  the  notice and other provisions required by the GPL. If you do not delete
  the provisions above, a recipient may use your version of this file under
  the terms of any one of the Apache License version 2 or the GPL.

  ***** END LICENSE BLOCK *****

 *
 *  netconf lib
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
#include "clixon_config.h" /* generated by config & autoconf */
#endif

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <syslog.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/param.h>

/* cligen */
#include <cligen/cligen.h>

/* clicon */
#include <clixon/clixon.h>

#include "netconf_rpc.h"
#include "netconf_lib.h"

/*
 * Exported variables
 */
enum transport_type    transport = NETCONF_SSH; /* XXX Remove SOAP support */
int cc_closed = 0; /* XXX Please remove (or at least hide in handle) this global variable */

/*! Add netconf xml postamble of message. I.e, xml after the body of the message.
 * @param[in]  cb  Netconf packet (cligen buffer)
 */
int
add_preamble(cbuf *cb)
{
    if (transport == NETCONF_SOAP)
	cprintf(cb, "\n<soapenv:Envelope\n xmlns:soapenv=\"http://www.w3.org/2003/05/soap-envelope\">\n"
	"<soapenv:Body>");
    return 0;
}

/*! Add netconf xml postamble of message. I.e, xml after the body of the message.
 * for soap this is the envelope stuff, for ssh this is ]]>]]>
 * @param[in]  cb  Netconf packet (cligen buffer)
 */
int
add_postamble(cbuf *cb)
{
    switch (transport){
    case NETCONF_SSH:
	cprintf(cb, "]]>]]>");     /* Add RFC4742 end-of-message marker */
	break;
    case NETCONF_SOAP:
	cprintf(cb, "\n</soapenv:Body>" "</soapenv:Envelope>");
	break;
    }
    return 0;
}

/*! Add error_preamble
 * compared to regular messages (see add_preamble), error message differ in some
 * protocols (eg soap) by adding a longer and deeper header.
 * @param[in]  cb  Netconf packet (cligen buffer)
 */
int
add_error_preamble(cbuf *cb,
		   char *reason)
{
    switch (transport){
    case NETCONF_SOAP:
	cprintf(cb, "<soapenv:Envelope xmlns:soapenv=\"http://www.w3.org/2003/05/soap-envelope\" xmlns:xml=\"http://www.w3.org/XML/1998/namespace\">"
		"<soapenv:Body>"
		"<soapenv:Fault>"
		"<soapenv:Code>"
		"<soapenv:Value>env:Receiver</soapenv:Value>"
		"</soapenv:Code>"
		"<soapenv:Reason>"
		"<soapenv:Text xml:lang=\"en\">%s</soapenv:Text>"
		"</soapenv:Reason>"
		"<detail>", reason);
	break;
    default:
	if (add_preamble(cb) < 0)
	    return -1;
	break;
    }
    return 0;
}

/*! Add error postamble
 * compared to regular messages (see add_postamble), error message differ in some
 * protocols (eg soap) by adding a longer and deeper header.
 * @param[in]  cb  Netconf packet (cligen buffer)
 */
int
add_error_postamble(cbuf *cb)
{
    switch (transport){
    case NETCONF_SOAP:
	cprintf(cb, "</detail>" "</soapenv:Fault>");
    default: /* fall through */
	if (add_postamble(cb) < 0)
	    return -1;
	break;
    }
    return 0;
}


/*! Get "target" attribute, return actual database given candidate or running
 * Caller must do error handling
 * @param[in]  xn       XML tree
 * @param[in]  path
 * @retval     dbname   Actual database file name
 */
char *
netconf_get_target(cxobj        *xn, 
		   char         *path)
{
    cxobj *x;    
    char  *target = NULL;

    if ((x = xpath_first(xn, NULL, "%s", path)) != NULL){
	if (xpath_first(x, NULL, "candidate") != NULL)
	    target = "candidate";
	else
	    if (xpath_first(x, NULL, "running") != NULL)
		target = "running";
	else
	    if (xpath_first(x, NULL, "startup") != NULL)
		target = "startup";
    }
    return target;
    
}

/*! Send netconf message from cbuf on socket
 * @param[in]   s    
 * @param[in]   cb   Cligen buffer that contains the XML message
 * @param[in]   msg  Only for debug
 * @retval      0    OK
 * @retval     -1    Error
 * @see netconf_output_encap  for function with encapsulation
 */
int 
netconf_output(int   s, 
	       cbuf *cb, 
	       char *msg)
{
    char *buf = cbuf_get(cb);
    int   len = cbuf_len(cb);
    int   retval = -1;

    clicon_debug(1, "SEND %s", msg);
    if (debug > 1){ /* XXX: below only works to stderr, clicon_debug may log to syslog */
	cxobj *xt = NULL;
	if (clixon_xml_parse_string(buf, YB_NONE, NULL, &xt, NULL) == 0){
	    clicon_xml2file(stderr, xml_child_i(xt, 0), 0, 0);
	    fprintf(stderr, "\n");
	    xml_free(xt);
	}
    }
    if (write(s, buf, len) < 0){
	if (errno == EPIPE)
	    ;
	else
	    clicon_log(LOG_ERR, "%s: write: %s", __FUNCTION__, strerror(errno));
	goto done;
    }
    retval = 0;
  done:
    return retval;
}

	    
/*! Encapsulate and send outgoing netconf packet as cbuf on socket
 * @param[in]   s    
 * @param[in]   cb   Cligen buffer that contains the XML message
 * @param[in]   msg  Only for debug
 * @retval      0    OK
 * @retval     -1    Error
 * @note Assumes "cb" contains valid XML
 * @see netconf_output  without encapsulation
 */
int 
netconf_output_encap(int   s, 
		     cbuf *cb, 
		     char *msg)
{
    int  retval = -1;
    cbuf *cb1 = NULL;
    
    if ((cb1 = cbuf_new()) == NULL){
	clicon_err(OE_XML, errno, "cbuf_new");
	goto done;
    }
    add_preamble(cb1);
    cprintf(cb1, "%s", cbuf_get(cb));
    add_postamble(cb1);
    retval = netconf_output(s, cb1, msg);
 done:
    if (cb1)
	cbuf_free(cb1);
    return retval;
}

/*
 *
  ***** BEGIN LICENSE BLOCK *****
 
  Copyright (C) 2009-2018 Olof Hagsand and Benny Holmgren

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
 * Protocol to communicate between clients (eg clixon_cli, clixon_netconf) 
 * and server (clicon_backend)
 */

#ifdef HAVE_CONFIG_H
#include "clixon_config.h" /* generated by config & autoconf */
#endif

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <assert.h>
#include <syslog.h>
#include <signal.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <netinet/in.h>
#include <sys/un.h>
#include <arpa/inet.h>

/* cligen */
#include <cligen/cligen.h>

/* clicon */
#include "clixon_err.h"
#include "clixon_log.h"
#include "clixon_queue.h"
#include "clixon_hash.h"
#include "clixon_handle.h"
#include "clixon_yang.h"
#include "clixon_sig.h"
#include "clixon_xml.h"
#include "clixon_proto.h"

static int _atomicio_sig = 0;

/*! Formats (showas) derived from XML
 */
struct formatvec{
    char *fv_str;
    int   fv_int;
};

static struct formatvec _FORMATS[] = {
    {"xml",     FORMAT_XML},
    {"text",    FORMAT_TEXT},
    {"json",    FORMAT_JSON},
    {"cli",     FORMAT_CLI},
    {"netconf", FORMAT_NETCONF},
    {NULL,   -1}
};

/*! Translate from numeric format to string representation
 * @param[in]  showas   Format value (see enum format_enum)
 * @retval     str      String value
 */
char *
format_int2str(enum format_enum showas)
{
    struct formatvec *fv;

    for (fv=_FORMATS; fv->fv_int != -1; fv++)
	if (fv->fv_int == showas)
	    break;
    return fv?(fv->fv_str?fv->fv_str:"unknown"):"unknown";
}

/*! Translate from string to numeric format representation
 * @param[in]  str       String value
 * @retval     enum      Format value (see enum format_enum)
 */
enum format_enum
format_str2int(char *str)
{
    struct formatvec *fv;

    for (fv=_FORMATS; fv->fv_int != -1; fv++)
	if (strcmp(fv->fv_str, str) == 0)
	    break;
    return fv?fv->fv_int:-1;
}

/*! Encode a clicon netconf message using variable argument lists
 * @param[in] format  Variable agrument list format an XML netconf string
 * @retval    msg  Clicon message to send to eg clicon_msg_send()
 * @note if format includes %, they will be expanded according to printf rules.
 *       if this is a problem, use ("%s", xml) instaead of (xml)
 *       Notaly this may an issue of RFC 3896 encoded strings
 */
struct clicon_msg *
clicon_msg_encode(char *format, ...)
{
    va_list            args;
    uint32_t           xmllen;
    uint32_t           len;
    struct clicon_msg *msg = NULL;
    int                hdrlen = sizeof(*msg);

    va_start(args, format);
    xmllen = vsnprintf(NULL, 0, format, args) + 1;
    va_end(args);

    len = hdrlen + xmllen;
    if ((msg = (struct clicon_msg *)malloc(len)) == NULL){
	clicon_err(OE_PROTO, errno, "malloc");
	return NULL;
    }
    memset(msg, 0, len);
    /* hdr */
    msg->op_len = htonl(len);

    /* body */
    va_start(args, format);
    vsnprintf(msg->op_body, xmllen, format, args);
    va_end(args);

    return msg;
}

/*! Decode a clicon netconf message
 * @param[in]  msg    CLICON msg
 * @param[out] xml    XML parse tree
 */
int
clicon_msg_decode(struct clicon_msg *msg, 
		  cxobj            **xml)
{
    int   retval = -1;
    char *xmlstr;

    /* body */
    xmlstr = msg->op_body;
    clicon_debug(1, "%s %s", __FUNCTION__, xmlstr);
    if (xml_parse_string(xmlstr, NULL, xml) < 0)
	goto done;
    retval = 0;
 done:
    return retval;
}

/*! Open local connection using unix domain sockets
 * @param[in]  sockpath Unix domain file path
 * @retval     s       socket
 * @retval     -1      error
 */
int
clicon_connect_unix(char *sockpath)
{
    struct sockaddr_un addr;
    int retval = -1;
    int s;

    if ((s = socket(AF_UNIX, SOCK_STREAM, 0)) < 0) {
	clicon_err(OE_CFG, errno, "socket");
	return -1;
    }
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sockpath, sizeof(addr.sun_path)-1);

    clicon_debug(2, "%s: connecting to %s", __FUNCTION__, addr.sun_path);
    if (connect(s, (struct sockaddr *)&addr, SUN_LEN(&addr)) < 0){
	if (errno == EACCES)
	    clicon_err(OE_CFG, errno, "connecting unix socket: %s."
		       "Client should be member of group $CLICON_SOCK_GROUP: ", 
		       sockpath);
	else
	    clicon_err(OE_CFG, errno, "connecting unix socket: %s", sockpath);
	close(s);
	goto done;
    }
    retval = s;
  done:
    return retval;
}

static void
atomicio_sig_handler(int arg)
{
    _atomicio_sig++;
}

/*! Ensure all of data on socket comes through. fn is either read or write
 * @param[in]  fn  I/O function, ie read/write
 * @param[in]  fd  File descriptor, eg socket
 * @param[in]  s0  Buffer to read to or write from
 * @param[in]  n   Number of bytes to read/write, loop until done
 */
static ssize_t
atomicio(ssize_t (*fn) (int, void *, size_t), 
	 int       fd, 
	 void     *s0, 
	 size_t    n)
{
    char *s = s0;
    ssize_t res, pos = 0;

    while (n > pos) {
	_atomicio_sig = 0;
	res = (fn)(fd, s + pos, n - pos);
	switch (res) {
	case -1:
	    if (errno == EINTR){
		if (!_atomicio_sig)
		    continue;
	    }
	    else if (errno == EAGAIN)
		continue;
	    else if (errno == EPEER)
		res = 0;
	case 0: /* fall thru */
	    return (res);
	default:
	    pos += res;
	}
    }
    return (pos);
}

/*! Print message on debug. Log if syslog, stderr if not
 * @param[in]  msg    CLICON msg
 */
static int
msg_dump(struct clicon_msg *msg)
{
    int  i;
    char buf[9*8];
    char buf2[9*8];
    
    memset(buf2, 0, sizeof(buf2));
    snprintf(buf2, sizeof(buf2), "%s:", __FUNCTION__);
    for (i=0; i<ntohl(msg->op_len); i++){
	snprintf(buf, sizeof(buf), "%s%02x", buf2, ((char*)msg)[i]&0xff);
	if ((i+1)%32==0){
	    clicon_debug(2, "%s", buf);
	    snprintf(buf, sizeof(buf), "%s:", __FUNCTION__);
	}
	else
	    if ((i+1)%4==0)
		snprintf(buf, sizeof(buf), "%s ", buf2);
	strncpy(buf2, buf, sizeof(buf2));
    }
    if (i%32)
	clicon_debug(2, "%s", buf);
    return 0;
}

/*! Send a CLICON netconf message
 * @param[in]   s      socket (unix or inet) to communicate with backend
 * @param[out]  msg    CLICON msg data reply structure. Free with free()
 */
int
clicon_msg_send(int                s, 
		struct clicon_msg *msg)
{ 
    int retval = -1;

    clicon_debug(2, "%s: send msg len=%d", 
		 __FUNCTION__, ntohl(msg->op_len));
    if (debug > 2)
	msg_dump(msg);
    if (atomicio((ssize_t (*)(int, void *, size_t))write, 
		 s, msg, ntohl(msg->op_len)) < 0){
	clicon_err(OE_CFG, errno, "atomicio");
	clicon_log(LOG_WARNING, "%s: write: %s len:%u msg:%s", __FUNCTION__,
		   strerror(errno), ntohs(msg->op_len), msg->op_body);
	goto done;
    }
    retval = 0;
  done:
    return retval;
}

/*! Receive a CLICON message
 *
 * XXX: timeout? and signals?
 * There is rudimentary code for turning on signals and handling them 
 * so that they can be interrupted by ^C. But the problem is that this
 * is a library routine and such things should be set up in the cli 
 * application for example: a daemon calling this function will want another 
 * behaviour.
 * Now, ^C will interrupt the whole process, and this may not be what you want.
 *
 * @param[in]   s      socket (unix or inet) to communicate with backend
 * @param[out]  msg    CLICON msg data reply structure. Free with free()
 * @param[out]  eof    Set if eof encountered
 * Note: caller must ensure that s is closed if eof is set after call.
 */
int
clicon_msg_rcv(int                s,
	       struct clicon_msg **msg,
	       int                *eof)
{ 
    int       retval = -1;
    struct clicon_msg hdr;
    int       hlen;
    uint32_t  len2;
    sigfn_t   oldhandler;
    uint32_t  mlen;

    *eof = 0;
    if (0)
	set_signal(SIGINT, atomicio_sig_handler, &oldhandler);

    if ((hlen = atomicio(read, s, &hdr, sizeof(hdr))) < 0){ 
	clicon_err(OE_CFG, errno, "atomicio");
	goto done;
    }
    if (hlen == 0){
	retval = 0;
	*eof = 1;
	goto done;
    }
    if (hlen != sizeof(hdr)){
	clicon_err(OE_CFG, errno, "header too short (%d)", hlen);
	goto done;
    }
    mlen = ntohl(hdr.op_len);
    clicon_debug(2, "%s: rcv msg len=%d",  
		 __FUNCTION__, mlen);
    if ((*msg = (struct clicon_msg *)malloc(mlen)) == NULL){
	clicon_err(OE_CFG, errno, "malloc");
	goto done;
    }
    memcpy(*msg, &hdr, hlen);
    if ((len2 = atomicio(read, s, (*msg)->op_body, mlen - sizeof(hdr))) < 0){ 
 	clicon_err(OE_CFG, errno, "read");
	goto done;
    }
    if (len2 != mlen - sizeof(hdr)){
	clicon_err(OE_CFG, errno, "body too short");
	goto done;
    }
    if (debug > 1)
	msg_dump(*msg);
    retval = 0;
  done:
    if (0)
	set_signal(SIGINT, oldhandler, NULL);
    return retval;
}

/*! Connect to server, send a clicon_msg message and wait for result using unix socket
 *
 * @param[in]  msg     CLICON msg data structure. It has fixed header and variable body.
 * @param[in]  sockpath Unix domain file path
 * @param[out] retdata  Returned data as string netconf xml tree.
 * @param[out] sock0   Return socket in case of asynchronous notify
 * @retval     0       OK
 * @retval     -1      Error
 * @see clicon_rpc  But this is one-shot rpc: open, send, get reply and close.
 */
int
clicon_rpc_connect_unix(struct clicon_msg *msg, 
			char              *sockpath,
			char             **retdata,
			int               *sock0)
{
    int retval = -1;
    int s = -1;
    struct stat sb;

    clicon_debug(1, "Send msg on %s", sockpath);
    /* special error handling to get understandable messages (otherwise ENOENT) */
    if (stat(sockpath, &sb) < 0){
	clicon_err(OE_PROTO, errno, "%s: config daemon not running?", sockpath);
	goto done;
    }
    if (!S_ISSOCK(sb.st_mode)){
	clicon_err(OE_PROTO, EIO, "%s: Not unix socket", sockpath);
	goto done;
    }
    if ((s = clicon_connect_unix(sockpath)) < 0)
	goto done;
    if (clicon_rpc(s, msg, retdata) < 0)
	goto done;
    if (sock0 != NULL)
	*sock0 = s;
    retval = 0;
  done:
    if (sock0 == NULL && s >= 0)
	close(s);
    return retval;
}

/*! Connect to server, send a clicon_msg message and wait for result using an inet socket
 * This uses unix domain socket communication
 * @param[in]  msg     CLICON msg data structure. It has fixed header and variable body.
 * @param[in]  dst     IPv4 address
 * @param[in]  port    TCP port
 * @param[out] retdata  Returned data as string netconf xml tree.
 * @param[out] sock0   Return socket in case of asynchronous notify
 * @retval     0       OK
 * @retval     -1      Error
 * @see clicon_rpc  But this is one-shot rpc: open, send, get reply and close.
 */
int
clicon_rpc_connect_inet(struct clicon_msg *msg, 
			char              *dst,
			uint16_t           port,
			char             **retdata,
			int               *sock0)
{
    int                retval = -1;
    int                s = -1;
    struct sockaddr_in addr;

    clicon_debug(1, "Send msg to %s:%hu", dst, port);

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (inet_pton(addr.sin_family, dst, &addr.sin_addr) != 1)
	goto done; /* Could check getaddrinfo */
    
    /* special error handling to get understandable messages (otherwise ENOENT) */
    if ((s = socket(addr.sin_family, SOCK_STREAM, 0)) < 0) {
	clicon_err(OE_CFG, errno, "socket");
	return -1;
    }
    if (connect(s, (struct sockaddr*)&addr, sizeof(addr)) < 0){
	clicon_err(OE_CFG, errno, "connecting socket inet4");
	close(s);
	goto done;
    }
    if (clicon_rpc(s, msg, retdata) < 0)
	goto done;
    if (sock0 != NULL)
	*sock0 = s;
    retval = 0;
  done:
    if (sock0 == NULL && s >= 0)
	close(s);
    return retval;
}

/*! Send a clicon_msg message and wait for result.
 *
 * TBD: timeout, interrupt?
 * retval may be -1 and
 * errno set to ENOTCONN which means that socket is now closed probably
 * due to remote peer disconnecting. The caller may have to do something,...
 *
 * @param[in]  s       Socket to communicate with backend
 * @param[in]  msg     CLICON msg data structure. It has fixed header and variable body.
 * @param[out] xret    Returned data as netconf xml tree.
 * @retval     0       OK
 * @retval     -1      Error
 */
int
clicon_rpc(int                   s, 
	   struct clicon_msg    *msg, 
	   char                **ret)
{
    int                retval = -1;
    struct clicon_msg *reply = NULL;
    int                eof;
    char              *data = NULL;
    cxobj             *cx = NULL;

    if (clicon_msg_send(s, msg) < 0)
	goto done;
    if (clicon_msg_rcv(s, &reply, &eof) < 0)
	goto done;
    if (eof){
	clicon_err(OE_PROTO, ESHUTDOWN, "Socket unexpected close");
	close(s);
	errno = ESHUTDOWN;
	goto done;
    }
    data = reply->op_body; /* assume string */
    if (ret && data)
	if ((*ret = strdup(data)) == NULL){
	    clicon_err(OE_UNIX, errno, "strdup");
	    goto done;
	}
    retval = 0;
  done:
    if (cx)
	xml_free(cx);
    if (reply)
	free(reply);
    return retval;
}

/*! Send a clicon_msg message as reply to a clicon rpc request
 *
 * @param[in]  s       Socket to communicate with client
 * @param[in]  data    Returned data as byte-string.
 * @param[in]  datalen Length of returned data XXX  may be unecessary if always string?
 * @retval     0       OK
 * @retval     -1      Error
 */
int 
send_msg_reply(int      s, 
	       char    *data, 
	       uint32_t datalen)
{
    int                retval = -1;
    struct clicon_msg *reply = NULL;
    uint32_t           len;

    len = sizeof(*reply) + datalen;
    if ((reply = (struct clicon_msg *)malloc(len)) == NULL)
	goto done;
    memset(reply, 0, len);
    reply->op_len = htonl(len);
    if (datalen > 0)
      memcpy(reply->op_body, data, datalen);
    if (clicon_msg_send(s, reply) < 0)
	goto done;
    retval = 0;
  done:
    if (reply)
	free(reply);
    return retval;
}

/*! Send a clicon_msg NOTIFY message asynchronously to client
 *
 * @param[in]  s       Socket to communicate with client
 * @param[in]  level
 * @param[in]  event
 * @retval     0       OK
 * @retval     -1      Error
 */
int
send_msg_notify(int   s, 
		int   level, 
		char *event)
{
    int                retval = -1;
    struct clicon_msg *msg = NULL;

    if ((msg=clicon_msg_encode("<notification><event>%s</event></notification>", event)) == NULL)
	goto done;
    if (clicon_msg_send(s, msg) < 0)
	goto done;
    retval = 0;
  done:
    if (msg)
	free(msg);
    return retval;
}

/*! Look for a text pattern in an input string, one char at a time
 *  @param[in]     tag     What to look for
 *  @param[in]     ch      New input character
 *  @param[in,out] state   A state integer holding how far we have parsed.
 *  @retval        0       No, we havent detected end tag
 *  @retval        1       Yes, we have detected end tag!
 */
int
detect_endtag(char *tag, 
	      char  ch, 
	      int  *state)
{
    int retval = 0;

    if (tag[*state] == ch){
	(*state)++;
	if (*state == strlen(tag)){
	    *state = 0;
	    retval = 1;
	}
    }
    else
	*state = 0;
    return retval;
}

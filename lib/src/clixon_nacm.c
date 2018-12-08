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

 * NACM code according to RFC8341 Network Configuration Access Control Model
 */

#ifdef HAVE_CONFIG_H
#include "clixon_config.h" /* generated by config & autoconf */
#endif

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <limits.h>
#include <fnmatch.h>
#include <stdint.h>
#include <assert.h>
#include <syslog.h>

/* cligen */
#include <cligen/cligen.h>

/* clixon */
#include "clixon_queue.h"
#include "clixon_hash.h"
#include "clixon_err.h"
#include "clixon_log.h"
#include "clixon_string.h"
#include "clixon_handle.h"
#include "clixon_yang.h"
#include "clixon_xml.h"
#include "clixon_options.h"
#include "clixon_netconf_lib.h"
#include "clixon_xpath_ctx.h"
#include "clixon_xpath.h"
#include "clixon_xml_db.h"
#include "clixon_nacm.h"

/*! Match nacm access operations according to RFC8341 3.4.4.  
 * Incoming RPC Message Validation Step 7 (c)
 *  The rule's "access-operations" leaf has the "exec" bit set or
 *  has the special value "*".
 * @retval 0  No match
 * @retval 1  Match
 * @note access_operations is bit-fields
 */
static int
nacm_match_access(char *access_operations,
		  char *mode)
{
    if (access_operations==NULL)
	return 0;
    if (strcmp(access_operations,"*")==0)
	return 1;
    if (strstr(access_operations, mode)!=NULL)
	return 1;
    return 0;
}

/*! Match nacm single rule. Either match with access or deny. Or not match.
 * @param[in]  h      Clicon handle
 * @param[in]  name  rpc name
 * @param[in]  xrule  NACM rule XML tree
 * @param[out] cbret  Cligen buffer result. Set to an error msg if retval=0.
 * @retval -1  Error
 * @retval  0  Matching rule AND Not access and cbret set
 * @retval  1  Matchung rule AND Access
 * @retval  2  No matching rule Goto step 10
 * From RFC8341 3.4.4.  Incoming RPC Message Validation
   +---------+-----------------+---------------------+-----------------+
   | Method  | Resource class  | NETCONF operation   | Access          |
   |         |                 |                     | operation       |
   +---------+-----------------+---------------------+-----------------+
   | OPTIONS | all             | none                | none            |
   | HEAD    | all             | <get>, <get-config> | read            |
   | GET     | all             | <get>, <get-config> | read            |
   | POST    | datastore, data | <edit-config>       | create          |
   | POST    | operation       | specified operation | execute         |
   | PUT     | data            | <edit-config>       | create, update  |
   | PUT     | datastore       | <copy-config>       | update          |
   | PATCH   | data, datastore | <edit-config>       | update          |
   | DELETE  | data            | <edit-config>       | delete          |

 7.(cont) A rule matches if all of the following criteria are met: 
        *  The rule's "module-name" leaf is "*" or equals the name of
           the YANG module where the protocol operation is defined.

        *  Either (1) the rule does not have a "rule-type" defined or
           (2) the "rule-type" is "protocol-operation" and the
           "rpc-name" is "*" or equals the name of the requested
           protocol operation.

        *  The rule's "access-operations" leaf has the "exec" bit set or
           has the special value "*".
 */
static int
nacm_match_rule(clicon_handle h,
		char         *name,
		cxobj        *xrule,
		cbuf         *cbret)
{
    int    retval = -1;
    //    cxobj *x;
    char  *module_name;
    char  *rpc_name;
    char  *access_operations;
    char  *action;
    
    module_name = xml_find_body(xrule, "module-name");
    rpc_name = xml_find_body(xrule, "rpc-name");
    /* XXX access_operations can be a set of bits */
    access_operations = xml_find_body(xrule, "access-operations");
    action = xml_find_body(xrule, "action");
    clicon_debug(1, "%s: %s %s %s %s", __FUNCTION__,
	       module_name, rpc_name, access_operations, action);
    if (module_name && strcmp(module_name,"*")==0){
	if (nacm_match_access(access_operations, "exec")){
	    if (rpc_name==NULL ||
		strcmp(rpc_name, "*")==0 || strcmp(rpc_name, name)==0){
		/* Here is a matching rule */
		if (action && strcmp(action, "permit")==0){
		    retval = 1;
		    goto done;
		}
		else{
		    if (netconf_access_denied(cbret, "protocol", "access denied") < 0)
			goto done;
		    retval = 0;
		    goto done;
		}
	    }
	}
    }
    retval = 2; /* no matching rule */
 done:
    return retval;

}

/*! Make nacm access control 
 * @param[in]  h     Clicon handle
 * @param[in]  mode  NACMmode, internal or external
 * @param[in]  name  rpc name
 * @param[in]  username
 * @param[out] cbret Cligen buffer result. Set to an error msg if retval=0.
 * @retval -1  Error
 * @retval  0  Not access and cbret set
 * @retval  1  Access
 * @see RFC8341 3.4.4.  Incoming RPC Message Validation
 */
int
nacm_access(clicon_handle h,
	    char         *mode,
	    char         *name,
	    char         *username,
	    cbuf         *cbret)
{
    int     retval = -1;
    cxobj  *xtop = NULL;
    cxobj  *xacm;
    cxobj  *x;
    cxobj  *xrlist;
    cxobj  *xrule;
    char   *enabled = NULL;
    cxobj **gvec = NULL; /* groups */
    size_t  glen;
    cxobj **rlistvec = NULL; /* rule-list */
    size_t  rlistlen;
    cxobj **rvec = NULL; /* rules */
    size_t  rlen;
    int     i, j;
    char   *exec_default = NULL;
    int     ret;

    clicon_debug(1, "%s", __FUNCTION__);
    /* 0. If nacm-mode is external, get NACM defintion from separet tree,
       otherwise get it from internal configuration */
    if (strcmp(mode, "external")==0){
	if ((xtop = clicon_nacm_ext(h)) == NULL){
	    clicon_err(OE_XML, 0, "No nacm external tree");
	    goto done;
	}
    }
    else if (strcmp(mode, "internal")==0){
	if (xmldb_get(h, "running", "nacm", 0, &xtop) < 0)
	    goto done;	
    }
    else{
	clicon_err(OE_UNIX, 0, "Invalid NACM mode: %s", mode);
	goto done;
    }
    
    /* 1.   If the "enable-nacm" leaf is set to "false", then the protocol
       operation is permitted. (or config does not exist) */
    if ((xacm = xpath_first(xtop, "nacm")) == NULL)
	goto permit;
    exec_default = xml_find_body(xacm, "exec-default");
    if ((x = xpath_first(xacm, "enable-nacm")) == NULL)
	goto permit;
    enabled = xml_body(x);
    if (strcmp(enabled, "true") != 0)
	goto permit;

    /* 2.   If the requesting session is identified as a recovery session,
       then the protocol operation is permitted. NYI */
    
    /* 3.   If the requested operation is the NETCONF <close-session>
       protocol operation, then the protocol operation is permitted.
    */
    if (strcmp(name, "close-session") == 0)
	goto permit;
    /* 4.   Check all the "group" entries to see if any of them contain a
       "user-name" entry that equals the username for the session
       making the request.  (If the "enable-external-groups" leaf is
       "true", add to these groups the set of groups provided by the
       transport layer.)	       */
    if (username == NULL)
	goto step10;
    /* User's group */
    if (xpath_vec(xacm, "groups/group[user-name='%s']", &gvec, &glen, username) < 0)
	goto done;
    /* 5. If no groups are found, continue with step 10. */
    if (glen == 0)
	goto step10;
    /* 6. Process all rule-list entries, in the order they appear in the
        configuration.  If a rule-list's "group" leaf-list does not
        match any of the user's groups, proceed to the next rule-list
        entry. */
    if (xpath_vec(xacm, "rule-list", &rlistvec, &rlistlen) < 0)
	goto done;
    for (i=0; i<rlistlen; i++){
	xrlist = rlistvec[i];
	/* Loop through user's group to find match in this rule-list */
	for (j=0; j<glen; j++){
	    char *gname;
	    gname = xml_find_body(gvec[j], "name");
	    if (xpath_first(xrlist, ".[group='%s']", gname)!=NULL)
		break; /* found */
	}
	if (j==glen) /* not found */
	    continue;
	/* 7. For each rule-list entry found, process all rules, in order,
	   until a rule that matches the requested access operation is
	   found. 
	*/
	if (xpath_vec(xrlist, "rule", &rvec, &rlen) < 0)
	    goto done;
	for (j=0; j<rlen; j++){
	    xrule = rvec[j];
	    /* -1 error, 0 deny, 1 permit, 2 continue */
	    if ((ret = nacm_match_rule(h, name, xrule, cbret)) < 0)
		goto done;
	    switch(ret){
	    case 0: /* deny */
		goto deny;
		break;
	    case 1: /* permit */
		goto permit;
		break;
	    case 2: /* no match, continue */
		break;
	    }
	}
    }
 step10:
    /*   10.  If the requested protocol operation is defined in a YANG module
        advertised in the server capabilities and the "rpc" statement
        contains a "nacm:default-deny-all" statement, then the protocol
        operation is denied. */
    /* 11.  If the requested protocol operation is the NETCONF
        <kill-session> or <delete-config>, then the protocol operation
        is denied. */
    if (strcmp(name, "kill-session")==0 || strcmp(name, "delete-config")==0){
	if (netconf_access_denied(cbret, "protocol", "default deny") < 0)
	    goto done;
	goto deny;
    }
    /*   12.  If the "exec-default" leaf is set to "permit", then permit the
	 protocol operation; otherwise, deny the request. */
    if (exec_default ==NULL || strcmp(exec_default, "permit")==0)
	goto permit;
    if (netconf_access_denied(cbret, "protocol", "default deny") < 0)
	goto done;
    goto deny;
 permit:
    retval = 1;
 done:
    clicon_debug(1, "%s retval:%d (0:deny 1:permit)", __FUNCTION__, retval);
    if (strcmp(mode, "internal")==0 && xtop)
	xml_free(xtop);
    if (gvec)
	free(gvec);
    if (rlistvec)
	free(rlistvec);
    if (rvec)
	free(rvec);
    return retval;
 deny: /* Here, cbret must contain a netconf error msg */
    assert(cbuf_len(cbret));
    retval = 0;
    goto done;
}

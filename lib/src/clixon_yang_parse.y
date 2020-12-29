/*
 *
  ***** BEGIN LICENSE BLOCK *****
 
  Copyright (C) 2009-2020 Olof Hagsand
  Copyright (C) 2020 Olof Hagsand and Rubicon Communications, LLC(Netgate)

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

 * Yang parser. Hopefully useful but not complete
 * @see https://tools.ietf.org/html/rfc6020 YANG 1.0
 * @see https://tools.ietf.org/html/rfc7950 YANG 1.1
 *
 * How identifiers map
 * IDENTIFIER     = [A-Za-z_][A-Za-z0-9_\-\.]
 * prefix         = IDENTIFIER
 * identifier_arg = IDENTIFIER
 * identifier_ref = prefix : IDENTIFIER
 * node_identier  = prefix : IDENTIFIER
 *
 * Missing args (just strings);
 * - length-arg-str
 * - path-arg-str
 * - date-arg-str
 */

%start file

%union {
    char *string;
}

%token MY_EOF 
%token SQ           /* Single quote: ' */
%token SEP          /* Separators (at least one) */
%token <string>   CHARS
%token <string>   IDENTIFIER
%token <string>   BOOL
%token <string>   INT

%type <string>    ustring
%type <string>    qstrings
%type <string>    qstring
%type <string>    string
%type <string>    integer_value_str
%type <string>    identifier_ref
%type <string>    abs_schema_nodeid
%type <string>    desc_schema_nodeid_strs
%type <string>    desc_schema_nodeid_str
%type <string>    desc_schema_nodeid
%type <string>    node_identifier
%type <string>    identifier_str
%type <string>    identifier_ref_str
%type <string>    bool_str


/* rfc 6020 keywords 
   See also enum rfc_6020 in clicon_yang.h. There, the constants have Y_ prefix instead of K_
 * Wanted to unify these (K_ and Y_) but gave up for several reasons:
 * - Dont want to expose a generated yacc file to the API
 * - Cant use the symbols in this file because yacc needs token definitions
 */
%token K_ACTION
%token K_ANYDATA
%token K_ANYXML
%token K_ARGUMENT
%token K_AUGMENT
%token K_BASE
%token K_BELONGS_TO
%token K_BIT
%token K_CASE
%token K_CHOICE
%token K_CONFIG
%token K_CONTACT
%token K_CONTAINER
%token K_DEFAULT
%token K_DESCRIPTION
%token K_DEVIATE
%token K_DEVIATION
%token K_ENUM
%token K_ERROR_APP_TAG
%token K_ERROR_MESSAGE
%token K_EXTENSION
%token K_FEATURE
%token K_FRACTION_DIGITS
%token K_GROUPING
%token K_IDENTITY
%token K_IF_FEATURE
%token K_IMPORT
%token K_INCLUDE
%token K_INPUT
%token K_KEY
%token K_LEAF
%token K_LEAF_LIST
%token K_LENGTH
%token K_LIST
%token K_MANDATORY
%token K_MAX_ELEMENTS
%token K_MIN_ELEMENTS
%token K_MODIFIER
%token K_MODULE
%token K_MUST
%token K_NAMESPACE
%token K_NOTIFICATION
%token K_ORDERED_BY
%token K_ORGANIZATION
%token K_OUTPUT
%token K_PATH
%token K_PATTERN
%token K_POSITION
%token K_PREFIX
%token K_PRESENCE
%token K_RANGE
%token K_REFERENCE
%token K_REFINE
%token K_REQUIRE_INSTANCE
%token K_REVISION
%token K_REVISION_DATE
%token K_RPC
%token K_STATUS
%token K_SUBMODULE
%token K_TYPE
%token K_TYPEDEF
%token K_UNIQUE
%token K_UNITS
%token K_USES
%token K_VALUE
%token K_WHEN
%token K_YANG_VERSION
%token K_YIN_ELEMENT


%lex-param     {void *_yy} /* Add this argument to parse() and lex() function */
%parse-param   {void *_yy}

%{
/* Here starts user C-code */

/* typecast macro */
#define _YY ((clixon_yang_yacc *)_yy)

#define _YYERROR(msg) {clicon_debug(1, "YYERROR %s '%s' %d", (msg), clixon_yang_parsetext, _YY->yy_linenum); YYERROR;}

/* add _yy to error parameters */
#define YY_(msgid) msgid 

#include "clixon_config.h"

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <net/if.h>

#include <cligen/cligen.h>

#include "clixon_queue.h"
#include "clixon_hash.h"
#include "clixon_handle.h"
#include "clixon_err.h"
#include "clixon_log.h"
#include "clixon_yang.h"
#include "clixon_yang_parse_lib.h"
#include "clixon_yang_parse.h"

extern int clixon_yang_parseget_lineno  (void);

/* 
   clixon_yang_parseerror
   also called from yacc generated code *
*/
void 
clixon_yang_parseerror(void *_yy,
		       char *s) 
{ 
    clicon_err(OE_YANG, 0, "%s on line %d: %s at or before: '%s'", 
	       _YY->yy_name,
	       _YY->yy_linenum ,
	       s, 
	       clixon_yang_parsetext); 
  return;
}

int
    yang_parse_init(clixon_yang_yacc *yy)
{
    return 0;
}


int
yang_parse_exit(clixon_yang_yacc *yy)
{
    return 0;
}

/*! Pop a yang parse context on stack
 * @param[in]  yy        Yang yacc argument
 */
int
ystack_pop(clixon_yang_yacc *yy)
{
    struct ys_stack *ystack; 

    if ((ystack = yy->yy_stack) == NULL){
	clicon_err(OE_YANG, 0, "ystack is NULL");
	return -1;
    }
    yy->yy_stack = ystack->ys_next;
    free(ystack);
    return 0;
}

/*! Push a yang parse context on stack
 * @param[in]  yy        Yang yacc argument
 * @param[in]  yn        Yang node to push
 */
struct ys_stack *
ystack_push(clixon_yang_yacc *yy,
	    yang_stmt        *yn)
{
    struct ys_stack *ystack; 

    if ((ystack = malloc(sizeof(*ystack))) == NULL) {
	clicon_err(OE_YANG, errno, "malloc");
	return NULL;
    }
    memset(ystack, 0, sizeof(*ystack));
    ystack->ys_node = yn;
    ystack->ys_next = yy->yy_stack;
    yy->yy_stack = ystack;
    return ystack;
}

/*! Add a yang statement to existing top-of-stack.
 *
 * @param[in]  yy        Yang yacc argument
 * @param[in]  keyword   Yang keyword
 * @param[in]  argument  Yang argument
 * @param[in]  extra     Yang extra for cornercases (unknown/extension)

 * @note consumes 'argument' and 'extra' which assumes it is malloced and not freed by caller
 */
static yang_stmt *
ysp_add(clixon_yang_yacc *yy, 
	enum rfc_6020     keyword, 
	char             *argument,
    	char             *extra)
{
    struct ys_stack *ystack = yy->yy_stack;
    yang_stmt       *ys = NULL;
    yang_stmt       *yn;
 
    ystack = yy->yy_stack;
    if (ystack == NULL){
	clicon_err(OE_YANG, errno, "No stack");
	goto err;
    }
    if ((yn = ystack->ys_node) == NULL){
	clicon_err(OE_YANG, errno, "No ys_node");
	goto err;
    }
    if ((ys = ys_new(keyword)) == NULL)
	goto err;
    /* NOTE: does not make a copy of string, ie argument is 'consumed' here */
    yang_argument_set(ys, argument);
    if (yn_insert(yn, ys) < 0) /* Insert into hierarchy */
	goto err; 
    if (ys_parse_sub(ys, extra) < 0)     /* Check statement-specific syntax */
	goto err2; /* dont free since part of tree */
//  done:
    return ys;
  err:
    if (ys)
	ys_free(ys);
  err2:
    return NULL;
}

/*! Add a yang statement to existing top-of-stack and then push it on stack
 *
 * @param[in]  yy        Yang yacc argument
 * @param[in]  keyword   Yang keyword
 * @param[in]  argument  Yang argument
 * @param[in]  extra     Yang extra for cornercases (unknown/extension)
 */
static yang_stmt *
ysp_add_push(clixon_yang_yacc *yy,
	     enum rfc_6020     keyword, 
	     char             *argument,
    	     char             *extra)
{
    yang_stmt *ys;

    if ((ys = ysp_add(yy, keyword, argument, extra)) == NULL)
	return NULL;
    if (ystack_push(yy, ys) == NULL)
	return NULL;
    return ys;
}

/*! Join two string with delimiter.
 * @param[in] str1   string 1 (will be freed) (optional)
 * @param[in] del    delimiter string (not freed) cannot be NULL (but "")
 * @param[in] str2   string 2 (will be freed)
 */
static char*
string_del_join(char *str1,
		char *del,
		char *str2)
{
    char *str;
    int   len;
    
    len = strlen(str2) + 1;

    if (str1)
	len += strlen(str1);
    len += strlen(del);
    if ((str = malloc(len)) == NULL){
	clicon_err(OE_UNIX, errno, "malloc");
	return NULL;
    }
    if (str1){
	snprintf(str, len, "%s%s%s", str1, del, str2);
	free(str1);
    }
    else
	snprintf(str, len, "%s%s", del, str2);
    free(str2);
    return str;
}

%} 
 
%%

/*
   statement = keyword [argument] (";" / "{" *statement "}") 
   The argument is a string
   recursion: right is wrong
   Let subststmt rules contain an empty rule, but not stmt rules
*/

file          : module_stmt MY_EOF
                       { clicon_debug(3,"file->module-stmt"); YYACCEPT; } 
              | submodule_stmt MY_EOF
                       { clicon_debug(3,"file->submodule-stmt"); YYACCEPT; } 
              ;

/* module identifier-arg-str */
module_stmt   : K_MODULE identifier_str 
                  { if ((_YY->yy_module = ysp_add_push(_yy, Y_MODULE, $2, NULL)) == NULL) _YYERROR("module_stmt");
                        } 
                '{' module_substmts '}' 
                  { if (ystack_pop(_yy) < 0) _YYERROR("module_stmt");
		    clicon_debug(3,"module_stmt -> id-arg-str { module-substmts }");} 
              ;

module_substmts : module_substmts module_substmt 
                      {clicon_debug(3,"module-substmts -> module-substmts module-substm");} 
              | module_substmt 
                      { clicon_debug(3,"module-substmts ->");} 
              ;

module_substmt : module_header_stmts { clicon_debug(3,"module-substmt -> module-header-stmts");}
               | linkage_stmts       { clicon_debug(3,"module-substmt -> linake-stmts");} 
               | meta_stmts          { clicon_debug(3,"module-substmt -> meta-stmts");} 
               | revision_stmts      { clicon_debug(3,"module-substmt -> revision-stmts");} 
               | body_stmts          { clicon_debug(3,"module-substmt -> body-stmts");} 
               | unknown_stmt        { clicon_debug(3,"module-substmt -> unknown-stmt");} 
               |                     { clicon_debug(3,"module-substmt ->");} 
               ;

/* submodule */
submodule_stmt : K_SUBMODULE identifier_str 
                    { if ((_YY->yy_module = ysp_add_push(_yy, Y_SUBMODULE, $2, NULL)) == NULL) _YYERROR("submodule_stmt"); }
                '{' submodule_substmts '}'
                    { if (ystack_pop(_yy) < 0) _YYERROR("submodule_stmt");
			clicon_debug(3,"submodule_stmt -> id-arg-str { submodule-substmts }");} 
              ;

submodule_substmts : submodule_substmts submodule_substmt 
                       { clicon_debug(3,"submodule-stmts -> submodule-substmts submodule-substmt"); }
              | submodule_substmt       
                       { clicon_debug(3,"submodule-stmts -> submodule-substmt"); }
              ;

submodule_substmt : submodule_header_stmts 
                              { clicon_debug(3,"submodule-substmt -> submodule-header-stmts"); }
               | linkage_stmts  { clicon_debug(3,"submodule-substmt -> linake-stmts");} 
               | meta_stmts     { clicon_debug(3,"submodule-substmt -> meta-stmts");} 
               | revision_stmts { clicon_debug(3,"submodule-substmt -> revision-stmts");} 
               | body_stmts     { clicon_debug(3,"submodule-stmt -> body-stmts"); }
               | unknown_stmt   { clicon_debug(3,"submodule-substmt -> unknown-stmt");} 
               |                { clicon_debug(3,"submodule-substmt ->");} 
              ;

/* linkage */
linkage_stmts : linkage_stmts linkage_stmt 
                       { clicon_debug(3,"linkage-stmts -> linkage-stmts linkage-stmt"); }
              | linkage_stmt
                       { clicon_debug(3,"linkage-stmts -> linkage-stmt"); }
              ;

linkage_stmt  : import_stmt  { clicon_debug(3,"linkage-stmt -> import-stmt"); }
              | include_stmt { clicon_debug(3,"linkage-stmt -> include-stmt"); }
              ;

/* module-header */
module_header_stmts : module_header_stmts module_header_stmt
                  { clicon_debug(3,"module-header-stmts -> module-header-stmts module-header-stmt"); }
              | module_header_stmt   { clicon_debug(3,"module-header-stmts -> "); }
              ;

module_header_stmt : yang_version_stmt 
                               { clicon_debug(3,"module-header-stmt -> yang-version-stmt"); }
              | namespace_stmt { clicon_debug(3,"module-header-stmt -> namespace-stmt"); }
              | prefix_stmt    { clicon_debug(3,"module-header-stmt -> prefix-stmt"); }
              ;

/* submodule-header */
submodule_header_stmts : submodule_header_stmts submodule_header_stmt
                  { clicon_debug(3,"submodule-header-stmts -> submodule-header-stmts submodule-header-stmt"); }
              | submodule_header_stmt   
                  { clicon_debug(3,"submodule-header-stmts -> submodule-header-stmt"); }
              ;

submodule_header_stmt : yang_version_stmt 
                  { clicon_debug(3,"submodule-header-stmt -> yang-version-stmt"); }
              | belongs_to_stmt { clicon_debug(3,"submodule-header-stmt -> belongs-to-stmt"); }
              ;

/* yang-version-stmt = yang-version-keyword  yang-version-arg-str */
yang_version_stmt : K_YANG_VERSION string stmtend
		{ if (ysp_add(_yy, Y_YANG_VERSION, $2, NULL) == NULL) _YYERROR("yang_version_stmt");
                            clicon_debug(3,"yang-version-stmt -> YANG-VERSION string"); }
              ;

/* import */
import_stmt   : K_IMPORT identifier_str
                     { if (ysp_add_push(_yy, Y_IMPORT, $2, NULL) == NULL) _YYERROR("import_stmt"); }
                '{' import_substmts '}' 
                     { if (ystack_pop(_yy) < 0) _YYERROR("import_stmt");
		       clicon_debug(3,"import-stmt -> IMPORT id-arg-str { import-substmts }");} 
              ;

import_substmts : import_substmts import_substmt 
                      { clicon_debug(3,"import-substmts -> import-substmts import-substm");} 
              | import_substmt 
                      { clicon_debug(3,"import-substmts ->");} 
              ;

import_substmt : prefix_stmt {  clicon_debug(3,"import-stmt -> prefix-stmt"); }
               | revision_date_stmt {  clicon_debug(3,"import-stmt -> revision-date-stmt"); }
               | description_stmt   { clicon_debug(3,"import-stmt -> description-stmt"); }
               | reference_stmt {  clicon_debug(3,"import-stmt -> reference-stmt"); }
              ;

include_stmt  : K_INCLUDE identifier_str ';'
		{ if (ysp_add(_yy, Y_INCLUDE, $2, NULL)== NULL) _YYERROR("include_stmt"); 
                           clicon_debug(3,"include-stmt -> id-str"); }
              | K_INCLUDE identifier_str
	      { if (ysp_add_push(_yy, Y_INCLUDE, $2, NULL) == NULL) _YYERROR("include_stmt"); }
	      '{' include_substmts '}'
                { if (ystack_pop(_yy) < 0) _YYERROR("include_stmt");
                  clicon_debug(3,"include-stmt -> id-str { include-substmts }"); }
              ;

include_substmts : include_substmts include_substmt 
                      { clicon_debug(3,"include-substmts -> include-substmts include-substm");} 
              | include_substmt 
                      { clicon_debug(3,"include-substmts ->");} 
              ;

include_substmt : revision_date_stmt {  clicon_debug(3,"include-stmt -> revision-date-stmt"); }
                | description_stmt   { clicon_debug(3,"include-stmt -> description-stmt"); }
                | reference_stmt {  clicon_debug(3,"include-stmt -> reference-stmt"); }
               ;


/* namespace-stmt = namespace-keyword sep uri-str */
namespace_stmt : K_NAMESPACE string stmtend  
		{ if (ysp_add(_yy, Y_NAMESPACE, $2, NULL)== NULL) _YYERROR("namespace_stmt"); 
                            clicon_debug(3,"namespace-stmt -> NAMESPACE string"); }
              ;

prefix_stmt   : K_PREFIX identifier_str stmtend /* XXX prefix-arg-str */
		{ if (ysp_add(_yy, Y_PREFIX, $2, NULL)== NULL) _YYERROR("prefix_stmt"); 
			     clicon_debug(3,"prefix-stmt -> PREFIX string ;");}
              ;

belongs_to_stmt : K_BELONGS_TO identifier_str 
                    { if (ysp_add_push(_yy, Y_BELONGS_TO, $2, NULL) == NULL) _YYERROR("belongs_to_stmt"); }

                  '{' prefix_stmt '}'
                    { if (ystack_pop(_yy) < 0) _YYERROR("belongs_to_stmt");
		      clicon_debug(3,"belongs-to-stmt -> BELONGS-TO id-arg-str { prefix-stmt } ");
			}
                 ;

organization_stmt: K_ORGANIZATION string stmtend
		{ if (ysp_add(_yy, Y_ORGANIZATION, $2, NULL)== NULL) _YYERROR("belongs_to_stmt"); 
			   clicon_debug(3,"organization-stmt -> ORGANIZATION string ;");}
              ;

contact_stmt  : K_CONTACT string stmtend
		{ if (ysp_add(_yy, Y_CONTACT, $2, NULL)== NULL) _YYERROR("contact_stmt"); 
                            clicon_debug(3,"contact-stmt -> CONTACT string"); }
              ;

description_stmt : K_DESCRIPTION string stmtend
		{ if (ysp_add(_yy, Y_DESCRIPTION, $2, NULL)== NULL) _YYERROR("description_stmt"); 
			   clicon_debug(3,"description-stmt -> DESCRIPTION string ;");}
              ;

reference_stmt : K_REFERENCE string stmtend
		{ if (ysp_add(_yy, Y_REFERENCE, $2, NULL)== NULL) _YYERROR("reference_stmt"); 
			   clicon_debug(3,"reference-stmt -> REFERENCE string ;");}
              ;

units_stmt    : K_UNITS string ';'
		{ if (ysp_add(_yy, Y_UNITS, $2, NULL)== NULL) _YYERROR("units_stmt"); 
                            clicon_debug(3,"units-stmt -> UNITS string"); }
              ;

revision_stmt : K_REVISION string ';'  /* XXX date-arg-str */
		{ if (ysp_add(_yy, Y_REVISION, $2, NULL) == NULL) _YYERROR("revision_stmt"); 
			 clicon_debug(3,"revision-stmt -> date-arg-str ;"); }
              | K_REVISION string 
	      { if (ysp_add_push(_yy, Y_REVISION, $2, NULL) == NULL) _YYERROR("revision_stmt"); }
                '{' revision_substmts '}'  /* XXX date-arg-str */
                     { if (ystack_pop(_yy) < 0) _YYERROR("revision_stmt");
		       clicon_debug(3,"revision-stmt -> date-arg-str { revision-substmts  }"); }
              ;

revision_substmts : revision_substmts revision_substmt 
                     { clicon_debug(3,"revision-substmts -> revision-substmts revision-substmt }"); }
              | revision_substmt
                     { clicon_debug(3,"revision-substmts -> }"); }
              ;

revision_substmt : description_stmt { clicon_debug(3,"revision-substmt -> description-stmt"); }
              | reference_stmt      { clicon_debug(3,"revision-substmt -> reference-stmt"); }
              | unknown_stmt        { clicon_debug(3,"revision-substmt -> unknown-stmt");} 
              |                     { clicon_debug(3,"revision-substmt -> "); }
              ;


/* revision */
revision_stmts : revision_stmts revision_stmt 
                       { clicon_debug(3,"revision-stmts -> revision-stmts revision-stmt"); }
              | revision_stmt
                       { clicon_debug(3,"revision-stmts -> "); }
              ;

revision_date_stmt : K_REVISION_DATE string stmtend  /* XXX date-arg-str */
		{ if (ysp_add(_yy, Y_REVISION_DATE, $2, NULL) == NULL) _YYERROR("revision_date_stmt"); 
			 clicon_debug(3,"revision-date-stmt -> date;"); }
              ;

extension_stmt : K_EXTENSION identifier_str ';' 
	       { if (ysp_add(_yy, Y_EXTENSION, $2, NULL) == NULL) _YYERROR("extension_stmt");
                    clicon_debug(3,"extenstion-stmt -> EXTENSION id-str ;"); }
              | K_EXTENSION identifier_str 
 	        { if (ysp_add_push(_yy, Y_EXTENSION, $2, NULL) == NULL) _YYERROR("extension_stmt"); }
	       '{' extension_substmts '}' 
	         { if (ystack_pop(_yy) < 0) _YYERROR("extension_stmt");
                    clicon_debug(3,"extension-stmt -> EXTENSION id-str { extension-substmts }"); }
	      ;

/* extension substmts */
extension_substmts : extension_substmts extension_substmt 
                  { clicon_debug(3,"extension-substmts -> extension-substmts extension-substmt"); }
              | extension_substmt 
                  { clicon_debug(3,"extension-substmts -> extension-substmt"); }
              ;

extension_substmt : argument_stmt    { clicon_debug(3,"extension-substmt -> argument-stmt"); }
              | status_stmt          { clicon_debug(3,"extension-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"extension-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"extension-substmt -> reference-stmt"); }
              | unknown_stmt         { clicon_debug(3,"extension-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"extension-substmt -> "); }
              ;

argument_stmt  : K_ARGUMENT identifier_str ';'
               { if (ysp_add(_yy, Y_ARGUMENT, $2, NULL) == NULL) _YYERROR("argument_stmt");
			 clicon_debug(3,"argument-stmt -> ARGUMENT identifier ;"); }
               | K_ARGUMENT identifier_str
	       { if (ysp_add_push(_yy, Y_ARGUMENT, $2, NULL) == NULL) _YYERROR("argument_stmt"); }
                '{' argument_substmts '}'
                       { if (ystack_pop(_yy) < 0) _YYERROR("argument_stmt");
	                 clicon_debug(3,"argument-stmt -> ARGUMENT { argument-substmts }"); }
               ;

/* argument substmts */
argument_substmts : argument_substmts argument_substmt 
                      { clicon_debug(3,"argument-substmts -> argument-substmts argument-substmt"); }
                  | argument_substmt 
                      { clicon_debug(3,"argument-substmts -> argument-substmt"); }
                  ;

argument_substmt : yin_element_stmt1 { clicon_debug(3,"argument-substmt -> yin-element-stmt1");}
                 | unknown_stmt   { clicon_debug(3,"argument-substmt -> unknown-stmt");}
                 ;


/* Example of optional rule, eg [yin-element-stmt] */
yin_element_stmt1 : K_YIN_ELEMENT bool_str stmtend {free($2);}
               ;

/* Identity */
identity_stmt  : K_IDENTITY identifier_str ';' 
	      { if (ysp_add(_yy, Y_IDENTITY, $2, NULL) == NULL) _YYERROR("identity_stmt"); 
			   clicon_debug(3,"identity-stmt -> IDENTITY string ;"); }

              | K_IDENTITY identifier_str
	      { if (ysp_add_push(_yy, Y_IDENTITY, $2, NULL) == NULL) _YYERROR("identity_stmt"); }
	       '{' identity_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("identity_stmt");
			     clicon_debug(3,"identity-stmt -> IDENTITY string { identity-substmts }"); }
              ;

identity_substmts : identity_substmts identity_substmt 
                      { clicon_debug(3,"identity-substmts -> identity-substmts identity-substmt"); }
              | identity_substmt 
                      { clicon_debug(3,"identity-substmts -> identity-substmt"); }
              ;

identity_substmt : if_feature_stmt   { clicon_debug(3,"identity-substmt -> if-feature-stmt"); }
              | base_stmt            { clicon_debug(3,"identity-substmt -> base-stmt"); }
              | status_stmt          { clicon_debug(3,"identity-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"identity-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"identity-substmt -> reference-stmt"); }
              | unknown_stmt         { clicon_debug(3,"identity-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"identity-substmt -> "); }
              ;

base_stmt     : K_BASE identifier_ref_str stmtend
		{ if (ysp_add(_yy, Y_BASE, $2, NULL)== NULL) _YYERROR("base_stmt"); 
                            clicon_debug(3,"base-stmt -> BASE identifier-ref-arg-str"); }
              ;

/* Feature */
feature_stmt  : K_FEATURE identifier_str ';' 
	       { if (ysp_add(_yy, Y_FEATURE, $2, NULL) == NULL) _YYERROR("feature_stmt");
		      clicon_debug(3,"feature-stmt -> FEATURE id-arg-str ;"); }
              | K_FEATURE identifier_str
	      { if (ysp_add_push(_yy, Y_FEATURE, $2, NULL) == NULL) _YYERROR("feature_stmt"); }
              '{' feature_substmts '}' 
                  { if (ystack_pop(_yy) < 0) _YYERROR("feature_stmt");
                    clicon_debug(3,"feature-stmt -> FEATURE id-arg-str { feature-substmts }"); }
              ;

/* feature substmts */
feature_substmts : feature_substmts feature_substmt 
                      { clicon_debug(3,"feature-substmts -> feature-substmts feature-substmt"); }
              | feature_substmt 
                      { clicon_debug(3,"feature-substmts -> feature-substmt"); }
              ;

feature_substmt : if_feature_stmt    { clicon_debug(3,"feature-substmt -> if-feature-stmt"); }
              | status_stmt          { clicon_debug(3,"feature-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"feature-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"feature-substmt -> reference-stmt"); }
              | unknown_stmt         { clicon_debug(3,"feature-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"feature-substmt -> "); }
              ;

/* if-feature-stmt = if-feature-keyword sep if-feature-expr-str */
if_feature_stmt : K_IF_FEATURE string stmtend 
		{ if (ysp_add(_yy, Y_IF_FEATURE, $2, NULL) == NULL) _YYERROR("if_feature_stmt"); 
                            clicon_debug(3,"if-feature-stmt -> IF-FEATURE identifier-ref-arg-str"); }
              ;

/* Typedef */
typedef_stmt  : K_TYPEDEF identifier_str 
                 { if (ysp_add_push(_yy, Y_TYPEDEF, $2, NULL) == NULL) _YYERROR("typedef_stmt"); }
	       '{' typedef_substmts '}' 
                 { if (ystack_pop(_yy) < 0) _YYERROR("typedef_stmt");
		   clicon_debug(3,"typedef-stmt -> TYPEDEF id-arg-str { typedef-substmts }"); }
              ;

typedef_substmts : typedef_substmts typedef_substmt 
                      { clicon_debug(3,"typedef-substmts -> typedef-substmts typedef-substmt"); }
              | typedef_substmt 
                      { clicon_debug(3,"typedef-substmts -> typedef-substmt"); }
              ;

typedef_substmt : type_stmt          { clicon_debug(3,"typedef-substmt -> type-stmt"); }
              | units_stmt           { clicon_debug(3,"typedef-substmt -> units-stmt"); }
              | default_stmt         { clicon_debug(3,"typedef-substmt -> default-stmt"); }
              | status_stmt          { clicon_debug(3,"typedef-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"typedef-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"typedef-substmt -> reference-stmt"); }
              | unknown_stmt         { clicon_debug(3,"typedef-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"typedef-substmt -> "); }
              ;

/* Type */
type_stmt     : K_TYPE identifier_ref_str ';' 
	       { if (ysp_add(_yy, Y_TYPE, $2, NULL) == NULL) _YYERROR("type_stmt"); 
			   clicon_debug(3,"type-stmt -> TYPE identifier-ref-arg-str ;");}
              | K_TYPE identifier_ref_str
	      { if (ysp_add_push(_yy, Y_TYPE, $2, NULL) == NULL) _YYERROR("type_stmt"); 
			 }
                '{' type_body_stmts '}'
                         { if (ystack_pop(_yy) < 0) _YYERROR("type_stmt");
                           clicon_debug(3,"type-stmt -> TYPE identifier-ref-arg-str { type-body-stmts }");}
              ;

/* type-body-stmts is a little special since it is a choice of
   sub-specifications that are all lists. One could model it as a list of 
   type-body-stmts and each individual specification as a simple.
 */
type_body_stmts : type_body_stmts type_body_stmt
                         { clicon_debug(3,"type-body-stmts -> type-body-stmts type-body-stmt"); }
              | 
                         { clicon_debug(3,"type-body-stmts -> "); }
              ;

type_body_stmt/* numerical-restrictions */ 
              : range_stmt             { clicon_debug(3,"type-body-stmt -> range-stmt"); }
              /* decimal64-specification */ 
              | fraction_digits_stmt   { clicon_debug(3,"type-body-stmt -> fraction-digits-stmt"); }
              /* string-restrictions */ 
              | length_stmt           { clicon_debug(3,"type-body-stmt -> length-stmt"); }
              | pattern_stmt          { clicon_debug(3,"type-body-stmt -> pattern-stmt"); }
              /* enum-specification */ 
              | enum_stmt             { clicon_debug(3,"type-body-stmt -> enum-stmt"); }
              /* leafref-specifications */
              | path_stmt             { clicon_debug(3,"type-body-stmt -> path-stmt"); }
              | require_instance_stmt { clicon_debug(3,"type-body-stmt -> require-instance-stmt"); }
              /* identityref-specification */
              | base_stmt             { clicon_debug(3,"type-body-stmt -> base-stmt"); }
              /* instance-identifier-specification (see require-instance-stmt above */
              /* bits-specification */
              | bit_stmt               { clicon_debug(3,"type-body-stmt -> bit-stmt"); }
              /* union-specification */
              | type_stmt              { clicon_debug(3,"type-body-stmt -> type-stmt"); }
/* Cisco uses this (eg Cisco-IOS-XR-sysadmin-nto-misc-set-hostname.yang) but I dont see this is in the RFC */
              | unknown_stmt           { clicon_debug(3,"type-body-stmt -> unknown-stmt");} 
              ;

/* range-stmt */
range_stmt   : K_RANGE string ';' /* XXX range-arg-str */
	       { if (ysp_add(_yy, Y_RANGE, $2, NULL) == NULL) _YYERROR("range_stmt"); 
			   clicon_debug(3,"range-stmt -> RANGE string ;"); }

              | K_RANGE string
	      { if (ysp_add_push(_yy, Y_RANGE, $2, NULL) == NULL) _YYERROR("range_stmt"); }
	       '{' range_substmts '}' 
                          { if (ystack_pop(_yy) < 0) _YYERROR("range_stmt");
			     clicon_debug(3,"range-stmt -> RANGE string { range-substmts }"); }
              ;

range_substmts : range_substmts range_substmt 
                      { clicon_debug(3,"range-substmts -> range-substmts range-substmt"); }
              | range_substmt 
                      { clicon_debug(3,"range-substmts -> range-substmt"); }
              ;

range_substmt : error_message_stmt   { clicon_debug(3,"range-substmt -> error-message-stmt");} 
              | description_stmt     { clicon_debug(3,"range-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"range-substmt -> reference-stmt"); }
              | unknown_stmt         { clicon_debug(3,"range-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"range-substmt -> "); }
              ;

/* fraction-digits-stmt = fraction-digits-keyword fraction-digits-arg-str */
fraction_digits_stmt : K_FRACTION_DIGITS string stmtend 
		{ if (ysp_add(_yy, Y_FRACTION_DIGITS, $2, NULL) == NULL) _YYERROR("fraction_digits_stmt"); 
                            clicon_debug(3,"fraction-digits-stmt -> FRACTION-DIGITS string"); }
              ;

/* meta */
meta_stmts    : meta_stmts meta_stmt { clicon_debug(3,"meta-stmts -> meta-stmts meta-stmt"); }
              | meta_stmt            { clicon_debug(3,"meta-stmts -> meta-stmt"); }
              ;

meta_stmt     : organization_stmt    { clicon_debug(3,"meta-stmt -> organization-stmt"); }
              | contact_stmt         { clicon_debug(3,"meta-stmt -> contact-stmt"); }
              | description_stmt     { clicon_debug(3,"meta-stmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"meta-stmt -> reference-stmt"); }
              ;


/* length-stmt */
length_stmt   : K_LENGTH string ';' /* XXX length-arg-str */
	       { if (ysp_add(_yy, Y_LENGTH, $2, NULL) == NULL) _YYERROR("length_stmt"); 
			   clicon_debug(3,"length-stmt -> LENGTH string ;"); }

              | K_LENGTH string
	      { if (ysp_add_push(_yy, Y_LENGTH, $2, NULL) == NULL) _YYERROR("length_stmt"); }
	       '{' length_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("length_stmt");
			     clicon_debug(3,"length-stmt -> LENGTH string { length-substmts }"); }
              ;

length_substmts : length_substmts length_substmt 
                      { clicon_debug(3,"length-substmts -> length-substmts length-substmt"); }
              | length_substmt 
                      { clicon_debug(3,"length-substmts -> length-substmt"); }
              ;

length_substmt : error_message_stmt  { clicon_debug(3,"length-substmt -> error-message-stmt");} 
              | description_stmt     { clicon_debug(3,"length-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"length-substmt -> reference-stmt"); }
              | unknown_stmt         { clicon_debug(3,"length-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"length-substmt -> "); }
              ;

/* Pattern */
pattern_stmt  : K_PATTERN string ';' 
	       { if (ysp_add(_yy, Y_PATTERN, $2, NULL) == NULL) _YYERROR("pattern_stmt"); 
			   clicon_debug(3,"pattern-stmt -> PATTERN string ;"); }

              | K_PATTERN string
	      { if (ysp_add_push(_yy, Y_PATTERN, $2, NULL) == NULL) _YYERROR("pattern_stmt"); }
	       '{' pattern_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("pattern_stmt");
			     clicon_debug(3,"pattern-stmt -> PATTERN string { pattern-substmts }"); }
              ;

pattern_substmts : pattern_substmts pattern_substmt 
                      { clicon_debug(3,"pattern-substmts -> pattern-substmts pattern-substmt"); }
              | pattern_substmt 
                      { clicon_debug(3,"pattern-substmts -> pattern-substmt"); }
              ;

pattern_substmt : modifier_stmt    { clicon_debug(3,"pattern-substmt -> modifier-stmt");}
              | error_message_stmt { clicon_debug(3,"pattern-substmt -> error-message-stmt");}
              | error_app_tag_stmt { clicon_debug(3,"pattern-substmt -> error-app-tag-stmt");} 
              | description_stmt   { clicon_debug(3,"pattern-substmt -> description-stmt");}
              | reference_stmt     { clicon_debug(3,"pattern-substmt -> reference-stmt"); }
              | unknown_stmt       { clicon_debug(3,"pattern-substmt -> unknown-stmt");} 

              |                      { clicon_debug(3,"pattern-substmt -> "); }
              ;

modifier_stmt  : K_MODIFIER string stmtend
		{ if (ysp_add(_yy, Y_MODIFIER, $2, NULL)== NULL) _YYERROR("modifier_stmt"); 
                            clicon_debug(3,"modifier-stmt -> MODIFIER string"); }
              ;

default_stmt  : K_DEFAULT string stmtend
		{ if (ysp_add(_yy, Y_DEFAULT, $2, NULL)== NULL) _YYERROR("default_stmt"); 
                            clicon_debug(3,"default-stmt -> DEFAULT string"); }
              ;

/* enum-stmt */
enum_stmt     : K_ENUM string ';'
	       { if (ysp_add(_yy, Y_ENUM, $2, NULL) == NULL) _YYERROR("enum_stmt"); 
			   clicon_debug(3,"enum-stmt -> ENUM string ;"); }
              | K_ENUM string
	      { if (ysp_add_push(_yy, Y_ENUM, $2, NULL) == NULL) _YYERROR("enum_stmt"); }
	       '{' enum_substmts '}' 
                         { if (ystack_pop(_yy) < 0) _YYERROR("enum_stmt");
			   clicon_debug(3,"enum-stmt -> ENUM string { enum-substmts }"); }
              ;

enum_substmts : enum_substmts enum_substmt 
                      { clicon_debug(3,"enum-substmts -> enum-substmts enum-substmt"); }
              | enum_substmt 
                      { clicon_debug(3,"enum-substmts -> enum-substmt"); }
              ;

enum_substmt  : if_feature_stmt      { clicon_debug(3,"enum-substmt -> if-feature-stmt"); }
              | value_stmt           { clicon_debug(3,"enum-substmt -> value-stmt"); }
              | status_stmt          { clicon_debug(3,"enum-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"enum-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"enum-substmt -> reference-stmt"); }
              | unknown_stmt         { clicon_debug(3,"enum-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"enum-substmt -> "); }
              ;

path_stmt     : K_PATH string stmtend /* XXX: path-arg-str */
		{ if (ysp_add(_yy, Y_PATH, $2, NULL)== NULL) _YYERROR("path_stmt"); 
                            clicon_debug(3,"path-stmt -> PATH string"); }
              ;

require_instance_stmt : K_REQUIRE_INSTANCE bool_str stmtend
		{ if (ysp_add(_yy, Y_REQUIRE_INSTANCE, $2, NULL)== NULL) _YYERROR("require_instance_stmt"); 
                            clicon_debug(3,"require-instance-stmt -> REQUIRE-INSTANCE string"); }
              ;

/* bit-stmt */
bit_stmt     : K_BIT identifier_str ';'
	       { if (ysp_add(_yy, Y_BIT, $2, NULL) == NULL) _YYERROR("bit_stmt"); 
			   clicon_debug(3,"bit-stmt -> BIT string ;"); }
              | K_BIT identifier_str
	      { if (ysp_add_push(_yy, Y_BIT, $2, NULL) == NULL) _YYERROR("bit_stmt"); }
	       '{' bit_substmts '}' 
                         { if (ystack_pop(_yy) < 0) _YYERROR("bit_stmt");
			   clicon_debug(3,"bit-stmt -> BIT string { bit-substmts }"); }
              ;

bit_substmts : bit_substmts bit_substmt 
                      { clicon_debug(3,"bit-substmts -> bit-substmts bit-substmt"); }
              | bit_substmt 
                      { clicon_debug(3,"bit-substmts -> bit-substmt"); }
              ;

bit_substmt   : if_feature_stmt      { clicon_debug(3,"bit-substmt -> if-feature-stmt"); }
              | position_stmt        { clicon_debug(3,"bit-substmt -> positition-stmt"); }
              | status_stmt          { clicon_debug(3,"bit-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"bit-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"bit-substmt -> reference-stmt"); }
              |                      { clicon_debug(3,"bit-substmt -> "); }
              ;

/* position-stmt = position-keyword position-value-arg-str */
position_stmt : K_POSITION integer_value_str stmtend 
		{ if (ysp_add(_yy, Y_POSITION, $2, NULL) == NULL) _YYERROR("position_stmt"); 
                            clicon_debug(3,"position-stmt -> POSITION integer-value"); }
              ;

/* status-stmt = status-keyword sep status-arg-str XXX: current-keyword*/
status_stmt   : K_STATUS string stmtend
		{ if (ysp_add(_yy, Y_STATUS, $2, NULL) == NULL) _YYERROR("status_stmt"); 
                            clicon_debug(3,"status-stmt -> STATUS string"); }
              ;

config_stmt   : K_CONFIG bool_str stmtend
		{ if (ysp_add(_yy, Y_CONFIG, $2, NULL) == NULL) _YYERROR("config_stmt"); 
                            clicon_debug(3,"config-stmt -> CONFIG config-arg-str"); }
              ;

/* mandatory-stmt = mandatory-keyword mandatory-arg-str */
mandatory_stmt : K_MANDATORY bool_str stmtend
                         { yang_stmt *ys;
			     if ((ys = ysp_add(_yy, Y_MANDATORY, $2, NULL))== NULL) _YYERROR("mandatory_stmt"); 
			   clicon_debug(3,"mandatory-stmt -> MANDATORY mandatory-arg-str ;");}
              ;

presence_stmt : K_PRESENCE string stmtend
                         { yang_stmt *ys;
			     if ((ys = ysp_add(_yy, Y_PRESENCE, $2, NULL))== NULL) _YYERROR("presence_stmt"); 
			   clicon_debug(3,"presence-stmt -> PRESENCE string ;");}
              ;

/* ordered-by-stmt = ordered-by-keyword sep ordered-by-arg-str */
ordered_by_stmt : K_ORDERED_BY string stmtend
                         { yang_stmt *ys;
			     if ((ys = ysp_add(_yy, Y_ORDERED_BY, $2, NULL))== NULL) _YYERROR("ordered_by_stmt"); 
			   clicon_debug(3,"ordered-by-stmt -> ORDERED-BY ordered-by-arg ;");}
              ;

/* must-stmt */
must_stmt     : K_MUST string ';'
	       { if (ysp_add(_yy, Y_MUST, $2, NULL) == NULL) _YYERROR("must_stmt"); 
			   clicon_debug(3,"must-stmt -> MUST string ;"); }

              | K_MUST string
	      { if (ysp_add_push(_yy, Y_MUST, $2, NULL) == NULL) _YYERROR("must_stmt"); }
	       '{' must_substmts '}' 
                         { if (ystack_pop(_yy) < 0) _YYERROR("must_stmt");
			   clicon_debug(3,"must-stmt -> MUST string { must-substmts }"); }
              ;

must_substmts : must_substmts must_substmt 
                      { clicon_debug(3,"must-substmts -> must-substmts must-substmt"); }
              | must_substmt 
                      { clicon_debug(3,"must-substmts -> must-substmt"); }
              ;

must_substmt  : error_message_stmt   { clicon_debug(3,"must-substmt -> error-message-stmt"); }
              | error_app_tag_stmt   { clicon_debug(3,"must-substmt -> error-app-tag-stmt"); }
              | description_stmt     { clicon_debug(3,"must-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"must-substmt -> reference-stmt"); }
              |                      { clicon_debug(3,"must-substmt -> "); }
              ;

/* error-message-stmt */
error_message_stmt   : K_ERROR_MESSAGE string stmtend
	       { if (ysp_add(_yy, Y_ERROR_MESSAGE, $2, NULL) == NULL) _YYERROR("error_message_stmt");
	          clicon_debug(3,"error-message-stmt -> ERROR-MESSAGE string"); }
               ;

error_app_tag_stmt : K_ERROR_APP_TAG string stmtend
	       { if (ysp_add(_yy, Y_ERROR_MESSAGE, $2, NULL) == NULL) _YYERROR("error_message_stmt");
     	          clicon_debug(3,"error-app-tag-stmt -> ERROR-APP-TAG string"); }
               ;

/* min-elements-stmt = min-elements-keyword min-value-arg-str */
min_elements_stmt : K_MIN_ELEMENTS integer_value_str stmtend
		{ if (ysp_add(_yy, Y_MIN_ELEMENTS, $2, NULL)== NULL) _YYERROR("min_elements_stmt"); 
			   clicon_debug(3,"min-elements-stmt -> MIN-ELEMENTS integer ;");}
              ;

/* max-elements-stmt   = max-elements-keyword ("unbounded"|integer-value) 
 * XXX cannot use integer-value
 */
max_elements_stmt : K_MAX_ELEMENTS string stmtend
		{ if (ysp_add(_yy, Y_MAX_ELEMENTS, $2, NULL)== NULL) _YYERROR("max_elements_stmt"); 
			   clicon_debug(3,"max-elements-stmt -> MIN-ELEMENTS integer ;");}
              ;

value_stmt   : K_VALUE integer_value_str stmtend
		{ if (ysp_add(_yy, Y_VALUE, $2, NULL) == NULL) _YYERROR("value_stmt"); 
                            clicon_debug(3,"value-stmt -> VALUE integer-value"); }
              ;

/* Grouping */
grouping_stmt  : K_GROUPING identifier_str 
                    { if (ysp_add_push(_yy, Y_GROUPING, $2, NULL) == NULL) _YYERROR("grouping_stmt"); }
	       '{' grouping_substmts '}' 
                    { if (ystack_pop(_yy) < 0) _YYERROR("grouping_stmt");
			     clicon_debug(3,"grouping-stmt -> GROUPING id-arg-str { grouping-substmts }"); }
              ;

grouping_substmts : grouping_substmts grouping_substmt 
                      { clicon_debug(3,"grouping-substmts -> grouping-substmts grouping-substmt"); }
              | grouping_substmt 
                      { clicon_debug(3,"grouping-substmts -> grouping-substmt"); }
              ;

grouping_substmt : status_stmt          { clicon_debug(3,"grouping-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"grouping-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"grouping-substmt -> reference-stmt"); }
              | typedef_stmt         { clicon_debug(3,"grouping-substmt -> typedef-stmt"); }
              | grouping_stmt        { clicon_debug(3,"grouping-substmt -> grouping-stmt"); }
              | data_def_stmt        { clicon_debug(3,"grouping-substmt -> data-def-stmt"); }
              | action_stmt          { clicon_debug(3,"grouping-substmt -> action-stmt"); }
              | notification_stmt    { clicon_debug(3,"grouping-substmt -> notification-stmt"); }
              | unknown_stmt        { clicon_debug(3,"container-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"grouping-substmt -> "); }
              ;


/* container */
container_stmt : K_CONTAINER identifier_str ';'
		{ if (ysp_add(_yy, Y_CONTAINER, $2, NULL) == NULL) _YYERROR("container_stmt"); 
                             clicon_debug(3,"container-stmt -> CONTAINER id-arg-str ;");}
              | K_CONTAINER identifier_str 
	      { if (ysp_add_push(_yy, Y_CONTAINER, $2, NULL) == NULL) _YYERROR("container_stmt"); }
                '{' container_substmts '}'
                           { if (ystack_pop(_yy) < 0) _YYERROR("container_stmt");
                             clicon_debug(3,"container-stmt -> CONTAINER id-arg-str { container-substmts }");}
              ;

container_substmts : container_substmts container_substmt 
              | container_substmt 
              ;

container_substmt : when_stmt       { clicon_debug(3,"container-substmt -> when-stmt"); }
              | if_feature_stmt     { clicon_debug(3,"container-substmt -> if-feature-stmt"); }
              | must_stmt           { clicon_debug(3,"container-substmt -> must-stmt"); }
              | presence_stmt       { clicon_debug(3,"container-substmt -> presence-stmt"); }
              | config_stmt         { clicon_debug(3,"container-substmt -> config-stmt"); }
              | status_stmt         { clicon_debug(3,"container-substmt -> status-stmt"); }
              | description_stmt    { clicon_debug(3,"container-substmt -> description-stmt");} 
              | reference_stmt      { clicon_debug(3,"container-substmt -> reference-stmt"); }
              | typedef_stmt        { clicon_debug(3,"container-substmt -> typedef-stmt"); }
              | grouping_stmt       { clicon_debug(3,"container-substmt -> grouping-stmt"); }
              | data_def_stmt       { clicon_debug(3,"container-substmt -> data-def-stmt");}
              | action_stmt         { clicon_debug(3,"container-substmt -> action-stmt");} 
              | notification_stmt   { clicon_debug(3,"container-substmt -> notification-stmt");} 
              | unknown_stmt        { clicon_debug(3,"container-substmt -> unknown-stmt");} 
              |                     { clicon_debug(3,"container-substmt ->");} 
              ;

leaf_stmt     : K_LEAF identifier_str ';'
		{ if (ysp_add(_yy, Y_LEAF, $2, NULL) == NULL) _YYERROR("leaf_stmt"); 
			   clicon_debug(3,"leaf-stmt -> LEAF id-arg-str ;");}
              | K_LEAF identifier_str 
	      { if (ysp_add_push(_yy, Y_LEAF, $2, NULL) == NULL) _YYERROR("leaf_stmt"); }
                '{' leaf_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("leaf_stmt");
                             clicon_debug(3,"leaf-stmt -> LEAF id-arg-str { lead-substmts }");}
              ;

leaf_substmts : leaf_substmts leaf_substmt
              | leaf_substmt
              ;

leaf_substmt  : when_stmt            { clicon_debug(3,"leaf-substmt -> when-stmt"); }
              | if_feature_stmt      { clicon_debug(3,"leaf-substmt -> if-feature-stmt"); }
              | type_stmt            { clicon_debug(3,"leaf-substmt -> type-stmt"); }
              | units_stmt           { clicon_debug(3,"leaf-substmt -> units-stmt"); }
              | must_stmt            { clicon_debug(3,"leaf-substmt -> must-stmt"); }
              | default_stmt         { clicon_debug(3,"leaf-substmt -> default-stmt"); }
              | config_stmt          { clicon_debug(3,"leaf-substmt -> config-stmt"); }
              | mandatory_stmt       { clicon_debug(3,"leaf-substmt -> mandatory-stmt"); }
              | status_stmt          { clicon_debug(3,"leaf-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"leaf-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"leaf-substmt -> reference-stmt"); }
              | unknown_stmt         { clicon_debug(3,"leaf-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"leaf-substmt ->"); }
              ;

/* leaf-list */
leaf_list_stmt : K_LEAF_LIST identifier_str ';'
		{ if (ysp_add(_yy, Y_LEAF_LIST, $2, NULL) == NULL) _YYERROR("leaf_list_stmt"); 
			   clicon_debug(3,"leaf-list-stmt -> LEAF id-arg-str ;");}
              | K_LEAF_LIST identifier_str
	      { if (ysp_add_push(_yy, Y_LEAF_LIST, $2, NULL) == NULL) _YYERROR("leaf_list_stmt"); }
                '{' leaf_list_substmts '}'
                           { if (ystack_pop(_yy) < 0) _YYERROR("leaf_list_stmt");
                             clicon_debug(3,"leaf-list-stmt -> LEAF-LIST id-arg-str { lead-substmts }");}
              ;

leaf_list_substmts : leaf_list_substmts leaf_list_substmt
              | leaf_list_substmt
              ;

leaf_list_substmt : when_stmt        { clicon_debug(3,"leaf-list-substmt -> when-stmt"); } 
              | if_feature_stmt      { clicon_debug(3,"leaf-list-substmt -> if-feature-stmt"); }
              | type_stmt            { clicon_debug(3,"leaf-list-substmt -> type-stmt"); }
              | units_stmt           { clicon_debug(3,"leaf-list-substmt -> units-stmt"); }
              | must_stmt            { clicon_debug(3,"leaf-list-substmt -> must-stmt"); }
              | default_stmt         { clicon_debug(3,"leaf-list-substmt -> default-stmt"); }
              | config_stmt          { clicon_debug(3,"leaf-list-substmt -> config-stmt"); }
              | min_elements_stmt    { clicon_debug(3,"leaf-list-substmt -> min-elements-stmt"); }
              | max_elements_stmt    { clicon_debug(3,"leaf-list-substmt -> max-elements-stmt"); }
              | ordered_by_stmt      { clicon_debug(3,"leaf-list-substmt -> ordered-by-stmt"); }
              | status_stmt          { clicon_debug(3,"leaf-list-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"leaf-list-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"leaf-list-substmt -> reference-stmt"); }
              | unknown_stmt         { clicon_debug(3,"leaf-list-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"leaf-list-stmt ->"); }
              ;

list_stmt     : K_LIST identifier_str ';' 
		{ if (ysp_add(_yy, Y_LIST, $2, NULL) == NULL) _YYERROR("list_stmt"); 
			   clicon_debug(3,"list-stmt -> LIST id-arg-str ;"); }
              | K_LIST identifier_str 
	      { if (ysp_add_push(_yy, Y_LIST, $2, NULL) == NULL) _YYERROR("list_stmt"); }
	       '{' list_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("list_stmt");
			     clicon_debug(3,"list-stmt -> LIST id-arg-str { list-substmts }"); }
              ;

list_substmts : list_substmts list_substmt 
                      { clicon_debug(3,"list-substmts -> list-substmts list-substmt"); }
              | list_substmt 
                      { clicon_debug(3,"list-substmts -> list-substmt"); }
              ;

list_substmt  : when_stmt            { clicon_debug(3,"list-substmt -> when-stmt"); }
              | if_feature_stmt      { clicon_debug(3,"list-substmt -> if-feature-stmt"); }
              | must_stmt            { clicon_debug(3,"list-substmt -> must-stmt"); }
              | key_stmt             { clicon_debug(3,"list-substmt -> key-stmt"); }
              | unique_stmt          { clicon_debug(3,"list-substmt -> unique-stmt"); }
              | config_stmt          { clicon_debug(3,"list-substmt -> config-stmt"); }
              | min_elements_stmt    { clicon_debug(3,"list-substmt -> min-elements-stmt"); }
              | max_elements_stmt    { clicon_debug(3,"list-substmt -> max-elements-stmt"); }
              | ordered_by_stmt      { clicon_debug(3,"list-substmt -> ordered-by-stmt"); }
              | status_stmt          { clicon_debug(3,"list-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"list-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"list-substmt -> reference-stmt"); }
              | typedef_stmt         { clicon_debug(3,"list-substmt -> typedef-stmt"); }
              | grouping_stmt        { clicon_debug(3,"list-substmt -> grouping-stmt"); }
              | data_def_stmt        { clicon_debug(3,"list-substmt -> data-def-stmt"); }
              | action_stmt          { clicon_debug(3,"list-substmt -> action-stmt"); }
              | notification_stmt    { clicon_debug(3,"list-substmt -> notification-stmt"); }
              | unknown_stmt         { clicon_debug(3,"list-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"list-substmt -> "); }
              ;

/* key-stmt = key-keyword sep key-arg-str */
key_stmt      : K_KEY string stmtend
		{ if (ysp_add(_yy, Y_KEY, $2, NULL)== NULL) _YYERROR("key_stmt"); 
			   clicon_debug(3,"key-stmt -> KEY id-arg-str ;");}
              ;

/* unique-stmt = unique-keyword unique-arg-str */
unique_stmt   : K_UNIQUE string stmtend
		{ if (ysp_add(_yy, Y_UNIQUE, $2, NULL)== NULL) _YYERROR("unique_stmt"); 
			   clicon_debug(3,"key-stmt -> KEY id-arg-str ;");}
              ;

/* choice */
choice_stmt   : K_CHOICE identifier_str ';' 
	       { if (ysp_add(_yy, Y_CHOICE, $2, NULL) == NULL) _YYERROR("choice_stmt"); 
			   clicon_debug(3,"choice-stmt -> CHOICE id-arg-str ;"); }
              | K_CHOICE identifier_str
	      { if (ysp_add_push(_yy, Y_CHOICE, $2, NULL) == NULL) _YYERROR("choice_stmt"); }
	       '{' choice_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("choice_stmt");
			     clicon_debug(3,"choice-stmt -> CHOICE id-arg-str { choice-substmts }"); }
              ;

choice_substmts : choice_substmts choice_substmt 
                      { clicon_debug(3,"choice-substmts -> choice-substmts choice-substmt"); }
              | choice_substmt 
                      { clicon_debug(3,"choice-substmts -> choice-substmt"); }
              ;

choice_substmt : when_stmt           { clicon_debug(3,"choice-substmt -> when-stmt"); }  
              | if_feature_stmt      { clicon_debug(3,"choice-substmt -> if-feature-stmt"); }
              | default_stmt         { clicon_debug(3,"choice-substmt -> default-stmt"); }
              | config_stmt          { clicon_debug(3,"choice-substmt -> config-stmt"); }
              | mandatory_stmt       { clicon_debug(3,"choice-substmt -> mandatory-stmt"); }
              | status_stmt          { clicon_debug(3,"choice-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"choice-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"choice-substmt -> reference-stmt"); }
              | short_case_stmt      { clicon_debug(3,"choice-substmt -> short-case-stmt");} 
              | case_stmt            { clicon_debug(3,"choice-substmt -> case-stmt");} 
              | unknown_stmt         { clicon_debug(3,"choice-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"choice-substmt -> "); }
              ;

/* case */
case_stmt   : K_CASE identifier_str ';' 
	       { if (ysp_add(_yy, Y_CASE, $2, NULL) == NULL) _YYERROR("case_stmt"); 
			   clicon_debug(3,"case-stmt -> CASE id-arg-str ;"); }
              | K_CASE identifier_str 
	      { if (ysp_add_push(_yy, Y_CASE, $2, NULL) == NULL) _YYERROR("case_stmt"); }
	       '{' case_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("case_stmt");
			     clicon_debug(3,"case-stmt -> CASE id-arg-str { case-substmts }"); }
              ;

case_substmts : case_substmts case_substmt 
                      { clicon_debug(3,"case-substmts -> case-substmts case-substmt"); }
              | case_substmt 
                      { clicon_debug(3,"case-substmts -> case-substmt"); }
              ;

case_substmt  : when_stmt            { clicon_debug(3,"case-substmt -> when-stmt"); }
              | if_feature_stmt      { clicon_debug(3,"case-substmt -> if-feature-stmt"); }
              | status_stmt          { clicon_debug(3,"case-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"case-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"case-substmt -> reference-stmt"); }
              | data_def_stmt        { clicon_debug(3,"case-substmt -> data-def-stmt");} 
              | unknown_stmt         { clicon_debug(3,"case-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"case-substmt -> "); }
              ;

anydata_stmt   : K_ANYDATA identifier_str ';' 
	       { if (ysp_add(_yy, Y_ANYDATA, $2, NULL) == NULL) _YYERROR("anydata_stmt"); 
			   clicon_debug(3,"anydata-stmt -> ANYDATA id-arg-str ;"); }
              | K_ANYDATA identifier_str
	      { if (ysp_add_push(_yy, Y_ANYDATA, $2, NULL) == NULL) _YYERROR("anydata_stmt"); }
	       '{' anyxml_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("anydata_stmt");
			     clicon_debug(3,"anydata-stmt -> ANYDATA id-arg-str { anyxml-substmts }"); }
              ;

/* anyxml */
anyxml_stmt   : K_ANYXML identifier_str ';' 
	       { if (ysp_add(_yy, Y_ANYXML, $2, NULL) == NULL) _YYERROR("anyxml_stmt"); 
			   clicon_debug(3,"anyxml-stmt -> ANYXML id-arg-str ;"); }
              | K_ANYXML identifier_str
	      { if (ysp_add_push(_yy, Y_ANYXML, $2, NULL) == NULL) _YYERROR("anyxml_stmt"); }
	       '{' anyxml_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("anyxml_stmt");
			     clicon_debug(3,"anyxml-stmt -> ANYXML id-arg-str { anyxml-substmts }"); }
              ;

anyxml_substmts : anyxml_substmts anyxml_substmt 
                      { clicon_debug(3,"anyxml-substmts -> anyxml-substmts anyxml-substmt"); }
              | anyxml_substmt 
                      { clicon_debug(3,"anyxml-substmts -> anyxml-substmt"); }
              ;

anyxml_substmt  : when_stmt          { clicon_debug(3,"anyxml-substmt -> when-stmt"); }
              | if_feature_stmt      { clicon_debug(3,"anyxml-substmt -> if-feature-stmt"); }
              | must_stmt            { clicon_debug(3,"anyxml-substmt -> must-stmt"); }
              | config_stmt          { clicon_debug(3,"anyxml-substmt -> config-stmt"); }
              | mandatory_stmt       { clicon_debug(3,"anyxml-substmt -> mandatory-stmt"); }
              | status_stmt          { clicon_debug(3,"anyxml-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"anyxml-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"anyxml-substmt -> reference-stmt"); }
              | ustring ':' ustring ';' { free($1); free($3); clicon_debug(3,"anyxml-substmt -> anyxml extension"); }
              | unknown_stmt         { clicon_debug(3,"anyxml-substmt -> unknown-stmt");} 
              ;

/* uses-stmt = uses-keyword identifier-ref-arg-str */
uses_stmt     : K_USES identifier_ref_str ';' 
	       { if (ysp_add(_yy, Y_USES, $2, NULL) == NULL) _YYERROR("uses_stmt"); 
			   clicon_debug(3,"uses-stmt -> USES id-arg-str ;"); }
              | K_USES identifier_ref_str
	      { if (ysp_add_push(_yy, Y_USES, $2, NULL) == NULL) _YYERROR("uses_stmt"); }
	       '{' uses_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("uses_stmt");
			     clicon_debug(3,"uses-stmt -> USES id-arg-str { uses-substmts }"); }
              ;

uses_substmts : uses_substmts uses_substmt 
                      { clicon_debug(3,"uses-substmts -> uses-substmts uses-substmt"); }
              | uses_substmt 
                      { clicon_debug(3,"uses-substmts -> uses-substmt"); }
              ;

uses_substmt  : when_stmt            { clicon_debug(3,"uses-substmt -> when-stmt"); }
              | if_feature_stmt      { clicon_debug(3,"uses-substmt -> if-feature-stmt"); }
              | status_stmt          { clicon_debug(3,"uses-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"uses-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"uses-substmt -> reference-stmt"); }
              | refine_stmt          { clicon_debug(3,"uses-substmt -> refine-stmt"); }
              | uses_augment_stmt    { clicon_debug(3,"uses-substmt -> uses-augment-stmt"); }
              | unknown_stmt         { clicon_debug(3,"uses-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"uses-substmt -> "); }
              ;

/* refine-stmt = refine-keyword sep refine-arg-str */
refine_stmt   : K_REFINE desc_schema_nodeid_strs ';' 
	       { if (ysp_add(_yy, Y_REFINE, $2, NULL) == NULL) _YYERROR("refine_stmt"); 
			   clicon_debug(3,"refine-stmt -> REFINE id-arg-str ;"); }
              | K_REFINE desc_schema_nodeid_strs
	      { if (ysp_add_push(_yy, Y_REFINE, $2, NULL) == NULL) _YYERROR("refine_stmt"); }
	       '{' refine_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("refine_stmt");
			     clicon_debug(3,"refine-stmt -> REFINE id-arg-str { refine-substmts }"); }
              ;

refine_substmts : refine_substmts refine_substmt 
                      { clicon_debug(3,"refine-substmts -> refine-substmts refine-substmt"); }
              | refine_substmt 
                      { clicon_debug(3,"refine-substmts -> refine-substmt"); }
              ;

refine_substmt  : if_feature_stmt     { clicon_debug(3,"refine-substmt -> if-feature-stmt"); }
              | must_stmt     { clicon_debug(3,"refine-substmt -> must-stmt"); }
              | presence_stmt  { clicon_debug(3,"refine-substmt -> presence-stmt"); }
              | default_stmt    { clicon_debug(3,"refine-substmt -> default-stmt"); }
              | config_stmt    { clicon_debug(3,"refine-substmt -> config-stmt"); }
              | mandatory_stmt  { clicon_debug(3,"refine-substmt -> mandatory-stmt"); }
              | min_elements_stmt  { clicon_debug(3,"refine-substmt -> min-elements-stmt"); }
              | max_elements_stmt  { clicon_debug(3,"refine-substmt -> max-elements-stmt"); }
              | description_stmt  { clicon_debug(3,"refine-substmt -> description-stmt"); }
              | reference_stmt  { clicon_debug(3,"refine-substmt -> reference-stmt"); }
              | unknown_stmt    { clicon_debug(3,"refine-substmt -> unknown-stmt");} 
              |                 { clicon_debug(3,"refine-substmt -> "); }
              ;

/* uses-augment-stmt = augment-keyword augment-arg-str 
uses_augment_stmt : K_AUGMENT desc_schema_nodeid_strs
*/
uses_augment_stmt : K_AUGMENT string
                      { if (ysp_add_push(_yy, Y_AUGMENT, $2, NULL) == NULL) _YYERROR("uses_augment_stmt"); }
                    '{' augment_substmts '}'
                      { if (ystack_pop(_yy) < 0) _YYERROR("uses_augment_stmt");
			     clicon_debug(3,"uses-augment-stmt -> AUGMENT desc-schema-node-str { augment-substmts }"); }

		    
/* augment-stmt = augment-keyword sep augment-arg-str 
 * XXX abs-schema-nodeid-str is too difficult, it needs the + semantics
augment_stmt   : K_AUGMENT abs_schema_nodeid_strs
 */
augment_stmt   : K_AUGMENT string
                   { if (ysp_add_push(_yy, Y_AUGMENT, $2, NULL) == NULL) _YYERROR("augment_stmt"); }
	       '{' augment_substmts '}' 
                   { if (ystack_pop(_yy) < 0) _YYERROR("augment_stmt");
			     clicon_debug(3,"augment-stmt -> AUGMENT abs-schema-node-str { augment-substmts }"); }
              ;

augment_substmts : augment_substmts augment_substmt 
                      { clicon_debug(3,"augment-substmts -> augment-substmts augment-substmt"); }
              | augment_substmt 
                      { clicon_debug(3,"augment-substmts -> augment-substmt"); }
              ;

augment_substmt : when_stmt          { clicon_debug(3,"augment-substmt -> when-stmt"); }  
              | if_feature_stmt      { clicon_debug(3,"augment-substmt -> if-feature-stmt"); }
              | status_stmt          { clicon_debug(3,"augment-substmt -> status-stmt"); }
              | description_stmt     { clicon_debug(3,"augment-substmt -> description-stmt"); }
              | reference_stmt       { clicon_debug(3,"augment-substmt -> reference-stmt"); }
              | data_def_stmt        { clicon_debug(3,"augment-substmt -> data-def-stmt"); }
              | case_stmt            { clicon_debug(3,"augment-substmt -> case-stmt");}
              | action_stmt          { clicon_debug(3,"augment-substmt -> action-stmt");} 
              | notification_stmt    { clicon_debug(3,"augment-substmt -> notification-stmt");} 
              | unknown_stmt         { clicon_debug(3,"augment-substmt -> unknown-stmt");} 
              |                      { clicon_debug(3,"augment-substmt -> "); }
              ;

/* when */
when_stmt   : K_WHEN string ';' 
	       { if (ysp_add(_yy, Y_WHEN, $2, NULL) == NULL) _YYERROR("when_stmt"); 
			   clicon_debug(3,"when-stmt -> WHEN string ;"); }
            | K_WHEN string
	    { if (ysp_add_push(_yy, Y_WHEN, $2, NULL) == NULL) _YYERROR("when_stmt"); }
	       '{' when_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("when_stmt");
			     clicon_debug(3,"when-stmt -> WHEN string { when-substmts }"); }
              ;

when_substmts : when_substmts when_substmt 
                      { clicon_debug(3,"when-substmts -> when-substmts when-substmt"); }
              | when_substmt 
                      { clicon_debug(3,"when-substmts -> when-substmt"); }
              ;

when_substmt  : description_stmt { clicon_debug(3,"when-substmt -> description-stmt"); }
              | reference_stmt   { clicon_debug(3,"when-substmt -> reference-stmt"); }
              |                  { clicon_debug(3,"when-substmt -> "); }
              ;

/* rpc */
rpc_stmt   : K_RPC identifier_str ';' 
	       { if (ysp_add(_yy, Y_RPC, $2, NULL) == NULL) _YYERROR("rpc_stmt"); 
			   clicon_debug(3,"rpc-stmt -> RPC id-arg-str ;"); }
           | K_RPC identifier_str
	   { if (ysp_add_push(_yy, Y_RPC, $2, NULL) == NULL) _YYERROR("rpc_stmt"); }
	     '{' rpc_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("rpc_stmt");
			     clicon_debug(3,"rpc-stmt -> RPC id-arg-str { rpc-substmts }"); }
              ;

rpc_substmts : rpc_substmts rpc_substmt 
                      { clicon_debug(3,"rpc-substmts -> rpc-substmts rpc-substmt"); }
              | rpc_substmt 
                      { clicon_debug(3,"rpc-substmts -> rpc-substmt"); }
              ;

rpc_substmt   : if_feature_stmt  { clicon_debug(3,"rpc-substmt -> if-feature-stmt"); }
              | status_stmt      { clicon_debug(3,"rpc-substmt -> status-stmt"); }
              | description_stmt { clicon_debug(3,"rpc-substmt -> description-stmt"); }
              | reference_stmt   { clicon_debug(3,"rpc-substmt -> reference-stmt"); }
              | typedef_stmt     { clicon_debug(3,"rpc-substmt -> typedef-stmt"); }
              | grouping_stmt    { clicon_debug(3,"rpc-substmt -> grouping-stmt"); }
              | input_stmt       { clicon_debug(3,"rpc-substmt -> input-stmt"); }
              | output_stmt      { clicon_debug(3,"rpc-substmt -> output-stmt"); }
              | unknown_stmt     { clicon_debug(3,"rpc-substmt -> unknown-stmt");} 
              |                  { clicon_debug(3,"rpc-substmt -> "); }
              ;

/* action */
action_stmt   : K_ACTION identifier_str ';' 
	       { if (ysp_add(_yy, Y_ACTION, $2, NULL) == NULL) _YYERROR("action_stmt"); 
			   clicon_debug(3,"action-stmt -> ACTION id-arg-str ;"); }
              | K_ACTION identifier_str
	      { if (ysp_add_push(_yy, Y_ACTION, $2, NULL) == NULL) _YYERROR("action_stmt"); }
	       '{' rpc_substmts '}' 
                           { if (ystack_pop(_yy) < 0) _YYERROR("action_stmt");
			     clicon_debug(3,"action-stmt -> ACTION id-arg-str { rpc-substmts }"); }
              ;

/* notification */
notification_stmt : K_NOTIFICATION identifier_str ';' 
	                { if (ysp_add(_yy, Y_NOTIFICATION, $2, NULL) == NULL) _YYERROR("notification_stmt"); 
			   clicon_debug(3,"notification-stmt -> NOTIFICATION id-arg-str ;"); }
                  | K_NOTIFICATION identifier_str
		  { if (ysp_add_push(_yy, Y_NOTIFICATION, $2, NULL) == NULL) _YYERROR("notification_stmt"); }
	            '{' notification_substmts '}' 
                        { if (ystack_pop(_yy) < 0) _YYERROR("notification_stmt");
			     clicon_debug(3,"notification-stmt -> NOTIFICATION id-arg-str { notification-substmts }"); }
                  ;

notification_substmts : notification_substmts notification_substmt 
                         { clicon_debug(3,"notification-substmts -> notification-substmts notification-substmt"); }
                      | notification_substmt 
                         { clicon_debug(3,"notification-substmts -> notification-substmt"); }
                      ;

notification_substmt : if_feature_stmt  { clicon_debug(3,"notification-substmt -> if-feature-stmt"); }
                     | must_stmt        { clicon_debug(3,"notification-substmt -> must-stmt"); }
                     | status_stmt      { clicon_debug(3,"notification-substmt -> status-stmt"); }
                     | description_stmt { clicon_debug(3,"notification-substmt -> description-stmt"); }
                     | reference_stmt   { clicon_debug(3,"notification-substmt -> reference-stmt"); }
                     | typedef_stmt     { clicon_debug(3,"notification-substmt -> typedef-stmt"); }
                     | grouping_stmt    { clicon_debug(3,"notification-substmt -> grouping-stmt"); }
                     | data_def_stmt    { clicon_debug(3,"notification-substmt -> data-def-stmt"); }
                     | unknown_stmt     { clicon_debug(3,"notification-substmt -> unknown-stmt");} 
                     |                  { clicon_debug(3,"notification-substmt -> "); }
                     ;

/* deviation /oc-sys:system/oc-sys:config/oc-sys:hostname {
	     deviate not-supported;
      }
 * XXX abs-schema-nodeid-str is too difficult, it needs the + semantics

*/
deviation_stmt : K_DEVIATION string
                        { if (ysp_add_push(_yy, Y_DEVIATION, $2, NULL) == NULL) _YYERROR("deviation_stmt"); }
	            '{' deviation_substmts '}' 
                        { if (ystack_pop(_yy) < 0) _YYERROR("deviation_stmt");
			     clicon_debug(3,"deviation-stmt -> DEVIATION id-arg-str { notification-substmts }"); }
               ;

deviation_substmts : deviation_substmts deviation_substmt 
                         { clicon_debug(3,"deviation-substmts -> deviation-substmts deviation-substmt"); }
                      | deviation_substmt 
                         { clicon_debug(3,"deviation-substmts -> deviation-substmt"); }
                      ;

deviation_substmt : description_stmt  { clicon_debug(3,"deviation-substmt -> description-stmt"); }
                  | reference_stmt  { clicon_debug(3,"deviation-substmt -> reference-stmt"); }
                  | deviate_stmt  { clicon_debug(3,"deviation-substmt -> deviate-stmt"); }
		  ;

/* RFC7950 differentiates between deviate-not-supported, deviate-add, 
 * deviate-replave, and deviate-delete. Here all are bundled into a single
 * deviate rule. For now, until "deviate" gets supported.
 */
deviate_stmt      : K_DEVIATE string ';'
	                { if (ysp_add(_yy, Y_DEVIATE, $2, NULL) == NULL) _YYERROR("notification_stmt");
    			   clicon_debug(3,"deviate-not-supported-stmt -> DEVIATE string ;"); }
                  | K_DEVIATE string
		  { if (ysp_add_push(_yy, Y_DEVIATE, $2, NULL) == NULL) _YYERROR("deviate_stmt"); }
	            '{' deviate_substmts '}' 
                        { if (ystack_pop(_yy) < 0) _YYERROR("deviate_stmt");
			     clicon_debug(3,"deviate-stmt -> DEVIATE string { deviate-substmts }"); }
                   ;

/* RFC7950 differentiates between deviate-not-supported, deviate-add, 
 * deviate-replave, and deviate-delete. Here all are bundled into a single
 * deviate-substmt rule. For now, until "deviate" gets supported.
 */
deviate_substmts     : deviate_substmts deviate_substmt 
                         { clicon_debug(3,"deviate-substmts -> deviate-substmts deviate-substmt"); }
                     | deviate_substmt 
                         { clicon_debug(3,"deviate-substmts -> deviate-substmt"); }
                     ;
/* Bundled */
deviate_substmt : type_stmt         { clicon_debug(3,"deviate-substmt -> type-stmt"); }
                | units_stmt        { clicon_debug(3,"deviate-substmt -> units-stmt"); }
                | must_stmt         { clicon_debug(3,"deviate-substmt -> must-stmt"); }
                | unique_stmt       { clicon_debug(3,"deviate-substmt -> unique-stmt"); }
                | default_stmt      { clicon_debug(3,"deviate-substmt -> default-stmt"); }
                | config_stmt       { clicon_debug(3,"deviate-substmt -> config-stmt"); }
                | mandatory_stmt    { clicon_debug(3,"deviate-substmt -> mandatory-stmt"); }
                | min_elements_stmt { clicon_debug(3,"deviate-substmt -> min-elements-stmt"); }
                | max_elements_stmt { clicon_debug(3,"deviate-substmt -> max-elements-stmt"); }
                |                   { clicon_debug(3,"deviate-substmt -> "); }
                ;


/* Represents the usage of an extension
   unknown-statement   = prefix ":" identifier [sep string] optsep
                         (";" /
                          "{" optsep
                              *((yang-stmt / unknown-statement) optsep)
                           "}") stmt
 *
 */
unknown_stmt  : ustring ':' ustring optsep ';'
                 { char *id; if ((id=string_del_join($1, ":", $3)) == NULL) _YYERROR("unknown_stmt");
		   if (ysp_add(_yy, Y_UNKNOWN, id, NULL) == NULL) _YYERROR("unknown_stmt"); 
		   clicon_debug(3,"unknown-stmt -> ustring : ustring");
	       }
              | ustring ':' ustring SEP string optsep ';'
	        { char *id; if ((id=string_del_join($1, ":", $3)) == NULL) _YYERROR("unknown_stmt");
		   if (ysp_add(_yy, Y_UNKNOWN, id, $5) == NULL){ _YYERROR("unknwon_stmt"); }
		   clicon_debug(3,"unknown-stmt -> ustring : ustring string");
	       }
              | ustring ':' ustring optsep
                 { char *id; if ((id=string_del_join($1, ":", $3)) == NULL) _YYERROR("unknown_stmt");
		     if (ysp_add_push(_yy, Y_UNKNOWN, id, NULL) == NULL) _YYERROR("unknown_stmt"); }
	         '{' yang_stmts '}'
	               { if (ystack_pop(_yy) < 0) _YYERROR("unknown_stmt");
			 clicon_debug(3,"unknown-stmt -> ustring : ustring { yang-stmts }"); }
              | ustring ':' ustring SEP string optsep
 	         { char *id; if ((id=string_del_join($1, ":", $3)) == NULL) _YYERROR("unknown_stmt");
		     if (ysp_add_push(_yy, Y_UNKNOWN, id, $5) == NULL) _YYERROR("unknown_stmt"); }
	         '{' yang_stmts '}'
	               { if (ystack_pop(_yy) < 0) _YYERROR("unknown_stmt");
			 clicon_debug(3,"unknown-stmt -> ustring : ustring string { yang-stmts }"); }
	      ;

yang_stmts    : yang_stmts yang_stmt { clicon_debug(3,"yang-stmts -> yang-stmts yang-stmt"); } 
              | yang_stmt            { clicon_debug(3,"yang-stmts -> yang-stmt");}
              ;

yang_stmt     : action_stmt          { clicon_debug(3,"yang-stmt -> action-stmt");}
              | anydata_stmt         { clicon_debug(3,"yang-stmt -> anydata-stmt");}
              | anyxml_stmt          { clicon_debug(3,"yang-stmt -> anyxml-stmt");}
              | argument_stmt        { clicon_debug(3,"yang-stmt -> argument-stmt");}
              | augment_stmt         { clicon_debug(3,"yang-stmt -> augment-stmt");}
              | base_stmt            { clicon_debug(3,"yang-stmt -> base-stmt");}
              | bit_stmt             { clicon_debug(3,"yang-stmt -> bit-stmt");}
              | case_stmt            { clicon_debug(3,"yang-stmt -> case-stmt");}
              | choice_stmt          { clicon_debug(3,"yang-stmt -> choice-stmt");}
              | config_stmt          { clicon_debug(3,"yang-stmt -> config-stmt");}
              | contact_stmt         { clicon_debug(3,"yang-stmt -> contact-stmt");}
              | container_stmt       { clicon_debug(3,"yang-stmt -> container-stmt");}
              | default_stmt         { clicon_debug(3,"yang-stmt -> default-stmt");}
              | description_stmt     { clicon_debug(3,"yang-stmt -> description-stmt");}
              | deviate_stmt         { clicon_debug(3,"yang-stmt -> deviate-stmt");}
/* deviate is not yet implemented, the above may be replaced by the following lines
              | deviate_add_stmt     { clicon_debug(3,"yang-stmt -> deviate-add-stmt");}
              | deviate_delete_stmt  { clicon_debug(3,"yang-stmt -> deviate-add-stmt");}
              | deviate_replace_stmt { clicon_debug(3,"yang-stmt -> deviate-add-stmt");}
*/
              | deviation_stmt       { clicon_debug(3,"yang-stmt -> deviation-stmt");}
              | enum_stmt            { clicon_debug(3,"yang-stmt -> enum-stmt");}
              | error_app_tag_stmt   { clicon_debug(3,"yang-stmt -> error-app-tag-stmt");}
              | error_message_stmt   { clicon_debug(3,"yang-stmt -> error-message-stmt");}
              | extension_stmt       { clicon_debug(3,"yang-stmt -> extension-stmt");}
              | feature_stmt         { clicon_debug(3,"yang-stmt -> feature-stmt");}
              | fraction_digits_stmt { clicon_debug(3,"yang-stmt -> fraction-digits-stmt");}
              | grouping_stmt        { clicon_debug(3,"yang-stmt -> grouping-stmt");}
              | identity_stmt        { clicon_debug(3,"yang-stmt -> identity-stmt");}
              | if_feature_stmt      { clicon_debug(3,"yang-stmt -> if-feature-stmt");}
              | import_stmt          { clicon_debug(3,"yang-stmt -> import-stmt");}
              | include_stmt         { clicon_debug(3,"yang-stmt -> include-stmt");}
              | input_stmt           { clicon_debug(3,"yang-stmt -> input-stmt");}
              | key_stmt             { clicon_debug(3,"yang-stmt -> key-stmt");}
              | leaf_list_stmt       { clicon_debug(3,"yang-stmt -> leaf-list-stmt");}
              | leaf_stmt            { clicon_debug(3,"yang-stmt -> leaf-stmt");}
              | length_stmt          { clicon_debug(3,"yang-stmt -> length-stmt");}
              | list_stmt            { clicon_debug(3,"yang-stmt -> list-stmt");}
              | mandatory_stmt       { clicon_debug(3,"yang-stmt -> list-stmt");}
              | max_elements_stmt    { clicon_debug(3,"yang-stmt -> list-stmt");}
              | min_elements_stmt    { clicon_debug(3,"yang-stmt -> list-stmt");}
              | modifier_stmt        { clicon_debug(3,"yang-stmt -> list-stmt");}
              | module_stmt          { clicon_debug(3,"yang-stmt -> list-stmt");}
              | must_stmt            { clicon_debug(3,"yang-stmt -> list-stmt");}
              | namespace_stmt       { clicon_debug(3,"yang-stmt -> list-stmt");}
              | notification_stmt    { clicon_debug(3,"yang-stmt -> notification-stmt");}
              | ordered_by_stmt      { clicon_debug(3,"yang-stmt -> list-stmt");}
              | organization_stmt    { clicon_debug(3,"yang-stmt -> list-stmt");}
              | output_stmt          { clicon_debug(3,"yang-stmt -> list-stmt");}
              | path_stmt            { clicon_debug(3,"yang-stmt -> list-stmt");}
              | pattern_stmt         { clicon_debug(3,"yang-stmt -> list-stmt");}
              | position_stmt        { clicon_debug(3,"yang-stmt -> list-stmt");}
              | prefix_stmt          { clicon_debug(3,"yang-stmt -> list-stmt");}
              | presence_stmt        { clicon_debug(3,"yang-stmt -> list-stmt");}
              | range_stmt           { clicon_debug(3,"yang-stmt -> list-stmt");}
              | reference_stmt       { clicon_debug(3,"yang-stmt -> list-stmt");}
              | refine_stmt          { clicon_debug(3,"yang-stmt -> list-stmt");}
              | require_instance_stmt { clicon_debug(3,"yang-stmt -> list-stmt");}
              | revision_date_stmt   { clicon_debug(3,"yang-stmt -> list-stmt");}
              | revision_stmt        { clicon_debug(3,"yang-stmt -> list-stmt");}
              | rpc_stmt             { clicon_debug(3,"yang-stmt -> rpc-stmt");}
              | status_stmt          { clicon_debug(3,"yang-stmt -> list-stmt");}
              | submodule_stmt       { clicon_debug(3,"yang-stmt -> list-stmt");}
              | typedef_stmt         { clicon_debug(3,"yang-stmt -> typedef-stmt");}
              | type_stmt            { clicon_debug(3,"yang-stmt -> list-stmt");}
              | unique_stmt          { clicon_debug(3,"yang-stmt -> list-stmt");}
              | units_stmt           { clicon_debug(3,"yang-stmt -> list-stmt");}
              | uses_augment_stmt    { clicon_debug(3,"yang-stmt -> list-stmt");}
              | uses_stmt            { clicon_debug(3,"yang-stmt -> list-stmt");}
              | value_stmt           { clicon_debug(3,"yang-stmt -> list-stmt");}
              | when_stmt            { clicon_debug(3,"yang-stmt -> list-stmt");}
              | yang_version_stmt    { clicon_debug(3,"yang-stmt -> list-stmt");}
/*              | yin_element_stmt     { clicon_debug(3,"yang-stmt -> list-stmt");} */
              ;

/* body */
body_stmts    : body_stmts body_stmt { clicon_debug(3,"body-stmts -> body-stmts body-stmt"); } 
              | body_stmt            { clicon_debug(3,"body-stmts -> body-stmt");}
              ;

body_stmt     : extension_stmt       { clicon_debug(3,"body-stmt -> extension-stmt");}
              | feature_stmt         { clicon_debug(3,"body-stmt -> feature-stmt");}
              | identity_stmt        { clicon_debug(3,"body-stmt -> identity-stmt");}
              | typedef_stmt         { clicon_debug(3,"body-stmt -> typedef-stmt");}
              | grouping_stmt        { clicon_debug(3,"body-stmt -> grouping-stmt");}
              | data_def_stmt        { clicon_debug(3,"body-stmt -> data-def-stmt");}
              | augment_stmt         { clicon_debug(3,"body-stmt -> augment-stmt");}
              | rpc_stmt             { clicon_debug(3,"body-stmt -> rpc-stmt");}
              | notification_stmt    { clicon_debug(3,"body-stmt -> notification-stmt");}
              | deviation_stmt       { clicon_debug(3,"body-stmt -> deviation-stmt");}
              ;

data_def_stmt : container_stmt       { clicon_debug(3,"data-def-stmt -> container-stmt");}
              | leaf_stmt            { clicon_debug(3,"data-def-stmt -> leaf-stmt");}
              | leaf_list_stmt       { clicon_debug(3,"data-def-stmt -> leaf-list-stmt");}
              | list_stmt            { clicon_debug(3,"data-def-stmt -> list-stmt");}
              | choice_stmt          { clicon_debug(3,"data-def-stmt -> choice-stmt");}
              | anydata_stmt         { clicon_debug(3,"data-def-stmt -> anydata-stmt");}
              | anyxml_stmt          { clicon_debug(3,"data-def-stmt -> anyxml-stmt");}
              | uses_stmt            { clicon_debug(3,"data-def-stmt -> uses-stmt");}
              ;

/* short-case */
short_case_stmt : container_stmt   { clicon_debug(3,"short-case-substmt -> container-stmt"); }
              | leaf_stmt          { clicon_debug(3,"short-case-substmt -> leaf-stmt"); }
              | leaf_list_stmt     { clicon_debug(3,"short-case-substmt -> leaf-list-stmt"); }
              | list_stmt          { clicon_debug(3,"short-case-substmt -> list-stmt"); }
              | anydata_stmt       { clicon_debug(3,"short-case-substmt -> anydata-stmt");}
              | anyxml_stmt        { clicon_debug(3,"short-case-substmt -> anyxml-stmt");}
              ;


/* input */
input_stmt  : K_INPUT 
                  { if (ysp_add_push(_yy, Y_INPUT, NULL, NULL) == NULL) _YYERROR("input_stmt"); }
	       '{' input_substmts '}' 
                  { if (ystack_pop(_yy) < 0) _YYERROR("input_stmt");
			     clicon_debug(3,"input-stmt -> INPUT { input-substmts }"); }
              ;

input_substmts : input_substmts input_substmt 
                      { clicon_debug(3,"input-substmts -> input-substmts input-substmt"); }
              | input_substmt 
                      { clicon_debug(3,"input-substmts -> input-substmt"); }
              ;

input_substmt : typedef_stmt         { clicon_debug(3,"input-substmt -> typedef-stmt"); }
              | grouping_stmt        { clicon_debug(3,"input-substmt -> grouping-stmt"); }
              | data_def_stmt        { clicon_debug(3,"input-substmt -> data-def-stmt"); }
              |                      { clicon_debug(3,"input-substmt -> "); }
              ;

/* output */
output_stmt  : K_OUTPUT  /* XXX reuse input-substatements since they are same */
                   { if (ysp_add_push(_yy, Y_OUTPUT, NULL, NULL) == NULL) _YYERROR("output_stmt"); }
	       '{' input_substmts '}' 
                   { if (ystack_pop(_yy) < 0) _YYERROR("output_stmt");
			     clicon_debug(3,"output-stmt -> OUTPUT { input-substmts }"); }
              ;

string        : qstrings { $$=$1; clicon_debug(3,"string -> qstrings (%s)", $1); }
              | ustring  { $$=$1; clicon_debug(3,"string -> ustring (%s)", $1); }
              ;	      

/* quoted string */
qstrings      : qstrings '+' qstring
                     {
			 int len = strlen($1);
			 $$ = realloc($1, len + strlen($3) + 1); 
			 sprintf($$+len, "%s", $3);
			 free($3); 
			 clicon_debug(3,"qstrings-> qstrings + qstring"); 
		     }
              | qstring    
                     { $$=$1; clicon_debug(3,"qstrings-> qstring"); } 
              ;

qstring        : '"' ustring '"'  { $$=$2; clicon_debug(3,"string-> \" ustring \"");}
               | '"' '"'  { $$=strdup(""); clicon_debug(3,"string-> \"  \"");} 
               | SQ ustring SQ  { $$=$2; clicon_debug(3,"string-> ' ustring '"); }
               | SQ SQ  { $$=strdup(""); clicon_debug(3,"string-> '  '");} 
               ;

/* unquoted string */
ustring       : ustring CHARS
                     {
			 int len = strlen($1);
			 $$ = realloc($1, len+strlen($2) + 1);
			 sprintf($$+len, "%s", $2); 
			 free($2);
 			 clicon_debug(3,"ustring-> string + CHARS"); 
		     }
              | CHARS 
	             {$$=$1; } 
              ;

abs_schema_nodeid : abs_schema_nodeid '/' node_identifier
                 { if (($$=string_del_join($1, "/", $3)) == NULL) _YYERROR("abs_schema_nodeid");
		   clicon_debug(3,"absolute-schema-nodeid -> absolute-schema-nodeid / node-identifier"); }
              | '/' node_identifier
                 {  if (($$=string_del_join(NULL, "/", $2)) == NULL) _YYERROR("abs_schema_nodeid");
		     clicon_debug(3,"absolute-schema-nodeid -> / node-identifier"); }
              ;

desc_schema_nodeid_strs : desc_schema_nodeid_strs '+' desc_schema_nodeid_str
                     {
			 int len = strlen($1);
			 $$ = realloc($1, len + strlen($3) + 1); 
			 sprintf($$+len, "%s", $3);
			 free($3); 
			 clicon_debug(3,"desc-schema-nodeid-strs-> desc-schema-nodeid-strs + desc-schema-nodeid-str");
		     }
                      | desc_schema_nodeid_str
                           { $$=$1; clicon_debug(3,"desc-schema-nodeid-strs-> desc-schema-nodeid-str"); }
                      ;

desc_schema_nodeid_str : desc_schema_nodeid
                         { $$=$1; clicon_debug(3,"descendant-schema-nodeid-str -> descendant-schema-nodeid"); }
                     | '"' desc_schema_nodeid '"'
                         { $$=$2; clicon_debug(3,"descendant-schema-nodeid-str -> descendant-schema-nodeid"); }
                     ;

/* descendant-schema-nodeid */
desc_schema_nodeid : node_identifier
                     { $$= $1; clicon_debug(3,"descendant-schema-nodeid -> node_identifier"); }
                   | node_identifier abs_schema_nodeid
		   { if (($$=string_del_join($1, " ", $2)) == NULL) _YYERROR("desc_schema_nodeid");clicon_debug(3,"descendant-schema-nodeid -> node_identifier abs_schema_nodeid"); }
                   ;

identifier_str : '"' IDENTIFIER '"' { $$ = $2;
		         clicon_debug(3,"identifier_str -> \" IDENTIFIER \" ");}
               | IDENTIFIER           { $$ = $1;
		         clicon_debug(3,"identifier_str -> IDENTIFIER ");}
               ;

identifier_ref_str : '"' identifier_ref '"' { $$ = $2;
		         clicon_debug(3,"identifier_ref_str -> \" identifier_ref \" ");}
               | identifier_ref           { $$ = $1;
		         clicon_debug(3,"identifier_ref_str -> identifier_ref ");}
               ;

integer_value_str : '"' INT '"' { $$=$2; }
                  |     INT     { $$=$1; }
                  ;

bool_str       : '"' BOOL '"' { $$ = $2;
		         clicon_debug(3,"bool_str -> \" BOOL \" ");}
               |     BOOL     { $$ = $1;
		         clicon_debug(3,"bool_str -> BOOL ");}
               ;


/*   node-identifier     = [prefix ":"] identifier */
node_identifier : IDENTIFIER
		   { $$=$1; clicon_debug(3,"identifier-ref-arg-str -> string"); }
                | IDENTIFIER ':' IDENTIFIER
		{ if (($$=string_del_join($1, ":", $3)) == NULL) _YYERROR("node_identifier");
			clicon_debug(3,"identifier-ref-arg-str -> prefix : string"); }
                ;

/* ;;; Basic Rules */

/* identifier-ref = [prefix ":"] identifier */
identifier_ref : node_identifier { $$=$1;}
               ;

optsep :       SEP
               |
               ;


stmtend        : ';'
               | '{' '}'
               | '{' unknown_stmt '}'
               ;

%%


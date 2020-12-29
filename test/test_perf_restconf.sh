#!/usr/bin/env bash
# Scaling/ performance tests
# CLI/Netconf/Restconf
# Lists (and leaf-lists)
# Add, get and delete entries

# Magic line must be first in script (see README.md)
s="$_" ; . ./lib.sh || if [ "$s" = $0 ]; then exit 0; else return 0; fi

# Which format to use as datastore format internally
: ${format:=xml}

# Number of list/leaf-list entries in file
: ${perfnr:=20000}

# Number of requests made get/put
: ${perfreq:=10}

# time function (this is a mess to get right on freebsd/linux)
# -f %e gives elapsed wall clock time but is not available on all systems
# so we use time -p for POSIX compliance and awk to get wall clock time
# Note sometimes time -p is used and sometimes $TIMEFN, cant get it to work same everywhere
: ${TIMEFN:=time -p} # portability: 2>&1 | awk '/real/ {print $2}'
if ! $TIMEFN true; then err "A working time function" "'$TIMEFN' does not work"; fi

APPNAME=example

cfg=$dir/scaling-conf.xml
fyang=$dir/scaling.yang
fconfig=$dir/large.xml
fconfig2=$dir/large2.xml

cat <<EOF > $fyang
module scaling{
   yang-version 1.1;
   namespace "urn:example:clixon";
   prefix ex;
   container x {
    list y {
      key "a";
      leaf a {
        type int32;
      }
      leaf b {
        type int32;
      }
    }
    leaf-list c {
       type string;
    }
  }
}
EOF

cat <<EOF > $cfg
<clixon-config xmlns="http://clicon.org/config">
  <CLICON_CONFIGFILE>$cfg</CLICON_CONFIGFILE>
  <CLICON_YANG_DIR>$dir</CLICON_YANG_DIR>
  <CLICON_YANG_DIR>/usr/local/share/clixon</CLICON_YANG_DIR>
  <CLICON_YANG_MAIN_FILE>$fyang</CLICON_YANG_MAIN_FILE>
  <CLICON_SOCK>/usr/local/var/$APPNAME/$APPNAME.sock</CLICON_SOCK>
  <CLICON_BACKEND_PIDFILE>/usr/local/var/example/$APPNAME.pidfile</CLICON_BACKEND_PIDFILE>
  <CLICON_RESTCONF_PRETTY>false</CLICON_RESTCONF_PRETTY>
  <CLICON_XMLDB_DIR>$dir</CLICON_XMLDB_DIR>
  <CLICON_XMLDB_PRETTY>false</CLICON_XMLDB_PRETTY>
  <CLICON_XMLDB_FORMAT>$format</CLICON_XMLDB_FORMAT>
  <CLICON_CLI_MODE>example</CLICON_CLI_MODE>
  <CLICON_CLI_DIR>/usr/local/lib/example/cli</CLICON_CLI_DIR>
  <CLICON_CLISPEC_DIR>/usr/local/lib/example/clispec</CLICON_CLISPEC_DIR>
  <CLICON_CLI_LINESCROLLING>0</CLICON_CLI_LINESCROLLING>
  <CLICON_FEATURE>ietf-netconf:startup</CLICON_FEATURE>
  $RESTCONFIG
</clixon-config>
EOF

new "test params: -f $cfg"
if [ $BE -ne 0 ]; then
    new "kill old backend"
    sudo clixon_backend -zf $cfg
    if [ $? -ne 0 ]; then
	err
    fi

    new "start backend -s init -f $cfg -- -s"
    start_backend -s init -f $cfg -- -s
fi

new "waiting"
wait_backend

if [ $RC -ne 0 ]; then
    new "kill old restconf daemon"
    stop_restconf_pre

    new "start restconf daemon"
    start_restconf -f $cfg

    new "waiting"
    wait_restconf
fi

new "generate config with $perfnr list entries"
echo -n "<rpc><edit-config><target><candidate/></target><config><x xmlns=\"urn:example:clixon\">" > $fconfig
for (( i=0; i<$perfnr; i++ )); do  
    echo -n "<y><a>$i</a><b>$i</b></y>" >> $fconfig
done
echo "</x></config></edit-config></rpc>]]>]]>" >> $fconfig

# Now take large config file and write it via netconf to candidate
new "test time exists"
expectpart "$(time -p ls)" 0 

new "netconf write large config"
expecteof_file "time -p $clixon_netconf -qf $cfg" 0 "$fconfig" "^<rpc-reply $DEFAULTNS><ok/></rpc-reply>]]>]]>$" 2>&1 | awk '/real/ {print $2}'

# Here, there are $perfnr entries in candidate

# Now commit it from candidate to running 
new "netconf commit large config"
expecteof "time -p $clixon_netconf -qf $cfg" 0 "<rpc $DEFAULTNS><commit/></rpc>]]>]]>" "^<rpc-reply $DEFAULTNS><ok/></rpc-reply>]]>]]>$" 2>&1 | awk '/real/ {print $2}'

# RESTCONF get
new "restconf get $perfreq small config 1 key index"
{ time -p for (( i=0; i<$perfreq; i++ )); do
    rnd=$(( ( RANDOM % $perfnr ) ))
    curl $CURLOPTS -X GET $RCPROTO://localhost/restconf/data/scaling:x/y=$rnd > /dev/null
done } 2>&1 | awk '/real/ {print $2}'

# RESTCONF put
# Reference:
# i686 format=xml perfnr=10000/100 time: 38/29s 20190425  WITH/OUT startup copying
# i686 format=tree perfnr=10000/100 time: 72/64s 20190425 WITH/OUT startup copying
new "restconf add $perfreq small config"
{ time -p for (( i=0; i<$perfreq; i++ )); do
    rnd=$(( ( RANDOM % $perfnr ) ))
    curl $CURLOPTS -X PUT $RCPROTO://localhost/restconf/data/scaling:x/y=$rnd  -d '{"scaling:y":{"a":"'$rnd'","b":"'$rnd'"}}'
done }  2>&1 | awk '/real/ {print $2}'

new "restconf get large config"
# XXX for some reason cannot expand $TIMEFN next two tests, need keep variable?
$TIMEFN curl $CURLOPTS -X GET $RCPROTO://localhost/restconf/data 2>&1 > /dev/null | awk '/real/ {print $2}'

# Delete entries (last since entries are removed from db)
# netconf
new "cli delete $perfreq small config"
{ time -p for (( i=0; i<$perfreq; i++ )); do
    rnd=$(( ( RANDOM % $perfnr ) ))
    $clixon_cli -1 -f $cfg delete x y $rnd 
done } 2>&1 | awk '/real/ {print $2}'

#new "netconf discard-changes"
expecteof "$clixon_netconf -qf $cfg" 0 "<rpc $DEFAULTNS><discard-changes/></rpc>]]>]]>" "^<rpc-reply $DEFAULTNS><ok/></rpc-reply>]]>]]>$"

# XXX This takes time
# 18.69 without startup feature
# 21.98 with startup
new "restconf delete $perfreq small config"
{ time -p for (( i=0; i<$perfreq; i++ )); do
    rnd=$(( ( RANDOM % $perfnr ) ))
    curl $CURLOPTS -X DELETE $RCPROTO://localhost/restconf/data/scaling:x/y=$rnd
done > /dev/null; } 2>&1 | awk '/real/ {print $2}'

# Now do leaf-lists istead of leafs

#new "generate leaf-list config"
echo -n "<rpc $DEFAULTNS><edit-config><target><candidate/></target><default-operation>replace</default-operation><config><x xmlns=\"urn:example:clixon\">" > $fconfig2
for (( i=0; i<$perfnr; i++ )); do  
    echo -n "<c>$i</c>" >> $fconfig2
done
echo "</x></config></edit-config></rpc>]]>]]>" >> $fconfig2

new "netconf replace large list-leaf config"
expecteof_file "time -p $clixon_netconf -qf $cfg" 0 "$fconfig2" "^<rpc-reply $DEFAULTNS><ok/></rpc-reply>]]>]]>$" 2>&1 | awk '/real/ {print $2}'

new "netconf commit large leaf-list config"
expecteof "time -p $clixon_netconf -qf $cfg" 0 "<rpc $DEFAULTNS><commit/></rpc>]]>]]>" "^<rpc-reply $DEFAULTNS><ok/></rpc-reply>]]>]]>$" 2>&1 | awk '/real/ {print $2}'

new "netconf add $perfreq small leaf-list config"
{ time -p for (( i=0; i<$perfreq; i++ )); do
    rnd=$(( ( RANDOM % $perfnr ) ))
    echo "<rpc $DEFAULTNS><edit-config><target><candidate/></target><config><x xmlns=\"urn:example:clixon\"><c>$rnd</c></x></config></edit-config></rpc>]]>]]>"
done | $clixon_netconf -qf $cfg > /dev/null; } 2>&1 | awk '/real/ {print $2}'

new "netconf add small leaf-list config"
expecteof "time -p $clixon_netconf -qf $cfg" 0 "<rpc $DEFAULTNS><edit-config><target><candidate/></target><config><x xmlns=\"urn:example:clixon\"><c>x</c></x></config></edit-config></rpc>]]>]]>" "^<rpc-reply $DEFAULTNS><ok/></rpc-reply>]]>]]>$" 2>&1 | awk '/real/ {print $2}'

new "netconf commit small leaf-list config"
expecteof "time -p $clixon_netconf -qf $cfg" 0 "<rpc $DEFAULTNS><commit/></rpc>]]>]]>" "^<rpc-reply $DEFAULTNS><ok/></rpc-reply>]]>]]>$" 2>&1 | awk '/real/ {print $2}'

new "netconf get large leaf-list config"
expecteof "time -p $clixon_netconf -qf $cfg" 0 "<rpc $DEFAULTNS><get-config><source><candidate/></source></get-config></rpc>]]>]]>" "^<rpc-reply $DEFAULTNS><data><x xmlns=\"urn:example:clixon\"><c>0</c><c>1</c>" 2>&1 | awk '/real/ {print $2}'

if [ $RC -ne 0 ]; then
    new "Kill restconf daemon"
    stop_restconf
fi

if [ $BE -eq 0 ]; then
    exit # BE
fi

new "Kill backend"
# Check if premature kill
pid=$(pgrep -u root -f clixon_backend)
if [ -z "$pid" ]; then
    err "backend already dead"
fi
# kill backend
stop_backend -f $cfg

rm -rf $dir

# unset conditional parameters 
unset format
unset perfnr
unset perfreq

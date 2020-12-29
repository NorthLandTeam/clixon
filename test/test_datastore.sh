#!/usr/bin/env bash
# Magic line must be first in script (see README.md)
s="$_" ; . ./lib.sh || if [ "$s" = $0 ]; then exit 0; else return 0; fi

# datastore tests.
# Just run a binary direct to datastore. No clixon.

fyang=$dir/ietf-ip.yang

: ${clixon_util_datastore:=clixon_util_datastore}

cat <<EOF > $fyang
module ietf-ip{
   yang-version 1.1;
   namespace "urn:example:clixon";
   prefix ip;
   container x {
    list y {
      key "a b";
      leaf a {
        type string;
      }
      leaf b {
        type string;
      }
      leaf c {
        type string;
      }   
    }
    leaf d {
        type empty;
    }
    container f {
      leaf-list e {
        type string;
      }
    }
    leaf g {
      type string;  
    }
    container h {
      leaf j {
        type string;
      }
    }
  }
}
EOF

xml='<config><x xmlns="urn:example:clixon"><y><a>1</a><b>2</b><c>first-entry</c></y><y><a>1</a><b>3</b><c>second-entry</c></y><y><a>2</a><b>3</b><c>third-entry</c></y><d/><f><e>a</e><e>b</e><e>c</e></f><g>astring</g></x></config>'

name=text

mydir=$dir/$name

if [ ! -d $mydir ]; then
    mkdir $mydir
fi
rm -rf $mydir/*

conf="-d candidate -b $mydir -y $dir/ietf-ip.yang"

new "datastore init"
expectpart "$($clixon_util_datastore $conf init)" 0 ""

new "datastore put all replace"
ret=$($clixon_util_datastore $conf put replace "$xml")
expectmatch "$ret" $? "0" ""

new "datastore get"
expectpart "$($clixon_util_datastore $conf get /)" 0 "^$xml$"

new "datastore put all remove"
expectpart "$($clixon_util_datastore $conf put remove "<config/>")" 0 ""

new "datastore get"
expectpart "$($clixon_util_datastore $conf get /)" 0 "^<config/>$" 

new "datastore put all merge"
ret=$($clixon_util_datastore $conf put merge "$xml")
expectmatch "$ret" $? "0" ""

#    expectpart "$($clixon_util_datastore $conf put merge $xml)" 0 ""

new "datastore get"
expectpart "$($clixon_util_datastore $conf get /)" 0 "^$xml$"

new "datastore put all delete"
expectpart "$($clixon_util_datastore $conf put remove "<config/>")" 0 ""

new "datastore get"
expectpart "$($clixon_util_datastore $conf get /)" 0 "^<config/>$"

new "datastore put all create"
ret=$($clixon_util_datastore $conf put create "$xml")
expectmatch "$ret" $? "0" ""

new "datastore get"
expectpart "$($clixon_util_datastore $conf get /)" 0 "^$xml$"

new "datastore put top create"
expectpart "$($clixon_util_datastore $conf put create "<config><x/></config>")" 0 "" # error

# Single key operations
# leaf
new "datastore put all delete"
expectpart "$($clixon_util_datastore $conf delete)" 0 ""

new "datastore init"
expectpart "$($clixon_util_datastore $conf init)" 0 ""

new "datastore create leaf"
expectpart "$($clixon_util_datastore $conf put create "<config><x><y><a>1</a><b>3</b><c>newentry</c></y></x></config>")" 0 ""

new "datastore create leaf"
expectpart "$($clixon_util_datastore $conf put create '<config><x><y><a>1</a><b>3</b><c>newentry</c></y></x></config>')" 0 ""

new "datastore delete leaf"
expectpart "$($clixon_util_datastore $conf put delete '<config><x><y><a>1</a><b>3</b></y></x></config>')" 0 ""

new "datastore replace leaf"
expectpart "$($clixon_util_datastore $conf put create '<config><x><y><a>1</a><b>3</b><c>newentry</c></y></x></config>')" 0 ""

new "datastore remove leaf"
expectpart "$($clixon_util_datastore $conf put remove '<config><x><g/></x></config>')" 0 ""

new "datastore remove leaf"
expectpart "$($clixon_util_datastore $conf put remove '<config><x><y><a>1</a><b>3</b><c/></y></x></config>')" 0 ""

new "datastore delete leaf"
expectpart "$($clixon_util_datastore $conf put delete '<config><x><g/></x></config>')" 0 ""

new "datastore merge leaf"
expectpart "$($clixon_util_datastore $conf put merge '<config><x><g>nalle</g></x></config>')" 0 ""

new "datastore replace leaf"
expectpart "$($clixon_util_datastore $conf put replace '<config><x><g>nalle</g></x></config>')" 0 ""

new "datastore merge leaf"
expectpart "$($clixon_util_datastore $conf put merge '<config><x><y><a>1</a><b>3</b><c>newentry</c></y></x></config>')" 0 ""

new "datastore replace leaf"
expectpart "$($clixon_util_datastore $conf put replace '<config><x><y><a>1</a><b>3</b><c>newentry</c></y></x></config>')" 0 ""

new "datastore create leaf"
expectpart "$($clixon_util_datastore $conf put create '<config><x><h><j>aaa</j></h></x></config>')" 0 ""

new "datastore create leaf"
expectpart "$($clixon_util_datastore $conf put create '<config><x><y><a>1</a><b>3</b><c>newentry</c></y></x></config>')" 0 ""

new "datastore other db init"
expectpart "$($clixon_util_datastore -d kalle -b $mydir -y $dir/ietf-ip.yang init)" 0 ""

new "datastore other db copy"
expectpart "$($clixon_util_datastore $conf copy kalle)" 0 ""

diff $mydir/kalle_db $mydir/candidate_db

new "datastore lock"
expectpart "$($clixon_util_datastore $conf lock 756)" 0 ""

# unset conditional parameters 
unset clixon_util_datastore

rm -rf $mydir

rm -rf $dir


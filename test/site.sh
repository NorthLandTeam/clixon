#!#/bin/sh
# Use this file to specify local site-specific env variables, or tests to
# skip. This file is sourced by lib.sh
#
# Add test filenames that you do not want to run to the SKIPLIST variable. The
# SKIPLIST is evaluated as a Bash glob in lib.sh, so you can use it to skip
# files from the begining of the file list up to a pattern by specifying an
# appropriate glob such as "test_[a-n]*\.sh".
#
# The SKIPLIST has precedence over the 'pattern' variable that you can use to
# specify included file when running the various test scripts such as "all.sh".
#SKIPLIST="test_[a-t]*\.sh test_openconfig.sh test_yangmodels.sh"
#
# Parse yang openconfig models from https://github.com/openconfig/public
#OPENCONFIG=/usr/local/share/openconfig/public
#
# Parse yangmodels from https://github.com/YangModels/yang
#YANGMODELS=/usr/local/share/yang
#
# Specify alternative directory for the standard IETF RFC yang files. 
#IETFRFC=$YANGMODELS/standard/ietf/RFC

# Some restconf tests can run IPv6, but its complicated because:
# - docker by default does not run IPv6
#IPv6=false

# Check sanity between --with-restconf setting and if nginx is started by systemd or not
# This check is optional because some installs, such as vagrant make a non-systemd/direct
# start
#NGINXCHECK=false

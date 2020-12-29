# Clixon tests and CI

## Overview

Tests called 'test_*.sh' and placed in this directory will be
automatically run as part of the all.sh, sum.sh tests etc. The scripts
need to follow some rules to work properly, please look at one or two
to get the idea.

See also the [site.sh](#site-sh) for example for skipping tests or setting some site-specific variables.

## Continuous Integration

CI is done via [Travis CI](https://travis-ci.org/clicon/clixon).

In the CI process, the system is built and configured and then the
[clixon test container](../docker/system) is built and the tests in
this directory is executed.

There are also [manual cicd scripts here](cicd/README.md)

## Vagrant

[Vagrant scripts are here](vagrant/README.md)

## Getting started

You need to build and install the clixon utility programs before running the tests as some of the tests rely on them:
```
  cd util
  make
  sudo make install
```

You need to configure and start nginx for the restconf tests:
* The [example](../example/main/README.md) has instructions on how to edit your nginx config files
* If you run systemd: `sudo systemctl start nginx.service`

You may need to install the `time` utility (`/usr/bin/time`). 

## Prefix variable

You can prefix a test with `BE=0` if you want to run your own backend.

To run with debug flags, use the `DBG=<number>` environment variable.

Other variables include:
* DEMWAIT Number of seconds to sleep after daemons have started

## Run all tests

You can run an individual test by itself, or run through all tests matching 'test_*.sh' in the directory. Prints test output and stops on first error:
```
  all.sh
```

Run all tests but continue after errors and only print a summary test output identifying which tests succeeded and which failed:
```
  sum.sh
```

## Memory leak test
The `mem.sh` runs memory checks using valgrind. Start it with no arguments to test all components (backend, restconf, cli, netconf), or specify which components to run:
```
  mem.sh    2>&1 | tee mylog        # All components
  mem.sh restconf backend           # Only backend and cli
```

## Run pattern of tests

The above scripts work with the `pattern` variable to limit the scope of which tests run, eg:
```
  pattern="test_c*.sh" mem.sh
```

## Performance plots

The script `plot_perf.sh` produces gnuplots for some testcases.

## Site.sh
You may add your site-specific modifications in a `site.sh` file. Example:
```
  # Add your local site specific env variables (or tests) here.
  # Add test to this list that you dont want run
  SKIPLIST="test_openconfig.sh test_yangmodels.sh"
  # Parse yang openconfig models from https://github.com/openconfig/public
  OPENCONFIG=/usr/local/share/openconfig/public
  # Parse yangmodels from https://github.com/YangModels/yang
  YANGMODELS=/usr/local/share/yangmodels
  # Standard IETF RFC yang files. 
  IETFRFC=$YANGMODELS/standard/ietf/RFC
```

For example, in FreeBSD, add:
```
  wwwuser=www
  make=gmake
```

## https

For fcgi/nginx you need to setup https in the nginx config file, independently of clixon.

If you use evhtp with `configure --with-restconf=evhtp`, you can prepend the tests with RCPROTO=https which will run all restconf tests with SSL https and server certs.

Ensure the server keys are in order, as follows.

If you already have server certs, ensure the RESTCONF variable in lib.sh points to them, by default the config is
```
  <server-cert-path>/etc/ssl/certs/clixon-server-crt.pem</server-cert-path>
  <server-key-path>/etc/ssl/private/clixon-server-key.pem</server-key-path>
  <server-ca-cert-path>/etc/ssl/certs/clixon-ca-crt.pem</server-ca-cert-path>
```

If you do not have them, generate self-signed certs, eg as follows:
```
  openssl req -x509 -nodes -newkey rsa:4096 -keyout /etc/ssl/private/clixon-server-key.pem -out /etc/ssl/certs/clixon-server-crt.pem -days 365
```

There are also client-cert tests, eg `test_ssl_certs.sh`

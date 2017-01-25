#! __ATF_SH__
# Copyright 2013 Google Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# * Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in the
#   documentation and/or other materials provided with the distribution.
# * Neither the name of Google Inc. nor the names of its contributors
#   may be used to endorse or promote products derived from this software
#   without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# \file netbsd_release_test.sh
# Integration tests for the netbsd_release sandbox type.


# Paths to installed files.
#
# Can be overriden for test purposes only.
: ${SANDBOXCTL_MODULESDIR="__SANDBOXCTL_MODULESDIR__"}


# Creates a fake tgz set with a single file in it.
#
# \param releasedir Path to the root of the release directory.
# \param name Basename of the set to create, without an extension.
create_set() {
    local releasedir="${1}"; shift
    local name="${1}"; shift

    touch "${name}.cookie"
    tar -cz -f "${releasedir}/binary/sets/${name}.tgz" "${name}.cookie"
    rm "${name}.cookie"
}


atf_test_case config__builtins
config__builtins_body() {
    isolate_module netbsd_release

    cat >expout <<EOF
NETBSD_RELEASE_RELEASEDIR = /home/sysbuild/release/$(uname -m)
NETBSD_RELEASE_SETS is undefined
SANDBOX_ROOT is undefined
SANDBOX_TYPE = empty
EOF
    atf_check -o file:expout sandboxctl -c /dev/null config
}


atf_test_case integration cleanup
integration_head() {
    atf_set "require.config" "netbsd_releasedir"
    atf_set "require.user" "root"
}
integration_body() {
    [ "$(uname -s)" = 'NetBSD' ] || atf_skip "Requires a NetBSD host"

    cat >custom.conf <<EOF
SANDBOX_ROOT="$(pwd)/sandbox"
SANDBOX_TYPE="netbsd-release"

NETBSD_RELEASE_RELEASEDIR="$(atf_config_get netbsd_releasedir)"
NETBSD_RELEASE_SETS="base.tgz etc.tgz"
EOF

    atf_check -e not-match:' W: ' -e not-match:' E: ' \
        sandboxctl -c custom.conf create

    # The commands invoked within the sandbox must check:
    # - Presence of binaries (obviously).
    # - Presence of configuration files.  Chowning a file ensures that, at
    #   least, the passwords database is present and valid.
    # - Invocation of MAKEDEV.  Using a device from /dev/ should be enough.
    # - Invocation of su, to potentially trigger a write to /var.
    atf_check -e ignore sandboxctl -c custom.conf run /bin/sh -c \
        'dd if=/dev/zero of=/tmp/testfile bs=1k count=1 \
         && chown root /tmp/testfile \
         && su root /bin/sh -c "touch /tmp/sufile"'
    [ -f sandbox/tmp/testfile ] || atf_fail 'Test file not created as expected'
    [ -f sandbox/tmp/sufile ] || atf_fail 'Test file not created as expected'
    dd if=/dev/zero of=testfile bs=1k count=1
    cmp -s sandbox/tmp/testfile testfile || atf_fail 'Test file invalid'

    atf_check sandboxctl -c custom.conf destroy
    rm custom.conf
}
integration_cleanup() {
    [ ! -f custom.conf ] || sandboxctl -c custom.conf destroy || true
}


atf_test_case auto_sets
auto_sets_head() {
    atf_set "require.config" "netbsd_releasedir"
    atf_set "require.user" "root"
}
auto_sets_body() {
    [ "$(uname -s)" = 'NetBSD' ] || atf_skip "Requires a NetBSD host"

    mkdir -p release/binary/sets
    ln -s "$(atf_config_get netbsd_releasedir)/binary/sets/base.tgz" \
        release/binary/sets/
    ln -s "$(atf_config_get netbsd_releasedir)/binary/sets/etc.tgz" \
        release/binary/sets/
    touch release/binary/sets/NOT-A-SET
    create_set release extra1
    create_set release extra2
    create_set release kern-A
    create_set release kern-GENERIC
    create_set release kern-Z

    cat >custom.conf <<EOF
SANDBOX_ROOT="$(pwd)/sandbox"
SANDBOX_TYPE="netbsd-release"

NETBSD_RELEASE_RELEASEDIR="$(pwd)/release"
NETBSD_RELEASE_SETS=
EOF

    atf_check -e not-match:' W: ' -e not-match:' E: ' \
        sandboxctl -c custom.conf create

    for set_name in extra1 extra2 kern-GENERIC; do
        [ -f sandbox/"${set_name}.cookie" ] \
            || atf_fail "${set_name} not extracted"
    done
    [ ! -f sandbox/kern-A.cookie ] || atf_fail "Unexpected kernel A extracted"
    [ ! -f sandbox/kern-Z.cookie ] || atf_fail "Unexpected kernel Z extracted"

    sandboxctl -c custom.conf destroy
    rm custom.conf
}
auto_sets_cleanup() {
    [ ! -f custom.conf ] || sandboxctl -c custom.conf destroy || true
}


atf_test_case auto_sets__no_generic
auto_sets__no_generic_head() {
    atf_set "require.config" "netbsd_releasedir"
    atf_set "require.user" "root"
}
auto_sets__no_generic_body() {
    [ "$(uname -s)" = 'NetBSD' ] || atf_skip "Requires a NetBSD host"

    mkdir -p release/binary/sets
    ln -s "$(atf_config_get netbsd_releasedir)/binary/sets/base.tgz" \
        release/binary/sets/
    ln -s "$(atf_config_get netbsd_releasedir)/binary/sets/etc.tgz" \
        release/binary/sets/
    create_set release kern-A
    create_set release kern-Z

    cat >custom.conf <<EOF
SANDBOX_ROOT="$(pwd)/sandbox"
SANDBOX_TYPE="netbsd-release"

NETBSD_RELEASE_RELEASEDIR="$(pwd)/release"
NETBSD_RELEASE_SETS=
EOF

    atf_check -e not-match:' W: ' -e not-match:' E: ' \
        sandboxctl -c custom.conf create

    [ -f sandbox/kern-A.cookie ] || atf_fail "Expected kernel A not extracted"
    [ ! -f sandbox/kern-Z.cookie ] || atf_fail "Unexpected kernel Z extracted"

    sandboxctl -c custom.conf destroy
    rm custom.conf
}
auto_sets_cleanup() {
    [ ! -f custom.conf ] || sandboxctl -c custom.conf destroy || true
}


atf_init_test_cases() {
    atf_add_test_case config__builtins

    atf_add_test_case integration

    atf_add_test_case auto_sets
    atf_add_test_case auto_sets__no_generic
}

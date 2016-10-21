#! __ATF_SH__
# Copyright 2016 Google Inc.
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

# \file freebsd_native_test.sh
# Integration tests for the freebsd_native sandbox type.


# Paths to installed files.
#
# Can be overriden for test purposes only.
: ${SANDBOXCTL_MODULESDIR="__SANDBOXCTL_MODULESDIR__"}


atf_test_case config__builtins
config__builtins_body() {
    isolate_module freebsd_native

    cat >expout <<EOF
FREEBSD_NATIVE_SOURCE = /usr/src
SANDBOX_ROOT is undefined
SANDBOX_TYPE = empty
EOF
    atf_check -o file:expout sandboxctl -c /dev/null config
}


common_integration_body() {
    local source="${1}"; shift

    [ "$(uname -s)" = 'FreeBSD' ] || atf_skip "Requires a FreeBSD host"

    cat >>custom.conf <<EOF
FREEBSD_NATIVE_SOURCE="${source}"
SANDBOX_ROOT="$(pwd)/sandbox"
SANDBOX_TYPE="freebsd-native"
EOF

    atf_check -e not-match:' W: ' -e not-match:' E: ' \
        sandboxctl -c custom.conf create

    # The commands invoked within the sandbox must check:
    # - Presence of binaries (obviously).
    # - Presence and writability of configuration files.  Adding a test user
    #   ensures that, at least, the passwords database is present and valid.
    # - Invocation of MAKEDEV.  Using a device from /dev/ should be enough.
    # - Ability to update the passwords database, which indirectly means a
    #   writable /etc.
    # - Configuration of /bin/sh as the default shell.
    cat >sandbox/tmp/checks.sh <<EOF
#! /bin/sh

fail() { echo "\${@}" 1>&2; exit 1; }

pw useradd -n testuser -s /bin/sh -m -w no || fail "User addition failed"
dd if=/dev/zero of=/tmp/testfile bs=1k count=1 || fail "Devices failed"

[ "\${SHELL}" = /bin/sh ] || fail "SHELL is \${SHELL} but should be /bin/sh"
EOF
    chmod +x sandbox/tmp/checks.sh

    grep "^testuser" sandbox/etc/passwd \
        && atf_fail 'passwd already contains test user'

    atf_check -e ignore sandboxctl -c custom.conf run /tmp/checks.sh

    grep "^testuser" sandbox/etc/passwd \
        || atf_fail 'passwd was not correctly updated'
    [ -f sandbox/tmp/testfile ] || atf_fail 'Test file not created as expected'
    dd if=/dev/zero of=testfile bs=1k count=1
    cmp -s sandbox/tmp/testfile testfile || atf_fail 'Test file invalid'

    atf_check sandboxctl -c custom.conf destroy
    rm custom.conf
}


common_integration_cleanup() {
    [ ! -f custom.conf ] || sandboxctl -c custom.conf destroy || true
}


atf_test_case integration_srcdir cleanup
integration__srcdir_head() {
    atf_set "require.config" "freebsd_srcdir"
    atf_set "require.user" "root"
}
integration__srcdir_body() {
    common_integration_body "$(atf_config_get freebsd_srcdir)"
}
integration__srcdir_cleanup() {
    common_integration_cleanup
}


atf_test_case integration_sets cleanup
integration__sets_head() {
    atf_set "require.config" "freebsd_releasedir"
    atf_set "require.user" "root"
}
integration__sets_body() {
    common_integration_body "$(atf_config_get freebsd_releasedir)"
}
integration__sets_cleanup() {
    common_integration_cleanup
}


atf_init_test_cases() {
    atf_add_test_case config__builtins

    atf_add_test_case integration__srcdir
    atf_add_test_case integration__sets
}

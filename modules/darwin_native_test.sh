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

# \file darwin_native_test.sh
# Integration tests for the darwin_native sandbox type.


# Paths to installed files.
#
# Can be overriden for test purposes only.
: ${SANDBOXCTL_MODULESDIR="__SANDBOXCTL_MODULESDIR__"}


atf_test_case config__builtins
config__builtins_body() {
    isolate_module darwin_native

    cat >expout <<EOF
DARWIN_NATIVE_WITH_XCODE = false
SANDBOX_ROOT is undefined
SANDBOX_TYPE = empty
EOF
    atf_check -o file:expout sandboxctl -c /dev/null config
}


atf_test_case integration__basic cleanup
integration__basic_head() {
    atf_set "require.user" "root"
}
integration__basic_body() {
    [ "$(uname -s)" = 'Darwin' ] || atf_skip "Requires a Darwin host"

    cat >custom.conf <<EOF
SANDBOX_ROOT="$(pwd)/sandbox"
SANDBOX_TYPE="darwin-native"
EOF

    # Force HOME to be under /var to ensure that the directory is created only
    # after /var has been established as a symlink; otherwise /var becomes a
    # real directory, which can later confuse getconf (tested below).
    atf_check -e not-match:' W: ' -e not-match:' E: ' \
        env HOME=/var/something sandboxctl -c custom.conf create

    [ ! -e sandbox/Applications/Xcode.app ] || atf_fail "Xcode was copied" \
        "into the sandbox but we did not request it"

    # The commands invoked within the sandbox must check:
    # - Presence of binaries (obviously).
    # - Presence of configuration files.  Chowning a file ensures that, at
    #   least, the passwords database is present and valid.
    # - Invocation of MAKEDEV.  Using a device from /dev/ should be enough.
    # - Invocation of su, to potentially trigger a write to /var.
    # - Writability of /tmp, which is usually a symlink.
    # - Writability of /var (via getconf).
    # - Name resolution works with mDNSResponder (via curl).
    atf_check -o ignore -e ignore sandboxctl -c custom.conf run /bin/sh -c \
        'dd if=/dev/zero of=/tmp/testfile bs=1k count=1 \
         && chown root /tmp/testfile \
         && getconf DARWIN_USER_TEMP_DIR >/tmp/getconf \
         && su root -c "touch /tmp/sufile" \
         && cp /etc/resolv.conf /tmp/resolv.conf \
         && curl example.com >tmp/example.html'
    [ -f sandbox/tmp/testfile ] || atf_fail 'Test file not created as expected'
    [ -s sandbox/tmp/getconf ] || atf_fail 'Test file not created as expected'
    [ -f sandbox/tmp/sufile ] || atf_fail 'Test file not created as expected'
    [ -s sandbox/tmp/resolv.conf ] || atf_fail 'resolv.conf is bogus'
    dd if=/dev/zero of=testfile bs=1k count=1
    cmp -s sandbox/tmp/testfile testfile || atf_fail 'Test file invalid'
    grep -i '<html' sandbox/tmp/example.html >/dev/null \
        || atf_fail 'Invalid response from example.com; bad DNS configuration?'

    atf_check sandboxctl -c custom.conf destroy
    rm custom.conf
}
integration_cleanup() {
    [ ! -f custom.conf ] || sandboxctl -c custom.conf destroy || true
}


atf_test_case integration__with_xcode cleanup
integration__with_xcode_head() {
    atf_set "require.files" "/Applications/Xcode.app"
    atf_set "require.user" "root"
    atf_set "timeout" "900"
}
integration__with_xcode_body() {
    [ "$(uname -s)" = 'Darwin' ] || atf_skip "Requires a Darwin host"

    cat >custom.conf <<EOF
SANDBOX_ROOT="$(pwd)/sandbox"
SANDBOX_TYPE="darwin-native"
DARWIN_NATIVE_WITH_XCODE=true
EOF

    atf_check -e not-match:' W: ' -e not-match:' E: ' \
        sandboxctl -c custom.conf create

    cat >sandbox/tmp/hello.c <<EOF
#include <stdio.h>
int main(void) {
    printf("Hello, Xcode!\n");
    return 0;
}
EOF

    atf_check -o match:'Hello, Xcode!' -e ignore \
        sandboxctl -c custom.conf run /bin/sh -c \
        'xcodebuild -license accept \
         ; cc -o /tmp/hello /tmp/hello.c \
         && /tmp/hello'
    [ -x sandbox/tmp/hello ] || atf_fail 'Test binary not created as expected'

    atf_check sandboxctl -c custom.conf destroy
    rm custom.conf
}
integration_cleanup() {
    [ ! -f custom.conf ] || sandboxctl -c custom.conf destroy || true
}


atf_init_test_cases() {
    atf_add_test_case config__builtins

    atf_add_test_case integration__basic
    atf_add_test_case integration__with_xcode
}

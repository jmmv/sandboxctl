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


# Creates a fake set with a single file in it.
#
# \param releasedir Path to the root of the release directory.
# \param name Basename of the set to create.
create_set() {
    local releasedir="${1}"; shift
    local name="${1}"; shift

    local flag
    case "${name}" in
        *.tar.xz) flag=J ;;
        *.tgz) flag=z ;;
    esac

    touch "${name}.cookie"
    tar "-c${flag}" -f "${releasedir}/binary/sets/${name}" "${name}.cookie"
    rm "${name}.cookie"
}


# Guesses the format of the release sets and returns their extension.
#
# \param releasedir Path to the root directory of the release files.
guess_sets_format() {
    local releasedir="${1}"; shift

    if [ -e "${releasedir}/binary/sets/base.tar.xz" ]; then
        echo "tar.xz"
    else
        echo "tgz"
    fi
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
NETBSD_RELEASE_SETS="base etc"
EOF

    atf_check -e not-match:' W: ' -e not-match:' E: ' \
        sandboxctl -c custom.conf create

    # The commands invoked within the sandbox must check:
    # - Presence of binaries (obviously).
    # - Presence of configuration files.  Chowning a file ensures that, at
    #   least, the passwords database is present and valid.
    # - Invocation of MAKEDEV.  Using a device from /dev/ should be enough.
    # - Invocation of su, to potentially trigger a write to /var.
    # - Name resolution works (via ftp).
    atf_check -e ignore sandboxctl -c custom.conf run /bin/sh -c \
        'dd if=/dev/zero of=/tmp/testfile bs=1k count=1 \
         && chown root /tmp/testfile \
         && su root -c "touch /tmp/sufile" \
         && ftp -o /tmp/example.html http://example.com/'
    [ -f sandbox/tmp/testfile ] || atf_fail 'Test file not created as expected'
    [ -f sandbox/tmp/sufile ] || atf_fail 'Test file not created as expected'
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


atf_test_case auto_sets
auto_sets_head() {
    atf_set "require.config" "netbsd_releasedir"
    atf_set "require.user" "root"
}
auto_sets_body() {
    [ "$(uname -s)" = 'NetBSD' ] || atf_skip "Requires a NetBSD host"

    local ext="$(guess_sets_format "$(atf_config_get netbsd_releasedir)")"

    mkdir -p release/binary/sets
    ln -s "$(atf_config_get netbsd_releasedir)/binary/sets/base.${ext}" \
        release/binary/sets/
    ln -s "$(atf_config_get netbsd_releasedir)/binary/sets/etc.${ext}" \
        release/binary/sets/
    touch release/binary/sets/NOT-A-SET
    create_set release extra1."${ext}"
    create_set release extra2."${ext}"
    create_set release kern-A."${ext}"
    create_set release kern-GENERIC."${ext}"
    create_set release kern-Z."${ext}"

    cat >custom.conf <<EOF
SANDBOX_ROOT="$(pwd)/sandbox"
SANDBOX_TYPE="netbsd-release"

NETBSD_RELEASE_RELEASEDIR="$(pwd)/release"
NETBSD_RELEASE_SETS=
EOF

    atf_check -e not-match:' W: ' -e not-match:' E: ' \
        sandboxctl -c custom.conf create

    for set_name in extra1 extra2 kern-GENERIC; do
        [ -f sandbox/"${set_name}.${ext}.cookie" ] \
            || atf_fail "${set_name} not extracted"
    done
    [ ! -f "sandbox/kern-A.${ext}.cookie" ] \
        || atf_fail "Unexpected kernel A extracted"
    [ ! -f "sandbox/kern-Z.${ext}.cookie" ] \
        || atf_fail "Unexpected kernel Z extracted"

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

    local ext="$(guess_sets_format "$(atf_config_get netbsd_releasedir)")"

    mkdir -p release/binary/sets
    ln -s "$(atf_config_get netbsd_releasedir)/binary/sets/base.${ext}" \
        release/binary/sets/
    ln -s "$(atf_config_get netbsd_releasedir)/binary/sets/etc.${ext}" \
        release/binary/sets/
    create_set release kern-A."${ext}"
    create_set release kern-Z."${ext}"

    cat >custom.conf <<EOF
SANDBOX_ROOT="$(pwd)/sandbox"
SANDBOX_TYPE="netbsd-release"

NETBSD_RELEASE_RELEASEDIR="$(pwd)/release"
NETBSD_RELEASE_SETS=
EOF

    atf_check -e not-match:' W: ' -e not-match:' E: ' \
        sandboxctl -c custom.conf create

    [ -f "sandbox/kern-A.${ext}.cookie" ] \
        || atf_fail "Expected kernel A not extracted"
    [ ! -f "sandbox/kern-Z.${ext}.cookie" ] \
        || atf_fail "Unexpected kernel Z extracted"

    sandboxctl -c custom.conf destroy
    rm custom.conf
}
auto_sets__no_generic_cleanup() {
    [ ! -f custom.conf ] || sandboxctl -c custom.conf destroy || true
}


atf_test_case auto_sets__other_format
auto_sets__other_format_head() {
    atf_set "require.config" "netbsd_releasedir"
    atf_set "require.user" "root"
}
auto_sets__other_format_body() {
    [ "$(uname -s)" = 'NetBSD' ] || atf_skip "Requires a NetBSD host"

    local ext="$(guess_sets_format "$(atf_config_get netbsd_releasedir)")"
    local other_ext=

    mkdir -p release/binary/sets
    for set_name in base etc; do
        local src="$(atf_config_get netbsd_releasedir)"
        src="${src}/binary/sets/${set_name}.${ext}"
        case "${ext}" in
            tar.xz)
                xz -cd "${src}" \
                    | gzip -c1 >"release/binary/sets/${set_name}.tgz"
                other_ext=tgz
                ;;
            tgz)
                gzip -cd "${src}" \
                    | xz -c0 >"release/binary/sets/${set_name}.tar.xz"
                other_ext=tar.xz
                ;;
            *)
                atf_fail "Don't know how to handle format ${ext}"
        esac
    done
    create_set release foo."${other_ext}"
    create_set release bar."${ext}"

    cat >custom.conf <<EOF
SANDBOX_ROOT="$(pwd)/sandbox"
SANDBOX_TYPE="netbsd-release"

NETBSD_RELEASE_RELEASEDIR="$(pwd)/release"
NETBSD_RELEASE_SETS=
EOF

    atf_check -e not-match:' W: ' -e not-match:' E: ' \
        sandboxctl -c custom.conf create

    [ -f sandbox/bin/ls ] || atf_fail "Expected set base not extracted"
    [ -f "sandbox/foo.${other_ext}.cookie" ] \
        || atf_fail "Expected set foo not extracted"
    [ ! -f "sandbox/bar.${ext}.cookie" ] \
        || atf_fail "Unexpected set bar extracted"

    sandboxctl -c custom.conf destroy
    rm custom.conf
}
auto_sets__other_format_cleanup() {
    [ ! -f custom.conf ] || sandboxctl -c custom.conf destroy || true
}


atf_init_test_cases() {
    atf_add_test_case config__builtins

    atf_add_test_case integration

    atf_add_test_case auto_sets
    atf_add_test_case auto_sets__no_generic
    atf_add_test_case auto_sets__other_format
}

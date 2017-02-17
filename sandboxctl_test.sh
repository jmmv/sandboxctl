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

# \file sandboxctl_test.sh
# Tests for the sandboxctl.sh script.
#
# The tests in this file should be OS-agnostic.  They validate the generic
# behavior of the tool using a mock sandbox type.  Every supported sandbox
# is tested in a separate test program.


# Paths to installed files.
#
# Can be overriden for test purposes only.
: ${SANDBOXCTL_MODULESDIR="__SANDBOXCTL_MODULESDIR__"}


# Creates a configuration using a mock sandbox type.
#
# This mock sandbox type records all actions performed in the given file to
# the standard output.  This log can later be used to validate that every
# handler has been called in the right order and the expected number of times.
#
# \param config_file Name of the configuration file to create.
# \param sandbox_root Path to the root of the sandbox to be created.
create_config_with_mock_type() {
    local config_file="${1}"; shift
    local sandbox_root="${1}"; shift

    mkdir modules
    cat >"modules/mock.subr" <<EOF
mock_config_vars() { echo MOCK_VARIABLE; }
mock_set_defaults() { shtk_config_set MOCK_VARIABLE mock-value; }
mock_create() { echo "mock_create \${*}"; }
mock_destroy() { echo "mock_destroy \${*}"; }
mock_mount() { echo "mock_mount \${*}"; }
mock_unmount() { echo "mock_unmount \${*}"; }
EOF
    export SANDBOXCTL_MODULESDIR="$(pwd)/modules"

    cat >"${config_file}" <<EOF
SANDBOX_ROOT="${sandbox_root}"
SANDBOX_TYPE="mock"
EOF
}


# Defines all possible hooks in a configuration file with successful hooks.
#
# \param config_file Name of the configuration file to extend.
add_hooks_to_config() {
    local config_file="${1}"; shift

    cat >>"${config_file}" <<EOF
post_create_hook() { echo "custom post_create_hook"; }
pre_destroy_hook() { echo "custom pre_destroy_hook"; }
post_mount_hook() { echo "custom post_mount_hook"; }
pre_unmount_hook() { echo "custom pre_unmount_hook"; }
EOF
}


# Creates a mock chroot tool and puts it in the path.
#
# The mock chroot executes the given command in the context of the target chroot
# directory, but does not actually perform a chroot.  Doing the actual chroot
# would be hard here because we would need to create a fully-featured sandbox
# (which is OS-specific and tested later in the type-specific tests) and because
# we would need root privileges.
create_mock_chroot() {
    cat >chroot <<EOF
#! /bin/sh
dir="\${1}"; shift
cd "\${dir}"
exec "\${@:-\${SHELL}}"
EOF
    chmod +x chroot
    PATH="$(pwd):${PATH}"
}


# Tests running a command with incomplete configuration.
#
# This makes sure the given command prints error messages on each missing
# configuration property and that it returns 1 on error, but cannot make sure
# that the command did not run through completion.
#
# \params ... Arguments to pass to sandboxctl, including the command name.
test_validate_config() {
    echo "SANDBOX_TYPE=" >custom.conf
    atf_check -s exit:1 \
        -e match:"E:.*SANDBOX_TYPE not set" \
        -e not-match:"E:.*SANDBOX_ROOT not set" \
        sandboxctl -c custom.conf "${@}"

    echo "SANDBOX_ROOT=" >custom.conf
    atf_check -s exit:1 \
        -e match:"E:.*SANDBOX_ROOT not set" \
        -e not-match:"E:.*SANDBOX_TYPE not set" \
        sandboxctl -c custom.conf "${@}"
}


atf_test_case config__builtins__no_modules
config__builtins__no_modules_body() {
    export SANDBOXCTL_MODULESDIR="$(pwd)/no-modules"
    cat >expout <<EOF
SANDBOX_ROOT is undefined
SANDBOX_TYPE = empty
EOF
    atf_check -o file:expout sandboxctl -c /dev/null config
}


atf_test_case config__builtins__some_modules
config__builtins__some_modules_body() {
    create_config_with_mock_type unused.conf unused-directory
    cat >expout <<EOF
MOCK_VARIABLE = mock-value
SANDBOX_ROOT is undefined
SANDBOX_TYPE = empty
EOF
    atf_check -o file:expout sandboxctl -c /dev/null config
}


atf_test_case config__path__components
config__path__components_body() {
    mkdir system
    export SANDBOXCTL_ETCDIR="$(pwd)/system"

    echo "SANDBOX_ROOT=the-root" >my-file
    atf_check -o match:"SANDBOX_ROOT = the-root" sandboxctl -c ./my-file config
}


atf_test_case config__path__extension
config__path__extension_body() {
    mkdir system
    export SANDBOXCTL_ETCDIR="$(pwd)/system"

    echo "SANDBOX_ROOT=another-root" >my-file.conf
    atf_check -o match:"SANDBOX_ROOT = another-root" sandboxctl \
        -c my-file.conf config
}


atf_test_case config__name__system_directory
config__name__system_directory_body() {
    mkdir system
    export SANDBOXCTL_ETCDIR="$(pwd)/system"

    echo "SANDBOX_TYPE=some-type" >system/foo.conf
    atf_check -o match:"SANDBOX_TYPE = some-type" sandboxctl -c foo config
}


atf_test_case config__name__not_found
config__name__not_found_body() {
    mkdir system
    export SANDBOXCTL_ETCDIR="$(pwd)/system"

    cat >experr <<EOF
sandboxctl: E: Cannot locate configuration named 'foobar'
Type 'man sandboxctl' for help
EOF
    atf_check -s exit:1 -o empty -e file:experr sandboxctl -c foobar config
}


atf_test_case config__overrides
config__overrides_body() {
    create_config_with_mock_type unused.conf unused-directory
    cat >custom.conf <<EOF
SANDBOX_ROOT=/custom/directory
SANDBOX_TYPE=custom-type
EOF

    cat >expout <<EOF
MOCK_VARIABLE = mock-value
SANDBOX_ROOT = /other/custom/directory
SANDBOX_TYPE is undefined
EOF
    atf_check -o file:expout sandboxctl -c custom.conf \
        -o SANDBOX_ROOT=/other/custom/directory -o SANDBOX_TYPE= config
}


atf_test_case config__one_variable
config__one_variable_body() {
    create_config_with_mock_type unused.conf unused-directory
    cat >expout <<EOF
MOCK_VARIABLE = mock-value
SANDBOX_ROOT is undefined
SANDBOX_TYPE = empty
EOF
    atf_check -o inline:'mock-value\n' \
        sandboxctl -c /dev/null config MOCK_VARIABLE
    atf_check -s exit:1 -e match:'SANDBOX_ROOT is not defined' \
        sandboxctl -c /dev/null config SANDBOX_ROOT
    atf_check -o inline:'empty\n' \
        sandboxctl -c /dev/null config SANDBOX_TYPE
    atf_check -s exit:1 -e match:'unknown_variable is not defined' \
        sandboxctl -c /dev/null config unknown_variable
}


atf_test_case config__too_many_args
config__too_many_args_body() {
    cat >experr <<EOF
sandboxctl: E: config takes at most one argument
Type 'man sandboxctl' for help
EOF
    atf_check -s exit:1 -e file:experr sandboxctl -c /dev/null config foo bar
}


atf_test_case create__ok
create__ok_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    atf_check -o inline:"mock_create $(pwd)/sandbox\n" \
        sandboxctl -c custom.conf create

    [ -d sandbox ] || atf_fail "Sandbox root not created"
    rmdir sandbox || atf_fail "Empty sandbox not really empty"
}


atf_test_case create__hooks
create__hooks_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    add_hooks_to_config custom.conf

    cat >expout <<EOF
mock_create $(pwd)/sandbox
custom post_create_hook
EOF
    atf_check -o file:expout sandboxctl -c custom.conf create

    [ -d sandbox ] || atf_fail "Sandbox root not created"
    rmdir sandbox || atf_fail "Empty sandbox not really empty"
}


atf_test_case create__already_exists
create__already_exists_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    touch sandbox

    atf_check -s exit:1 -e match:"E: Sandbox $(pwd)/sandbox already exists" \
        sandboxctl -c custom.conf create

    [ -f sandbox ] || atf_fail "Sandbox root was modified"
}


atf_test_case create__validate_config
create__validate_config_body() {
    test_validate_config create
}


atf_test_case create__fail_mkdir
create__fail_mkdir_head() {
    atf_set "require.user" "unprivileged"
}
create__fail_mkdir_body() {
    create_config_with_mock_type custom.conf "$(pwd)/subdir/sandbox"
    mkdir subdir
    chmod 500 subdir

    atf_check -s exit:1 \
        -e match:"sandboxctl: E: Failed to create sandbox root" \
        sandboxctl -c custom.conf create

    [ ! -d "$(pwd)/subdir/sandbox" ] || atf_fail "Sandbox was created"
}


atf_test_case create__fail_bad_type
create__fail_bad_type_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    echo "SANDBOX_TYPE=unknown-type" >>custom.conf

    atf_check -s exit:1 \
        -e match:"sandboxctl: E: Invalid sandbox type .*unknown-type" \
        sandboxctl -c custom.conf create

    [ ! -d "$(pwd)/sandbox" ] || atf_fail "Sandbox was created"
}


atf_test_case create__fail_in_type
create__fail_in_type_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox" failing
    echo 'mock_create() { echo "mock_create ${*}"; exit 1; }' >>custom.conf
    echo 'post_create_hook() { echo "custom post_create_hook"; }' >>custom.conf

    cat >expout <<EOF
mock_create $(pwd)/sandbox
mock_destroy $(pwd)/sandbox
EOF
    atf_check -s exit:1 -o file:expout \
        -e inline:"sandboxctl: E: Failed to create sandbox type mock\n" \
        sandboxctl -c custom.conf create

    [ ! -d sandbox ] || atf_fail "Sandbox was not cleaned up"
}


atf_test_case create__fail_hook
create__fail_hook_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    echo 'post_create_hook() { echo "custom post_create_hook"; exit 1; }' \
         >>custom.conf

    cat >expout <<EOF
mock_create $(pwd)/sandbox
custom post_create_hook
mock_destroy $(pwd)/sandbox
EOF
    atf_check -s exit:1 -o file:expout \
        -e inline:"sandboxctl: E: The hook post_create_hook returned an error\n" \
        sandboxctl -c custom.conf create

    [ ! -d sandbox ] || atf_fail "Sandbox was not cleaned up"
}


atf_test_case destroy__ok
destroy__ok_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    mkdir sandbox

    atf_check -o inline:"mock_destroy $(pwd)/sandbox\n" \
        sandboxctl -c custom.conf destroy

    [ ! -d sandbox ] || atf_fail "Sandbox not destroyed"
}


atf_test_case destroy__hooks
destroy__hooks_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    add_hooks_to_config custom.conf

    mkdir sandbox

    cat >expout <<EOF
custom pre_destroy_hook
mock_destroy $(pwd)/sandbox
EOF
    atf_check -o file:expout sandboxctl -c custom.conf destroy

    [ ! -d sandbox ] || atf_fail "Sandbox not destroyed"
}


atf_test_case destroy__non_existent
destroy__non_existent_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    atf_check -s exit:1 -e match:'Cannot destroy a non-existent sandbox' \
        sandboxctl -c custom.conf destroy
}


atf_test_case destroy__still_mounted cleanup
destroy__still_mounted_head() {
    atf_set "require.user" "root"
}
destroy__still_mounted_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    mkdir sandbox
    mkdir sandbox/tmp
    mount_tmpfs sandbox/tmp
    touch sandbox/tmp/file

    atf_check -s exit:1 -e match:'still be mounted; refusing to destroy' \
        sandboxctl -c custom.conf destroy

    [ -f sandbox/tmp/file ] || atf_fail "Sandbox destroyed by mistake"
}
destroy__still_mounted_cleanup() {
    umount sandbox/tmp >/dev/null 2>&1 || true
}


atf_test_case destroy__validate_config
destroy__validate_config_body() {
    test_validate_config destroy
}


atf_test_case destroy__fail_type
destroy__fail_type_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox" failing
    echo 'mock_destroy() { echo "mock_destroy ${*}"; exit 1; }' >>custom.conf
    echo 'pre_destroy_hook() { echo "custom pre_destroy_hook"; }' >>custom.conf

    mkdir sandbox

    cat >expout <<EOF
custom pre_destroy_hook
mock_destroy $(pwd)/sandbox
EOF
    atf_check -s exit:1 -o file:expout \
        -e inline:"sandboxctl: E: Failed to destroy sandbox type mock\n" \
        sandboxctl -c custom.conf destroy

    [ -d sandbox ] || atf_fail "Sandbox was cleaned up"
}


atf_test_case destroy__fail_hook
destroy__fail_hook_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    echo 'pre_destroy_hook() { echo "custom pre_destroy_hook"; exit 1; }' \
        >>custom.conf

    mkdir sandbox

    cat >expout <<EOF
custom pre_destroy_hook
EOF
    atf_check -s exit:1 -o file:expout \
        -e inline:"sandboxctl: E: The hook pre_destroy_hook returned an error\n" \
        sandboxctl -c custom.conf destroy

    [ -d sandbox ] || atf_fail "Sandbox was cleaned up"
}


atf_test_case mount__ok
mount__ok_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    mkdir sandbox

    atf_check -o inline:"mock_mount $(pwd)/sandbox\n" \
        sandboxctl -c custom.conf mount

    atf_check sandboxctl -c custom.conf mount
}


atf_test_case mount__hooks
mount__hooks_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    add_hooks_to_config custom.conf

    mkdir sandbox

    cat >expout <<EOF
mock_mount $(pwd)/sandbox
custom post_mount_hook
EOF
    atf_check -o file:expout sandboxctl -c custom.conf mount

    atf_check sandboxctl -c custom.conf mount
}


atf_test_case mount__non_existent
mount__non_existent_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    atf_check -s exit:1 -e match:'Cannot mount a non-existent sandbox' \
        sandboxctl -c custom.conf mount
}


atf_test_case mount__already_mounted cleanup
mount__already_mounted_head() {
    atf_set "require.user" "root"
}
mount__already_mounted_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    mkdir sandbox
    mkdir sandbox/mnt
    mount_tmpfs sandbox/mnt

    atf_check -s exit:1 -e match:'Sandbox in inconsistent state' \
        sandboxctl -c custom.conf mount

    mount | grep sandbox/mnt >/dev/null || atf_fail "File systems were" \
        "unmounted but should not have been"
}
mount__already_mounted_cleanup() {
    umount sandbox/mnt >/dev/null 2>&1 || true
}


atf_test_case mount__validate_config
mount__validate_config_body() {
    test_validate_config mount
}


atf_test_case mount__fail_type
mount__fail_type_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox" failing
    echo 'mock_mount() { echo "mock_mount ${*}"; exit 1; }' >>custom.conf
    echo 'post_mount_hook() { echo "custom post_mount_hook"; }' >>custom.conf

    mkdir sandbox

    cat >expout <<EOF
mock_mount $(pwd)/sandbox
mock_unmount $(pwd)/sandbox
EOF
    atf_check -s exit:1 -o file:expout \
        -e inline:"sandboxctl: E: Failed to mount sandbox type mock\n" \
        sandboxctl -c custom.conf mount

    [ -d sandbox ] || atf_fail "Sandbox was cleaned up"
}


atf_test_case mount__fail_hook
mount__fail_hook_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    echo 'post_mount_hook() { echo "custom post_mount_hook"; exit 1; }' \
        >>custom.conf

    mkdir sandbox

    cat >expout <<EOF
mock_mount $(pwd)/sandbox
custom post_mount_hook
mock_unmount $(pwd)/sandbox
EOF
    atf_check -s exit:1 -o file:expout \
        -e inline:"sandboxctl: E: The hook post_mount_hook returned an error\n" \
        sandboxctl -c custom.conf mount

    [ -d sandbox ] || atf_fail "Sandbox was cleaned up"
}


atf_test_case unmount__ok
unmount__ok_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    mkdir sandbox

    atf_check -o ignore sandboxctl -c custom.conf mount

    atf_check -o inline:"mock_unmount $(pwd)/sandbox\n" \
        sandboxctl -c custom.conf unmount
}


atf_test_case unmount__hooks
unmount__hooks_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    add_hooks_to_config custom.conf

    mkdir sandbox

    atf_check -o ignore sandboxctl -c custom.conf mount

    cat >expout <<EOF
custom pre_unmount_hook
mock_unmount $(pwd)/sandbox
EOF
    atf_check -o file:expout sandboxctl -c custom.conf unmount
}


atf_test_case unmount__not_mounted
unmount__not_mounted_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    mkdir sandbox

    atf_check -s exit:1 -e match:"Sandbox not locked" \
        sandboxctl -c custom.conf unmount
}


atf_test_case unmount__force
unmount__force_head() {
    atf_set "require.user" "unprivileged"
}
unmount__force_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    mkdir sandbox

    atf_check -o inline:"mock_mount $(pwd)/sandbox\n" \
        sandboxctl -c custom.conf mount

    touch sandbox/.sandbox_lock.tmp
    chmod 555 sandbox/.sandbox_lock.tmp

    atf_check -s exit:1 -e match:"Failed to unlock sandbox" \
        sandboxctl -c custom.conf unmount

    atf_check -o inline:"mock_unmount $(pwd)/sandbox\n" \
        -e match:"destroying lock" \
        sandboxctl -c custom.conf unmount -f

    atf_check -s exit:1 -e match:"Sandbox not locked" \
        sandboxctl -c custom.conf unmount
}


atf_test_case unmount__force_force cleanup
unmount__force_force_head() {
    atf_set "require.user" "root"
}
unmount__force_force_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    mkdir sandbox
    mkdir sandbox/tmp

    atf_check -o inline:"mock_mount $(pwd)/sandbox\n" \
        sandboxctl -c custom.conf mount
    mount_tmpfs sandbox/tmp
    touch sandbox/tmp/cookie

    ( cd sandbox/tmp && sleep 300 ) &  # Keep the mount point busy.

    atf_check -s exit:1 -o inline:"mock_unmount $(pwd)/sandbox\n" \
        -e match:"Failed to unmount .*sandbox" \
        sandboxctl -c custom.conf unmount
    [ -f sandbox/tmp/cookie ] || atf_fail "File systems prematurely unmounted"

    atf_check -o inline:"mock_unmount $(pwd)/sandbox\n" \
        sandboxctl -c custom.conf unmount -f -f
    [ ! -f sandbox/tmp/cookie ] || atf_fail "File systems not unmounted"

    atf_check -s exit:1 -e match:"Sandbox not locked" \
        sandboxctl -c custom.conf unmount
}
unmount__force_force_cleanup() {
    umount sandbox/tmp >/dev/null 2>&1 || true
}


atf_test_case unmount__validate_config
unmount__validate_config_body() {
    test_validate_config unmount
}


atf_test_case unmount__fail_type
unmount__fail_type_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox" failing
    echo 'mock_unmount() { echo "mock_unmount ${*}"; exit 1; }' >>custom.conf
    echo 'pre_unmount_hook() { echo "custom pre_unmount_hook"; }' >>custom.conf

    mkdir sandbox
    atf_check -o ignore sandboxctl -c custom.conf mount

    cat >expout <<EOF
custom pre_unmount_hook
mock_unmount $(pwd)/sandbox
EOF
    atf_check -s exit:1 -o file:expout \
        -e inline:"sandboxctl: E: Failed to unmount sandbox type mock\n" \
        sandboxctl -c custom.conf unmount

    [ -d sandbox ] || atf_fail "Sandbox was cleaned up"
}


atf_test_case unmount__fail_hook
unmount__fail_hook_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    echo 'pre_unmount_hook() { echo "custom pre_unmount_hook"; exit 1; }' \
        >>custom.conf

    mkdir sandbox
    atf_check -o ignore sandboxctl -c custom.conf mount

    cat >expout <<EOF
custom pre_unmount_hook
EOF
    atf_check -s exit:1 -o file:expout \
        -e inline:"sandboxctl: E: The hook pre_unmount_hook returned an error\n" \
        sandboxctl -c custom.conf unmount

    [ -d sandbox ] || atf_fail "Sandbox was cleaned up"
}


atf_test_case unmount__unknown_flag
unmount__unknown_flag_body() {
    cat >experr <<EOF
sandboxctl: E: Unknown option -k in unmount
Type 'man sandboxctl' for help
EOF
    atf_check -s exit:1 -e file:experr sandboxctl -c /dev/null unmount -k
}


atf_test_case mount_unmount__nested
mount_unmount__nested_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"

    mkdir sandbox

    atf_check -o inline:"mock_mount $(pwd)/sandbox\n" \
        sandboxctl -c custom.conf mount

    atf_check sandboxctl -c custom.conf mount
    atf_check sandboxctl -c custom.conf mount

    cat >experr <<EOF
sandboxctl: W: Sandbox still in use by another process; file systems may still be mounted!
EOF
    atf_check -e file:experr sandboxctl -c custom.conf unmount
    atf_check -e file:experr sandboxctl -c custom.conf unmount

    atf_check -o inline:"mock_unmount $(pwd)/sandbox\n" \
        sandboxctl -c custom.conf unmount

    atf_check -s exit:1 -e match:"Sandbox not locked" \
        sandboxctl -c custom.conf unmount
}


atf_test_case run__ok
run__ok_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    create_mock_chroot

    mkdir sandbox
    touch sandbox/abc

    cat >expout <<EOF
mock_mount $(pwd)/sandbox
.
..
.sandbox_lock
abc
mock_unmount $(pwd)/sandbox
EOF
    atf_check -o file:expout sandboxctl -c custom.conf run /bin/ls -a1
}


atf_test_case run__clean_env
run__clean_env_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    create_mock_chroot

    mkdir sandbox

    atf_check \
        -o not-match:"ABC=" \
        -o match:"HOME=/tmp" \
        -o match:"SHELL=/bin/sh" \
        -o match:"TERM=${TERM}" \
        -o not-match:"Z=" \
        env ABC=foo HOME=/foo/bar SHELL=/bin/thesh Z=bar \
        sandboxctl -c custom.conf run /bin/sh -c env
}


atf_test_case run__shell_is_sh
run__shell_is_sh_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    create_mock_chroot

    mkdir sandbox

    cat >expout <<EOF
mock_mount $(pwd)/sandbox
/bin/sh
mock_unmount $(pwd)/sandbox
EOF
    atf_check -o file:expout sandboxctl -c custom.conf run \
        /bin/sh -c 'echo "${SHELL}"'
}


atf_test_case run__command_fails
run__command_fails_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    create_mock_chroot

    mkdir sandbox
    cat >sandbox/fail.sh <<EOF
#! /bin/sh
echo "Failing"
exit 15
EOF
    chmod +x sandbox/fail.sh

    cat >expout <<EOF
mock_mount $(pwd)/sandbox
Failing
mock_unmount $(pwd)/sandbox
EOF
    atf_check -s exit:15 -o file:expout sandboxctl -c custom.conf run ./fail.sh
}


atf_test_case run__validate_config
run__validate_config_body() {
    test_validate_config run foo
}


atf_test_case run__unmount_after_signals
run__unmount_after_signals_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    create_mock_chroot

    mkdir sandbox
    cat >sandbox/wait.sh <<EOF
#! /bin/sh
echo "Waiting for signal"
touch cookie
while [ -e cookie ]; do
    sleep .1
done
EOF
    chmod +x sandbox/wait.sh

    for signal in HUP INT TERM; do
        rm -f sandbox/cookie out err

        echo "Testing handling of ${signal} signal"
        sandboxctl -c custom.conf run ./wait.sh >out 2>err &
        local pid="${!}"

        while [ ! -e sandbox/cookie ]; do
            echo "sandbox/cookie not found; waiting for sandbox to come up"
            sleep .1
        done

        echo "Sending ${signal} to sandboxctl PID ${pid}"
        kill "-${signal}" "${pid}"
        rm sandbox/cookie
        wait "${pid}"

        cat >expout <<EOF
mock_mount $(pwd)/sandbox
Waiting for signal
mock_unmount $(pwd)/sandbox
EOF
        atf_check -o file:expout cat out
    done
}


atf_test_case shell__ok
shell__ok_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    create_mock_chroot

    mkdir sandbox
    touch sandbox/abc

    cat >expout <<EOF
mock_mount $(pwd)/sandbox
123
mock_unmount $(pwd)/sandbox
EOF
    echo 'echo 123' | atf_check -o file:expout sandboxctl -c custom.conf shell
}


atf_test_case shell__clean_env
shell__clean_env_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    create_mock_chroot

    mkdir sandbox

    echo env | atf_check \
        -o not-match:"ABC=" \
        -o match:"HOME=/tmp" \
        -o match:"SHELL=/bin/sh" \
        -o match:"TERM=${TERM}" \
        -o not-match:"Z=" \
        env ABC=foo HOME=/foo/bar SHELL=/bin/thesh Z=bar \
        sandboxctl -c custom.conf shell
}


atf_test_case shell__shell_is_sh
shell__shell_is_sh_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    create_mock_chroot

    mkdir sandbox

    cat >expout <<EOF
mock_mount $(pwd)/sandbox
/bin/sh
mock_unmount $(pwd)/sandbox
EOF
    echo 'echo "${SHELL}"' \
        | atf_check -o file:expout sandboxctl -c custom.conf shell
}


atf_test_case shell__fail
shell__fail_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    create_mock_chroot

    mkdir sandbox
    touch sandbox/abc

    cat >expout <<EOF
mock_mount $(pwd)/sandbox
Will fail
mock_unmount $(pwd)/sandbox
EOF
    echo 'echo Will fail; exit 23' \
        | atf_check -s exit:23 -o file:expout sandboxctl -c custom.conf shell
}


atf_test_case shell__validate_config
shell__validate_config_body() {
    test_validate_config shell
}


atf_test_case shell__unmount_after_signals
shell__unmount_after_signals_body() {
    create_config_with_mock_type custom.conf "$(pwd)/sandbox"
    create_mock_chroot

    mkdir sandbox

    for signal in HUP INT TERM; do
        rm -f sandbox/cookie out err

        echo "Testing handling of ${signal} signal"
        echo 'echo "Waiting for signal"; touch cookie;' \
             'while [ -e cookie ]; do sleep .1; done' \
            | sandboxctl -c custom.conf shell >out 2>err &
        local pid="${!}"

        while [ ! -e sandbox/cookie ]; do
            echo "sandbox/cookie not found; waiting for sandbox to come up"
            sleep .1
        done

        echo "Sending ${signal} to sandboxctl PID ${pid}"
        kill "-${signal}" "${pid}"
        rm sandbox/cookie
        wait "${pid}"

        cat >expout <<EOF
mock_mount $(pwd)/sandbox
Waiting for signal
mock_unmount $(pwd)/sandbox
EOF
        atf_check -o file:expout cat out
    done
}


atf_test_case no_command
no_command_body() {
    cat >experr <<EOF
sandboxctl: E: No command specified
Type 'man sandboxctl' for help
EOF
    atf_check -s exit:1 -e file:experr sandboxctl
}


atf_test_case unknown_command
unknown_command_body() {
    cat >experr <<EOF
sandboxctl: E: Unknown command foo
Type 'man sandboxctl' for help
EOF
    atf_check -s exit:1 -e file:experr sandboxctl foo
}


atf_test_case unknown_flag
unknown_flag_body() {
    cat >experr <<EOF
sandboxctl: E: Unknown option -Z
Type 'man sandboxctl' for help
EOF
    atf_check -s exit:1 -e file:experr sandboxctl -Z
}


atf_init_test_cases() {
    atf_add_test_case config__builtins__no_modules
    atf_add_test_case config__builtins__some_modules
    atf_add_test_case config__path__components
    atf_add_test_case config__path__extension
    atf_add_test_case config__name__system_directory
    atf_add_test_case config__name__not_found
    atf_add_test_case config__overrides
    atf_add_test_case config__one_variable
    atf_add_test_case config__too_many_args

    atf_add_test_case create__ok
    atf_add_test_case create__hooks
    atf_add_test_case create__already_exists
    atf_add_test_case create__validate_config
    atf_add_test_case create__fail_mkdir
    atf_add_test_case create__fail_bad_type
    atf_add_test_case create__fail_in_type
    atf_add_test_case create__fail_hook

    atf_add_test_case destroy__ok
    atf_add_test_case destroy__hooks
    atf_add_test_case destroy__non_existent
    atf_add_test_case destroy__still_mounted
    atf_add_test_case destroy__validate_config
    atf_add_test_case destroy__fail_type
    atf_add_test_case destroy__fail_hook

    atf_add_test_case mount__ok
    atf_add_test_case mount__hooks
    atf_add_test_case mount__non_existent
    atf_add_test_case mount__already_mounted
    atf_add_test_case mount__validate_config
    atf_add_test_case mount__fail_type
    atf_add_test_case mount__fail_hook

    atf_add_test_case unmount__ok
    atf_add_test_case unmount__hooks
    atf_add_test_case unmount__not_mounted
    atf_add_test_case unmount__force
    atf_add_test_case unmount__force_force
    atf_add_test_case unmount__validate_config
    atf_add_test_case unmount__fail_type
    atf_add_test_case unmount__fail_hook
    atf_add_test_case unmount__unknown_flag

    atf_add_test_case mount_unmount__nested

    atf_add_test_case run__ok
    atf_add_test_case run__clean_env
    atf_add_test_case run__shell_is_sh
    atf_add_test_case run__command_fails
    atf_add_test_case run__validate_config
    atf_add_test_case run__unmount_after_signals

    atf_add_test_case shell__ok
    atf_add_test_case shell__clean_env
    atf_add_test_case shell__shell_is_sh
    atf_add_test_case shell__fail
    atf_add_test_case shell__validate_config
    atf_add_test_case shell__unmount_after_signals

    atf_add_test_case no_command
    atf_add_test_case unknown_command
    atf_add_test_case unknown_flag
}

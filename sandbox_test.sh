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

shtk_import sandbox
_SANDBOX_BINDFS_EXTRA_OPTS=,direct_io


# Creates fake sandbox types and loads them.
#
# The fake1 sandbox type has three functions (action1, action2 and action3) to
# be called with sandbox_call_types.  action1 and action2 return success while
# action3 returns an error.  The main dispatcher of the sandbox type returns
# success.
#
# The fake2 sandbox type is the same as the fake1 type but the dispatcher raises
# an error.
setup_fake_types() {
    mkdir modules
    cat >>modules/fake1.subr <<EOF
fake1_action1() { echo "fake1_action1: \${*}"; }
fake1_action2() { echo "fake1_action2: \${*}"; }
fake1_action3() { echo "fake1_action3: \${*}"; false; }

_fake1_common() {
    local command="\${1}"; shift
    echo "fake1 handler \${command}: \${*}"
}

fake1_create() { _fake1_common create "\${@}"; }
fake1_destroy() { _fake1_common destroy "\${@}"; }
fake1_mount() { _fake1_common mount "\${@}"; }
fake1_unmount() { _fake1_common unmount "\${@}"; }
EOF
    cat >>modules/fake2.subr <<EOF
shtk_import cli

fake2_action1() { echo "fake2_action1: \${*}"; }
fake2_action2() { echo "fake2_action2: \${*}"; }
fake2_action3() { echo "fake2_action3: \${*}"; false; }

_fake2_common() {
    local command="\${1}"; shift
    echo "fake2 handler \${command}: \${*}"
    shtk_cli_error "handler failure"
}

fake2_create() { _fake2_common create "\${@}"; }
fake2_destroy() { _fake2_common destroy "\${@}"; }
fake2_mount() { _fake2_common mount "\${@}"; }
fake2_unmount() { _fake2_common unmount "\${@}"; }
EOF
    sandbox_load_types modules
}


atf_test_case load_types__none__no_dir
load_types__none__no_dir_body() {
    sandbox_load_types modules
}


atf_test_case load_types__none__empty_dir
load_types__none__empty_dir_body() {
    mkdir modules
    sandbox_load_types modules
}


atf_test_case load_types__ok
load_types__ok_body() {
    mkdir modules
    echo "fake1() { true; }" >modules/fake1.subr
    echo "fake2() { true; }" >modules/fake2.subr
    echo "fake3() { true; }" >modules/fake3.foo
    sandbox_load_types modules

    fake1 || atf_fail "fake1 not loaded"
    fake2 || atf_fail "fake2 not loaded"
    if fake3; then
        atf_fail "fake3 loaded but it should not have been"
    fi
}


atf_test_case load_types__default_hooks
load_types__default_hooks_body() {
    mkdir modules
    echo "true" >modules/fake1.subr
    sandbox_load_types modules
    for hook in fake1_config_vars fake1_set_defaults \
                fake1_create fake1_destroy fake1_mount fake1_unmount; do
        if ! "${hook}" >out; then
            atf_fail "Default unimplemented ${hook} failed"
        fi
        atf_check -o empty cat out
    done
}


atf_test_case load_types__error
load_types__error_body() {
    mkdir modules
    echo "fake1() { true; }" >modules/fake1.subr
    echo "invalid file" >modules/fake2.subr
    echo "fake3() { true; }" >modules/fake3.subr
    if ( sandbox_load_types modules ); then
        atf_fail "sandbox_load_types should have failed"
    fi
}


atf_test_case call_types__ok
call_types__ok_body() {
    setup_fake_types

    sandbox_call_types action1 arg1 arg2 >output
    cat >expout <<EOF
fake1_action1: arg1 arg2
fake2_action1: arg1 arg2
EOF
    atf_check -o file:expout cat output

    sandbox_call_types action2 arg1 arg2 >output
    cat >expout <<EOF
fake1_action2: arg1 arg2
fake2_action2: arg1 arg2
EOF
    atf_check -o file:expout cat output
}


atf_test_case call_types__error
call_types__error_body() {
    setup_fake_types

    if ( sandbox_call_types action3 arg1 >output 2>error ); then
        atf_fail "sandbox_call_types succeeded but it should have failed"
    fi
    atf_check -o inline:"fake1_action3: arg1\n" cat output
    atf_check -o match:"E:.*action3 on fake1 failed" cat error
}


atf_test_case dispatch__type__ok
dispatch__type__ok_body() {
    setup_fake_types
    for action in create mount unmount destroy; do
        sandbox_dispatch fake1 "the/sandbox" "${action}" >out 2>err
        atf_check -o inline:"fake1 handler ${action}: the/sandbox\n" cat out
        [ ! -s err ] || atf_fail "Error messages should not have been printed"
    done
}


atf_test_case dispatch__type__error
dispatch__type__error_body() {
    setup_fake_types
    for action in create mount unmount destroy; do
        if ( sandbox_dispatch fake2 "the/sandbox" "${action}" >out 2>err ); then
            atf_fail "Handler failed but error was not captured"
        fi
        atf_check -o inline:"fake2 handler ${action}: the/sandbox\n" cat out
        atf_check -o match:"Failed to ${action} sandbox type fake2" cat err
    done
}


atf_test_case dispatch__unknown_type
dispatch__unknown_type_body() {
    setup_fake_types
    if ( sandbox_dispatch fake3 "the/sandbox" create >out 2>err ); then
        atf_fail "Dispatch on unknown type worked but should not have"
    fi
    atf_check -o match:"Invalid sandbox type 'fake3'" cat err
}


atf_test_case dispatch__unknown_action
dispatch__unknown_action_body() {
    if ( sandbox_dispatch empty the/directory foobar ) 2>err
    then
        atf_fail "Invalid action was not captured"
    fi
    atf_check -o match:'unknown action foobar' cat err
}


atf_test_case enter_leave__once
enter_leave__once_body() {
    local root="$(pwd)/sandbox"
    mkdir -p "${root}"

    sandbox_enter "${root}" || atf_fail "enter did not lock sandbox"
    [ -f "${root}/.sandbox_lock" ] || atf_fail "Lock file not created"
    sandbox_leave "${root}" || atf_fail "leave did not unlock sandbox"
    [ ! -f "${root}/.sandbox_lock" ] || atf_fail "Lock file not deleted"
}


atf_test_case enter_leave__nested
enter_leave__nested_body() {
    local root="$(pwd)/sandbox"
    mkdir -p "${root}"

    sandbox_enter "${root}" || atf_fail "enter did not lock sandbox"

    if sandbox_enter "${root}"; then
        atf_fail "enter relocked already-in-use sandbox"
    fi
    if sandbox_leave "${root}"; then
        atf_fail "leave unlocked still-in-use sandbox"
    fi

    if sandbox_enter "${root}"; then
        atf_fail "enter relocked already-in-use sandbox"

        if sandbox_enter "${root}"; then
            atf_fail "enter relocked already-in-use sandbox"
        fi
        if sandbox_leave "${root}"; then
            atf_fail "leave unlocked still-in-use sandbox"
        fi
    fi
    if sandbox_leave "${root}"; then
        atf_fail "leave unlocked still-in-use sandbox"
    fi

    sandbox_leave "${root}" || atf_fail "leave did not unlock sandbox"
    [ ! -f "${root}/.sandbox_lock" ] || atf_fail "Lock file not deleted"
}


atf_test_case enter__error
enter__error_body() {
    local root="$(pwd)/sandbox"

    if ( sandbox_enter "${root}" ) 2>err; then
        atf_fail "sandbox_enter did not raise an error"
    fi
    atf_check -o match:'E: Failed to lock sandbox' cat err
    [ ! -f "${root}/.sandbox_lock" ] || atf_fail "Lock file created"
}


atf_test_case leave__error
leave__error_head() {
    atf_set "require.user" "unprivileged"
}
leave__error_body() {
    local root="$(pwd)/sandbox"
    mkdir -p "${root}"
    sandbox_enter "${root}"
    chmod 555 "${root}"

    if ( sandbox_leave "${root}" ) 2>err; then
        chmod 755 "${root}"
        atf_fail "sandbox_leave did not raise an error"
    fi
    chmod 755 "${root}"
    atf_check -o match:'E: Failed to unlock sandbox' cat err
    [ -f "${root}/.sandbox_lock" ] || atf_fail "Lock file deleted"
}


atf_test_case leave__not_entered
leave__not_entered_body() {
    local root="$(pwd)/sandbox"
    mkdir -p "${root}"

    if ( sandbox_leave "${root}" ) 2>err; then
        atf_fail "sandbox_leave did not raise an error"
    fi
    atf_check -o match:'E: Sandbox not locked' cat err
    [ ! -f "${root}/.sandbox_lock" ] || atf_fail "Lock file created"
}


atf_test_case has_mounts__no cleanup
has_mounts__no_head() {
    atf_set "require.user" "root"
}
has_mounts__no_body() {
    mkdir -p sandbox/tmp
    mkdir -p sandbox2/tmp
    mount_tmpfs sandbox2/tmp
    if sandbox_has_mounts sandbox; then
        atf_fail "sandbox_has_mount should have returned false"
    fi
}
has_mounts__no_cleanup() {
    umount sandbox2/tmp >/dev/null 2>&1 || true
}


atf_test_case has_mounts__yes cleanup
has_mounts__yes_head() {
    atf_set "require.user" "root"
}
has_mounts__yes_body() {
    mkdir -p sandbox/tmp
    mount_tmpfs sandbox/tmp

    sandbox_has_mounts sandbox || atf_fail "sandbox_has_mount should have" \
        "returned true"
}
has_mounts__yes_cleanup() {
    umount sandbox/tmp >/dev/null 2>&1 || true
}


atf_test_case has_mounts__yes_indirect cleanup
has_mounts__yes_indirect_head() {
    atf_set "require.user" "root"
}
has_mounts__yes_indirect_body() {
    mkdir -p sandbox/tmp
    ln -s sandbox other
    mount_tmpfs other/tmp

    sandbox_has_mounts other || atf_fail "sandbox_has_mount should have" \
        "returned true"
}
has_mounts__yes_indirect_cleanup() {
    umount other/tmp >/dev/null 2>&1 || true
    umount sandbox/tmp >/dev/null 2>&1 || true
}


atf_test_case unmount_dirs__ok cleanup
unmount_dirs__ok_head() {
    atf_set "require.user" "root"
}
unmount_dirs__ok_body() {
    for dir in sandbox/first/dir sandbox/second/nested/dir sandbox2/tmp; do
        echo "${dir}" >>dirs
        mkdir -p "${dir}"
        mount_tmpfs "${dir}"
        touch "${dir}/cookie"
    done

    sandbox_unmount_dirs sandbox || atf_fail "Failed to unmount sandbox"
    if [ -n "$(find sandbox -name cookie)" ]; then
        atf_fail "File systems seem to be left mounted"
    fi

    [ -f sandbox2/tmp/cookie ] || atf_fail "File systems outside of the" \
        "sandbox were unmounted"
}
unmount_dirs__ok_cleanup() {
    for dir in $(cat dirs); do
        umount "${dir}" >/dev/null 2>&1 || true
    done
}


atf_test_case unmount_dirs__ok_indirect cleanup
unmount_dirs__ok_indirect_head() {
    atf_set "require.user" "root"
}
unmount_dirs__ok_indirect_body() {
    mkdir -p sandbox/first/dir
    ln -s sandbox other
    mount_tmpfs other/first/dir
    touch other/first/dir/cookie

    sandbox_unmount_dirs other || atf_fail "Failed to unmount sandbox"
    if [ -n "$(find other/first -name cookie)" ]; then
        atf_fail "File systems seem to be left mounted"
    fi
}
unmount_dirs__ok_indirect_cleanup() {
    umount sandbox/first/dir >/dev/null 2>&1 || true
    umount other/first/dir >/dev/null 2>&1 || true
}


atf_test_case unmount_dirs__error cleanup
unmount_dirs__error_head() {
    atf_set "require.user" "root"
}
unmount_dirs__error_body() {
    mkdir -p sandbox/mnt
    mount_tmpfs sandbox/mnt

    cd sandbox/mnt
    sleep 600 &
    local pid="${!}"
    cd -
    echo "${pid}" >pid

    if ( sandbox_unmount_dirs sandbox 2>err ); then
        atf_fail "sandbox_unmount_dirs did not raise an error"
    fi
    kill -9 "${pid}"
    wait "${pid}"
    sandbox_unmount_dirs sandbox || atf_fail "Failed to unmount sandbox"
}
unmount_dirs__error_cleanup() {
    kill -9 "$(cat pid)" 2>&1 || true
    umount sandbox/mnt >/dev/null 2>&1 || true
}


atf_test_case destroy__ok
destroy__ok_body() {
    mkdir -p sandbox/tmp
    touch sandbox/tmp/foo
    chmod 555 sandbox/tmp

    sandbox_destroy sandbox || atf_fail "sandbox_destroy failed"
    [ ! -d sandbox ] || atf_fail "sandbox not deleted"
}


atf_test_case destroy__abort_if_still_mounted cleanup
destroy__abort_if_still_mounted_head() {
    atf_set "require.user" "root"
}
destroy__abort_if_still_mounted_body() {
    cat >script.sh <<EOF
#! /bin/sh
shtk_import sandbox
main() {
    chmod() { touch chmod-called; }
    rm() { touch rm-called; }
    sandbox_destroy "\${1}"
}
EOF
    atf_check __SHTK__ build -o script script.sh

    mkdir -p sandbox/tmp
    mount_tmpfs sandbox/tmp
    atf_check -s signal \
        -e match:"script: A: Attempting to delete an still-mounted sandbox" \
        ./script sandbox
    [ ! -f chmod-called ] || fail "chmod called; did not abort"
    [ ! -f rm-called ] || fail "rm called; did not abort"
}
destroy__abort_if_still_mounted_cleanup() {
    umount sandbox/tmp >/dev/null 2>&1 || true
}


atf_test_case destroy__abort_if_root
destroy__abort_if_root_body() {
    cat >script.sh <<EOF
#! /bin/sh
shtk_import sandbox
main() {
    chmod() { touch chmod-called; }
    rm() { touch rm-called; }
    sandbox_destroy "\${1}"
}
EOF
    atf_check __SHTK__ build -o script script.sh

    for candidate in / /bin/.. ///; do
        echo "Testing sandbox_destroy with a root of ${candidate}"

        rm *-called 2>/dev/null || true
        atf_check -s signal \
            -e match:"script: A: Attempting to delete /" ./script "${candidate}"
        [ ! -f chmod-called ] || fail "chmod called; did not abort"
        [ ! -f rm-called ] || fail "rm called; did not abort"
    done
}


# Creates a test tarball with some files in it.
#
# \param tgz Path to the tarball to be created.
create_test_tgz() {
    local tgz="${1}"; shift

    mkdir dir1 dir2
    touch dir1/file1 dir1/file2 dir2/file1

    mkdir -p "$(dirname "${tgz}")"
    tar -czf "${tgz}" dir1 dir2

    rm -rf dir1 dir2
}


atf_test_case extract__all__not_verbose
extract__all__not_verbose_body() {
    create_test_tgz dist/test.tgz

    mkdir destdir
    sandbox_extract dist/test.tgz destdir
    [ -f destdir/dir1/file1 ] || atf_fail "File missing after extraction"
    [ -f destdir/dir1/file2 ] || atf_fail "File missing after extraction"
    [ -f destdir/dir2/file1 ] || atf_fail "File missing after extraction"
}


atf_test_case extract__all__verbose
extract__all__verbose_body() {
    shtk_cli_set_log_level debug
    extract__all__not_verbose_body
}


atf_test_case extract__some__not_verbose
extract__some__not_verbose_body() {
    create_test_tgz dist/test.tgz

    mkdir destdir
    sandbox_extract dist/test.tgz "$(pwd)/destdir" dir1/file2 dir2
    [ ! -f destdir/dir1/file1 ] || atf_fail "Unexpected file extracted"
    [ -f destdir/dir1/file2 ] || atf_fail "File missing after extraction"
    [ -f destdir/dir2/file1 ] || atf_fail "File missing after extraction"
}


atf_test_case extract__some__verbose
extract__some__verbose_body() {
    shtk_cli_set_log_level debug
    extract__some__not_verbose_body
}


atf_test_case extract__error__not_verbose
extract__error__not_verbose_body() {
    create_test_tgz dist/test.tgz

    if ( sandbox_extract dist/test.tgz destdir ) 2>err; then
        atf_fail "sandbox_extract did not raise an error"
    fi
    atf_check -o match:'E: Extraction of dist/test.tgz failed' cat err
    [ ! -d destdir ] || atf_fail "destdir unexpectedly created"
}


atf_test_case extract__error__verbose
extract__error__verbose_body() {
    shtk_cli_set_log_level debug
    extract__error__not_verbose_body
}


atf_test_case extract__bad_args
extract__bad_args_body() {
    if ( sandbox_extract foo 2>err ); then
        atf_fail "sandbox_extract did not raise an error"
    fi
    atf_check -o match:'E: sandbox_extract: syntax error' cat err
}


atf_test_case bindfs__ok__default_ro cleanup
bindfs__ok__default_ro_head() {
    atf_set "require.user" "root"
}
bindfs__ok__default_ro_body() {
    shtk_abort() { atf_skip "${@}"; }

    mkdir real
    echo first >real/file

    mkdir -p sandbox/mnt
    sandbox_bindfs "${@}" real sandbox/mnt || atf_fail "Failed to mount bindfs"

    if echo second >sandbox/mnt/file; then
        atf_fail "bindfs did not default to read-only mode"
    fi
    atf_check -o inline:'first\n' cat real/file
    atf_check -o inline:'first\n' cat sandbox/mnt/file
    echo third >real/file
    atf_check -o inline:'third\n' cat real/file
    atf_check -o inline:'third\n' cat sandbox/mnt/file
}
bindfs__ok__default_ro_cleanup() {
    umount sandbox/mnt >/dev/null 2>&1 || true
}


atf_test_case bindfs__ok__ro_mode cleanup
bindfs__ok__ro_mode_head() {
    bindfs__ok__default_ro_head
}
bindfs__ok__ro_mode_body() {
    bindfs__ok__default_ro_body -o ro
}
bindfs__ok__ro_mode_cleanup() {
    bindfs__ok__default_ro_cleanup
}


atf_test_case bindfs__ok__rw_mode cleanup
bindfs__ok__rw_mode_head() {
    atf_set "require.user" "root"
}
bindfs__ok__rw_mode_body() {
    shtk_abort() { atf_skip "${@}"; }

    mkdir real
    echo first >real/file

    mkdir -p sandbox/mnt
    sandbox_bindfs -o rw real sandbox/mnt || atf_fail "Failed to mount bindfs"

    echo second >sandbox/mnt/file || atf_fail "bindfs not in read-write mode"
    atf_check -o inline:'second\n' cat real/file
    atf_check -o inline:'second\n' cat sandbox/mnt/file
    echo third >real/file
    atf_check -o inline:'third\n' cat real/file
    atf_check -o inline:'third\n' cat sandbox/mnt/file
}
bindfs__ok__rw_mode_cleanup() {
    umount sandbox/mnt >/dev/null 2>&1 || true
}


atf_test_case bindfs__mount_fails cleanup
bindfs__mount_fails_head() {
    atf_set "require.user" "root"
}
bindfs__mount_fails_body() {
    shtk_abort() { atf_skip "${@}"; }

    mkdir real
    if ( sandbox_bindfs -o rw real sandbox/mnt 2>err ); then
        atf_fail "sandbox_bindfs did not raise an error"
    fi
    atf_check -o match:'E: Failed to bind sandbox/mnt' cat err
}
bindfs__mount_fails_cleanup() {
    umount sandbox/mnt >/dev/null 2>&1 || true
}


atf_test_case bindfs__invalid_option
bindfs__invalid_option_body() {
    if ( sandbox_bindfs -o rww bar 2>err ); then
        atf_fail "sandbox_bindfs did not raise an error"
    fi
    atf_check -o match:'E: Unsupported mount option rww' cat err
}


atf_test_case bindfs__unknown_flag
bindfs__unknown_flag_body() {
    if ( sandbox_bindfs -k foo bar 2>err ); then
        atf_fail "sandbox_bindfs did not raise an error"
    fi
    atf_check -o match:'E: Unknown option -k' cat err
}


atf_test_case bindfs__bad_args
bindfs__bad_args_body() {
    if ( sandbox_bindfs foo 2>err ); then
        atf_fail "sandbox_bindfs did not raise an error"
    fi
    atf_check -o match:'E: sandbox_bindfs: syntax error' cat err

    if ( sandbox_bindfs foo bar baz 2>err ); then
        atf_fail "sandbox_bindfs did not raise an error"
    fi
    atf_check -o match:'E: sandbox_bindfs: syntax error' cat err
}


atf_init_test_cases() {
    shtk_cli_set_log_level debug

    atf_add_test_case load_types__none__no_dir
    atf_add_test_case load_types__none__empty_dir
    atf_add_test_case load_types__ok
    atf_add_test_case load_types__default_hooks
    atf_add_test_case load_types__error

    atf_add_test_case call_types__ok
    atf_add_test_case call_types__error

    atf_add_test_case dispatch__type__ok
    atf_add_test_case dispatch__type__error
    atf_add_test_case dispatch__unknown_type
    atf_add_test_case dispatch__unknown_action

    atf_add_test_case enter_leave__once
    atf_add_test_case enter_leave__nested

    atf_add_test_case enter__error

    atf_add_test_case leave__error
    atf_add_test_case leave__not_entered

    atf_add_test_case has_mounts__no
    atf_add_test_case has_mounts__yes
    atf_add_test_case has_mounts__yes_indirect

    atf_add_test_case unmount_dirs__ok
    atf_add_test_case unmount_dirs__ok_indirect
    atf_add_test_case unmount_dirs__error

    atf_add_test_case destroy__ok
    atf_add_test_case destroy__abort_if_still_mounted
    atf_add_test_case destroy__abort_if_root

    atf_add_test_case extract__all__not_verbose
    atf_add_test_case extract__all__verbose
    atf_add_test_case extract__some__not_verbose
    atf_add_test_case extract__some__verbose
    atf_add_test_case extract__error__not_verbose
    atf_add_test_case extract__error__verbose
    atf_add_test_case extract__bad_args

    atf_add_test_case bindfs__ok__default_ro
    atf_add_test_case bindfs__ok__ro_mode
    atf_add_test_case bindfs__ok__rw_mode
    atf_add_test_case bindfs__mount_fails
    atf_add_test_case bindfs__invalid_option
    atf_add_test_case bindfs__unknown_flag
    atf_add_test_case bindfs__bad_args
}

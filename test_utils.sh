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

# \file test_utils.sh
# Miscellaneous test-only utilities.

: ${SANDBOXCTL_SHTK_MODULESDIR:="__SANDBOXCTL_SHTK_MODULESDIR__"}
SHTK_MODULESPATH="${SANDBOXCTL_SHTK_MODULESDIR}" shtk_import sandbox
_SANDBOX_BINDFS_EXTRA_OPTS=,direct_io


# Isolate the sandbox type under test so that sandboxctl only sees that one.
#
# \post SANDBOXCTL_MODULESDIR is modified to point to the temporary directory
# and is exported so that invocations of sandboxctl can use the new value.
isolate_module() {
    local module="${1}"; shift

    mkdir modules
    ln -s "${SANDBOXCTL_MODULESDIR}/${module}.subr" modules/
    SANDBOXCTL_MODULESDIR="$(pwd)/modules"; export SANDBOXCTL_MODULESDIR
}


# Mounts a tmpfs file system for testing purposes.
#
# \param mount_point Directory in which to mount the tmpfs file system.
mount_tmpfs() {
    local mount_point="${1}"; shift

    case "$(uname -s)" in
        Darwin)
            # Assume sandbox_bindfs works properly for simplicity here.
            # If not, we'll get all kinds of failures and we'll also get the
            # unit tests for sandbox_bindfs to fail, which will help in
            # understanding the problem.
            local tmpdir="$(mktemp -d -t fake_tmpfs)"
            sandbox_bindfs -o rw "${tmpdir}" "${mount_point}"
            ;;

        FreeBSD|Linux|NetBSD)
            mount -t tmpfs tmpfs "${mount_point}" \
                || atf_fail "Failed to mount a tmpfs file system"
            ;;

        *)
            atf_skip "Don't know how to mount a tmpfs file system"
            ;;
    esac
}

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

# \file sandboxctl.sh
# Manages sandboxes under various operating systems.

shtk_import cli
shtk_import config
shtk_import sandbox


# Location of the sandboxctl configuration files.
: ${SANDBOXCTL_ETCDIR:="__SANDBOXCTL_ETCDIR__"}


# Location of the sandboxctl modules.
: ${SANDBOXCTL_MODULESDIR:="__SANDBOXCTL_MODULESDIR__"}


# List of valid configuration variables.
#
# Please remember to update sandboxctl.conf(5) if you change this list.
SANDBOXCTL_CONFIG_VARS="SANDBOX_ROOT SANDBOX_TYPE"


# Sets defaults for configuration variables and hooks that need to exist.
#
# This function should be called before the configuration file has been loaded.
# This means that the user can undefine a required configuration variable, but
# we let him shoot himself in the foot if he so desires.
sandboxctl_set_defaults() {
    # Remember to update sandboxctl.conf(5) if you change any default values.
    shtk_config_set SANDBOX_TYPE "empty"
    sandbox_call_types set_defaults

    post_create_hook() { true; }
    pre_destroy_hook() { true; }
    post_mount_hook() { true; }
    pre_unmount_hook() { true; }
}


# Dumps the loaded configuration.
#
# \param ... The options and arguments to the command.
sandboxctl_config() {
    [ ${#} -eq 0 ] || shtk_cli_usage_error "config does not take any arguments"

    local all_vars="${SANDBOXCTL_CONFIG_VARS} $(sandbox_call_types config_vars)"
    local sorted_vars="$(for var in ${all_vars}; do \
                             echo "${var}"; \
                         done | sort | uniq)"
    for var in ${sorted_vars}; do
        if shtk_config_has "${var}"; then
            echo "${var} = $(shtk_config_get "${var}")"
        else
            echo "${var} is undefined"
        fi
    done
}


# Creates the sandbox.
sandboxctl_create() {
    [ ${#} -eq 0 ] || shtk_cli_usage_error "create does not take any arguments"

    local type
    type="$(shtk_config_get SANDBOX_TYPE)" || exit
    local root
    root="$(shtk_config_get SANDBOX_ROOT)" || exit

    [ ! -e "${root}" ] || shtk_cli_error "Sandbox ${root} already exists"
    mkdir "${root}" || shtk_cli_error "Failed to create sandbox root"
    if ! ( sandbox_dispatch "${type}" "${root}" create ); then
        ( sandboxctl_destroy ) || true
        # Cope with the case where the sandbox type was bad: our
        # sandbox_dispatch couldn't do a thing, but sandboxctl_destroy could not
        # run either.  Simply remove the just-created directory.
        rmdir "${root}" 2>/dev/null || true
        return 1
    fi
    if ! ( shtk_config_run_hook post_create_hook ); then
        sandboxctl_destroy || true
        return 1
    fi
}


# Destroys the sandbox.
#
# This does not attempt to unmount the sandbox if still mounted, and will abort
# loudly if it is.
sandboxctl_destroy() {
    [ ${#} -eq 0 ] || shtk_cli_usage_error "destroy does not take any arguments"

    local type
    type="$(shtk_config_get SANDBOX_TYPE)" || exit
    local root
    root="$(shtk_config_get SANDBOX_ROOT)" || exit

    [ -d "${root}" ] || shtk_cli_error "Cannot destroy a non-existent sandbox"

    ! sandbox_has_mounts "${root}" || shtk_cli_error "File systems appear to" \
        "still be mounted; refusing to destroy"

    shtk_config_run_hook pre_destroy_hook
    sandbox_dispatch "${type}" "${root}" destroy

    sandbox_destroy "${root}"
}


# Mounts the sandbox.
#
# The sandbox must have been created first with the 'create' command.  Running
# multiple mount operations from different clients is reasonably safe as we
# record how many clients have called this.
sandboxctl_mount() {
    [ ${#} -eq 0 ] || shtk_cli_usage_error "mount does not take any arguments"

    local type
    type="$(shtk_config_get SANDBOX_TYPE)" || exit
    local root
    root="$(shtk_config_get SANDBOX_ROOT)" || exit

    [ -d "${root}" ] || shtk_cli_error "Cannot mount a non-existent sandbox"

    if sandbox_enter "${root}"; then
        if sandbox_has_mounts "${root}"; then
            sandbox_leave "${root}"
            shtk_cli_error "Sandbox in inconsistent state; mounts found but" \
                           "is not locked"
        fi

        local ret=0
        (
            sandbox_dispatch "${type}" "${root}" mount
            shtk_config_run_hook post_mount_hook
        ) || ret=${?}
        if [ ${ret} -ne 0 ]; then
            sandboxctl_unmount
            exit ${ret}
        fi
    fi
}


# Unmounts the sandbox.
#
# The sandbox must exist.  Running multiple unmount operations from different
# clients is reasonably safe as we have recorded how many clients did so.
sandboxctl_unmount() {
    local force_leave=
    local force_unmount=
    local OPTIND
    while getopts ':f' arg "${@}"; do
        case "${arg}" in
            f)  # Force leave if given once; force unmount if given twice.
                if [ -n "${force_leave}" ]; then
                    force_unmount=-f
                else
                    force_leave=-f
                fi
                ;;

            \?)
                shtk_cli_usage_error "Unknown option -${OPTARG} in unmount"
                ;;
        esac
    done
    shift $((${OPTIND} - 1))
    OPTIND=1  # Should not be necessary due to the 'local' above.

    [ ${#} -eq 0 ] || shtk_cli_usage_error "unmount does not take any arguments"

    local type
    type="$(shtk_config_get SANDBOX_TYPE)" || exit
    local root
    root="$(shtk_config_get SANDBOX_ROOT)" || exit

    [ -d "${root}" ] || shtk_cli_error "Cannot unmount a non-existent sandbox"

    if sandbox_leave ${force_leave} "${root}"; then
        shtk_config_run_hook pre_unmount_hook
        sandbox_dispatch "${type}" "${root}" unmount
        sandbox_unmount_dirs ${force_unmount} "${root}"
    else
        shtk_cli_warning "Sandbox still in use by another process; file" \
            "systems may still be mounted!"
    fi
}


# Runs the given command inside the sandbox.
#
# \param binary Path to the binary to run, relative to the sandbox.
# \param ... Additional arguments to the binary.
#
# \return The exit status of the executed command.
sandboxctl_run() {
    [ ${#} -gt 0 ] || shtk_cli_usage_error "run requires at least one argument"

    sandboxctl_mount
    local ret=0
    chroot "$(shtk_config_get SANDBOX_ROOT)" "${@}" || ret="${?}"
    sandboxctl_unmount
    return "${ret}"
}


# Runs an interactive shell inside the sandbox.
#
# \return The exit status of the shell.
sandboxctl_shell() {
    [ ${#} -eq 0 ] || shtk_cli_usage_error "shell does not take any arguments"

    sandboxctl_mount
    local ret=0
    PS1="sandbox# " chroot "$(shtk_config_get SANDBOX_ROOT)" /bin/sh \
        || ret="${?}"
    sandboxctl_unmount
    return "${ret}"
}


# Loads the configuration file specified in the command line.
#
# \param config_name Name of the desired configuration.  It can be either a
#     configuration name (no slashes) or a path.
sandboxctl_config_load() {
    local config_name="${1}"; shift

    local config_file=
    case "${config_name}" in
        */*|*.conf)
            config_file="${config_name}"
            ;;

        *)
            config_file="${SANDBOXCTL_ETCDIR}/${config_name}.conf"
            [ -e "${config_file}" ] \
                || shtk_cli_usage_error "Cannot locate configuration named" \
                "'${config_name}'"
            ;;
    esac
    shtk_config_load "${config_file}"
}


# Entry point to the program.
#
# \param ... Command-line arguments to be processed.
#
# \return An exit code to be returned to the user.
main() {
    local config_name="default"

    sandbox_load_types "${SANDBOXCTL_MODULESDIR}"
    shtk_config_init ${SANDBOXCTL_CONFIG_VARS} $(sandbox_call_types config_vars)

    local OPTIND
    while getopts ':c:o:v' arg "${@}"; do
        case "${arg}" in
            c)  # Name of the configuration to load.
                config_name="${OPTARG}"
                ;;

            o)  # Override for a particular configuration variable.
                shtk_config_override "${OPTARG}"
                ;;

            v)  # Be verbose.
                shtk_cli_set_log_level debug
                ;;

            :)
                shtk_cli_usage_error "Missing argument to option -${OPTARG}"
                ;;

            \?)
                shtk_cli_usage_error "Unknown option -${OPTARG}"
                ;;
        esac
    done
    shift $((${OPTIND} - 1))
    OPTIND=1  # Should not be necessary due to the 'local' above.

    [ ${#} -ge 1 ] || shtk_cli_usage_error "No command specified"

    local exit_code=0

    local command="${1}"; shift
    case "${command}" in
        config|create|destroy|mount|run|shell|unmount)
            sandboxctl_set_defaults
            sandboxctl_config_load "${config_name}"
            "sandboxctl_${command}" "${@}" || exit_code="${?}"
            ;;

        *)
            shtk_cli_usage_error "Unknown command ${command}"
            ;;
    esac

    return "${exit_code}"
}

dnl Copyright 2013 Google Inc.
dnl All rights reserved.
dnl
dnl Redistribution and use in source and binary forms, with or without
dnl modification, are permitted provided that the following conditions are
dnl met:
dnl
dnl * Redistributions of source code must retain the above copyright
dnl   notice, this list of conditions and the following disclaimer.
dnl * Redistributions in binary form must reproduce the above copyright
dnl   notice, this list of conditions and the following disclaimer in the
dnl   documentation and/or other materials provided with the distribution.
dnl * Neither the name of Google Inc. nor the names of its contributors
dnl   may be used to endorse or promote products derived from this software
dnl   without specific prior written permission.
dnl
dnl THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
dnl "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
dnl LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
dnl A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
dnl OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
dnl SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
dnl LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
dnl DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
dnl THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
dnl (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
dnl OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

AC_INIT([sandboxctl], [0.1],
        [https://github.com/jmmv/sandboxctl/issues/], [sandboxctl],
        [https://github.com/jmmv/sandboxctl/])
AC_PREREQ([2.65])


AC_COPYRIGHT([Copyright 2013 Google Inc.])
AC_CONFIG_AUX_DIR([admin])
AC_CONFIG_FILES([Makefile])
AC_CONFIG_SRCDIR([sandboxctl.sh])


AM_INIT_AUTOMAKE([1.9 check-news foreign subdir-objects -Wall])


AC_MSG_CHECKING([for operating system name])
osname="$(uname -s)"
AC_MSG_RESULT([${osname}])
case "${osname}" in
    Darwin|FreeBSD|NetBSD)
        ;;
    *)
        AC_MSG_ERROR([Operating system ${osname} is not supported])
        ;;
esac
AM_CONDITIONAL([SANDBOXCTL_OS_DARWIN], [test "${osname}" = Darwin])
AM_CONDITIONAL([SANDBOXCTL_OS_FREEBSD], [test "${osname}" = FreeBSD])
AM_CONDITIONAL([SANDBOXCTL_OS_NETBSD], [test "${osname}" = NetBSD])
AC_SUBST([SANDBOXCTL_OS], [${osname}])


case "${osname}" in
    Darwin)
        AC_PATH_PROG([BINDFS], [bindfs])
        if test -z "${BINDFS}"; then
            AC_MSG_ERROR([bindfs is required but was not found])
        fi
        if ! test -e "${BINDFS}"; then
            AC_MSG_ERROR([bindfs in ${BINDFS} does not exist])
        fi
        ;;
esac


AC_ARG_VAR([SANDBOXCTL_CONFSUBDIR],
           [Subdirectory of sysconfdir under which to look for files])
if test x"${SANDBOXCTL_CONFSUBDIR-unset}" = x"unset"; then
    SANDBOXCTL_CONFSUBDIR=sandboxctl
else
    case "${SANDBOXCTL_CONFSUBDIR}" in
    /*)
        AC_MSG_ERROR([SANDBOXCTL_CONFSUBDIR must hold a relative path])
        ;;
    *)
        ;;
    esac
fi
if test x"${SANDBOXCTL_CONFSUBDIR}" = x""; then
    AC_SUBST(sandboxctl_confdir, \${sysconfdir})
else
    AC_SUBST(sandboxctl_confdir, \${sysconfdir}/\${SANDBOXCTL_CONFSUBDIR})
fi


m4_ifndef([PKG_CHECK_MODULES],
    [m4_fatal([Cannot find pkg.m4; see the INSTALL document for help])])

m4_ifndef([SHTK_CHECK],
    [m4_fatal([Cannot find shtk.m4; see the INSTALL document for help])])
SHTK_CHECK([>= 1.7])

m4_ifndef([ATF_CHECK_SH],
    [m4_fatal([Cannot find atf-sh.m4; see the INSTALL document for help])])
ATF_CHECK_SH([>= 0.17])
m4_ifndef([ATF_ARG_WITH],
    [m4_fatal([Cannot find atf-common.m4; see the INSTALL document for help])])
ATF_ARG_WITH


AC_PATH_PROG([KYUA], [kyua])
AM_CONDITIONAL([HAVE_KYUA], [test -n "${KYUA}"])


AC_SUBST(pkgtestsdir, \${testsdir}/sandboxctl)
AC_SUBST(testsdir, \${exec_prefix}/tests)


AC_OUTPUT

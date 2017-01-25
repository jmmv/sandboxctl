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

PHONY_TARGETS =

doc_DATA = AUTHORS CONTRIBUTING.md CONTRIBUTORS COPYING NEWS README
noinst_DATA = INSTALL README
EXTRA_DIST = $(doc_DATA) INSTALL README

BUILD_SED = \
	sed -e 's,__ATF_SH__,$(ATF_SH),g' \
	    -e 's,__BINDFS__,$(BINDFS),g' \
	    -e 's,__SANDBOXCTL_ETCDIR__,$(sandboxctl_confdir),g' \
	    -e 's,__SANDBOXCTL_MODULESDIR__,$(pkgdatadir),g' \
	    -e 's,__SHTK__,$(SHTK_TOOL),g'
BUILD_SCRIPT = \
	cat $${sources} | $(BUILD_SED) | \
	    $(SHTK_TOOL) build -o "$${target}" -
BUILD_FILE = \
	cat $${sources} | $(BUILD_SED) >"$${target}"
BUILD_MAN = \
	cat $${sources} | $(BUILD_SED) | awk ' \
	    BEGIN { skip = 0 } \
	    /^@if $(SANDBOXCTL_OS)$$/ { skip = 0; next } \
	    /^@if / { skip = 1; next } \
	    /^@endif$$/ { skip = 0; next } \
	    { if (!skip) print } \
	' >"$${target}"
BUILD_TEST = \
	cat $${sources} | $(BUILD_SED) \
	    | $(SHTK_TOOL) build -s '$(ATF_SH)' -m '' -o "$${target}" -

dist_pkgdata_DATA = modules/empty.subr
if SANDBOXCTL_OS_DARWIN
dist_pkgdata_DATA += modules/darwin_native.subr
else
EXTRA_DIST += modules/darwin_native.subr
endif
if SANDBOXCTL_OS_FREEBSD
dist_pkgdata_DATA += modules/freebsd_native.subr
else
EXTRA_DIST += modules/freebsd_native.subr
endif
if SANDBOXCTL_OS_LINUX
dist_pkgdata_DATA += modules/linux_native.subr
else
EXTRA_DIST += modules/linux_native.subr
endif
if SANDBOXCTL_OS_NETBSD
dist_pkgdata_DATA += modules/netbsd_native.subr
dist_pkgdata_DATA += modules/netbsd_release.subr
else
EXTRA_DIST += modules/netbsd_native.subr
EXTRA_DIST += modules/netbsd_release.subr
endif

nodist_sandboxctl_conf_DATA = default.conf
CLEANFILES = default.conf
EXTRA_DIST += examples/Darwin.conf
EXTRA_DIST += examples/FreeBSD.conf
EXTRA_DIST += examples/Linux.conf
EXTRA_DIST += examples/NetBSD.conf
default.conf: $(srcdir)/examples/$(SANDBOXCTL_OS).conf
	$(AM_V_GEN)cp $(srcdir)/examples/$(SANDBOXCTL_OS).conf default.conf

EXTRA_DIST += test_utils.sh

shtk_modulesdir = $(SHTK_MODULESDIR)
nodist_shtk_modules_DATA = sandbox.subr
CLEANFILES += sandbox.subr
EXTRA_DIST += sandbox.subr.in
sandbox.subr: $(srcdir)/sandbox.subr.in
	sources="$(srcdir)/sandbox.subr.in" target=sandbox.subr; $(BUILD_FILE)

sbin_SCRIPTS = sandboxctl
CLEANFILES += sandboxctl
EXTRA_DIST += sandboxctl.sh
sandboxctl: $(srcdir)/sandboxctl.sh
	sources="$(srcdir)/sandboxctl.sh" target=sandboxctl; $(BUILD_SCRIPT)

man_MANS = sandboxctl.8
CLEANFILES += sandboxctl.8
EXTRA_DIST += sandboxctl.8.in
sandboxctl.8: $(srcdir)/sandboxctl.8.in
	sources="$(srcdir)/sandboxctl.8.in" target=sandboxctl.8; $(BUILD_MAN)

man_MANS += sandboxctl.conf.5
CLEANFILES += sandboxctl.conf.5
EXTRA_DIST += sandboxctl.conf.5.in
sandboxctl.conf.5: $(srcdir)/sandboxctl.conf.5.in
	sources="$(srcdir)/sandboxctl.conf.5.in" target=sandboxctl.conf.5; \
	$(BUILD_MAN)

if WITH_ATF
dist_pkgtests_DATA = Kyuafile

pkgtests_SCRIPTS = sandbox_test
CLEANFILES += sandbox_test
EXTRA_DIST += sandbox_test.sh
sandbox_test: $(srcdir)/sandbox_test.sh $(srcdir)/test_utils.sh
	sources="$(srcdir)/sandbox_test.sh $(srcdir)/test_utils.sh"; \
	target=sandbox_test; $(BUILD_TEST)

pkgtests_SCRIPTS += sandboxctl_test
CLEANFILES += sandboxctl_test
EXTRA_DIST += sandboxctl_test.sh
sandboxctl_test: $(srcdir)/sandboxctl_test.sh $(srcdir)/test_utils.sh
	sources="$(srcdir)/sandboxctl_test.sh $(srcdir)/test_utils.sh" \
	target=sandboxctl_test; $(BUILD_TEST)

modulestestsdir = $(pkgtestsdir)/modules
dist_modulestests_DATA = modules/Kyuafile

modulestests_SCRIPTS =

EXTRA_DIST += modules/darwin_native_test.sh
if SANDBOXCTL_OS_DARWIN
modulestests_SCRIPTS += modules/darwin_native_test
CLEANFILES += modules/darwin_native_test
modules/darwin_native_test: $(srcdir)/modules/darwin_native_test.sh \
                            $(srcdir)/test_utils.sh
	test -d modules || mkdir -p modules
	sources="$(srcdir)/modules/darwin_native_test.sh $(srcdir)/test_utils.sh" \
	target=modules/darwin_native_test; $(BUILD_TEST)
endif

EXTRA_DIST += modules/freebsd_native_test.sh
if SANDBOXCTL_OS_FREEBSD
modulestests_SCRIPTS += modules/freebsd_native_test
CLEANFILES += modules/freebsd_native_test
modules/freebsd_native_test: $(srcdir)/modules/freebsd_native_test.sh \
                             $(srcdir)/test_utils.sh
	test -d modules || mkdir -p modules
	sources="$(srcdir)/modules/freebsd_native_test.sh $(srcdir)/test_utils.sh" \
	target=modules/freebsd_native_test; $(BUILD_TEST)
endif

EXTRA_DIST += modules/linux_native_test.sh
if SANDBOXCTL_OS_LINUX
modulestests_SCRIPTS += modules/linux_native_test
CLEANFILES += modules/linux_native_test
modules/linux_native_test: $(srcdir)/modules/linux_native_test.sh \
                           $(srcdir)/test_utils.sh
	test -d modules || mkdir -p modules
	sources="$(srcdir)/modules/linux_native_test.sh $(srcdir)/test_utils.sh" \
	target=modules/linux_native_test; $(BUILD_TEST)
endif

EXTRA_DIST += modules/netbsd_native_test.sh
if SANDBOXCTL_OS_NETBSD
modulestests_SCRIPTS += modules/netbsd_native_test
CLEANFILES += modules/netbsd_native_test
modules/netbsd_native_test: $(srcdir)/modules/netbsd_native_test.sh \
                            $(srcdir)/test_utils.sh
	test -d modules || mkdir -p modules
	sources="$(srcdir)/modules/netbsd_native_test.sh $(srcdir)/test_utils.sh" \
	target=modules/netbsd_native_test; $(BUILD_TEST)
endif

if SANDBOXCTL_OS_NETBSD
modulestests_SCRIPTS += modules/netbsd_release_test
CLEANFILES += modules/netbsd_release_test
EXTRA_DIST += modules/netbsd_release_test.sh
modules/netbsd_release_test: $(srcdir)/modules/netbsd_release_test.sh \
                             $(srcdir)/test_utils.sh
	test -d modules || mkdir -p modules
	sources="$(srcdir)/modules/netbsd_release_test.sh $(srcdir)/test_utils.sh" \
	target=modules/netbsd_release_test; $(BUILD_TEST)
endif

if HAVE_KYUA
CHECK_ENVIRONMENT  = PATH=$(abs_top_builddir):$${PATH}
CHECK_ENVIRONMENT += SANDBOXCTL_MODULESDIR=$(abs_top_srcdir)/modules
CHECK_ENVIRONMENT += SHTK_MODULESPATH=$(abs_top_srcdir):$${SHTK_MODULESPATH}
INSTALLCHECK_ENVIRONMENT = PATH=$(prefix)/sbin:$${PATH}

# Allow the caller to override the configuration file passed to our test runs
# below (or any other argument for that matter).
KYUA_FLAGS ?=

check-local: check-kyua
PHONY_TARGETS += check-kyua
check-kyua:
	$(CHECK_ENVIRONMENT) $(TESTS_ENVIRONMENT) \
	    $(KYUA) $(KYUA_FLAGS) test \
	    --kyuafile='$(top_srcdir)/Kyuafile' --build-root='$(top_builddir)'

installcheck-local: installcheck-kyua
PHONY_TARGETS += installcheck-kyua
installcheck-kyua:
	cd $(pkgtestsdir) && $(INSTALLCHECK_ENVIRONMENT) $(TESTS_ENVIRONMENT) \
	    $(KYUA) $(KYUA_FLAGS) test
else  # HAVE_KYUA
PHONY_TARGETS += missing-kyua
missing-kyua:
	@echo "WARNING: kyua not found; no tests run"

check-local: missing-kyua
installcheck-local: missing-kyua
endif  # HAVE_KYUA
else  # WITH_ATF
dist-hook: forbid-dist
PHONY_TARGETS += forbid-dist
forbid-dist:
	@echo "Sorry; cannot make dist without atf."
	@false
endif  # WITH_ATF

PHONY_TARGETS += clean-all
clean-all:
	GIT="$(GIT)" $(SH) $(srcdir)/admin/clean-all.sh

.PHONY: $(PHONY_TARGETS)

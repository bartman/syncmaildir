# ----------------------------------------------------------------------------
# These variables should not be changed by the regular user, only developers
# should care about them

PROJECTNAME=syncmaildir
VERSION=0.9.12
BINARIES=mddiff smd-applet
MANPAGES=mddiff.1 smd-server.1 smd-client.1 \
	 smd-pull.1 smd-push.1 smd-loop.1 smd-applet.1
HTML=index.html design.html
DESTDIR=
SF_FRS=/home/frs/project/s/sy/syncmaildir/syncmaildir
SF_LOGIN=gareuselesinge,syncmaildir
SF_WEB=htdocs

# ----------------------------------------------------------------------------
# These variables affect the programs behaviour and their installation;
# they are meant to be overridden if necessary. See the end of this
# file for some templates setting them.

PREFIX=usr/local
SED=sed
SHA1SUM=sha1sum
XDELTA=xdelta
CPN=cp -n
SSH=ssh
LUAV=5.1
LUA=lua$(LUAV)
CFLAGS=-O2 -Wall -Wextra -g
PKG_FLAGS=

# ----------------------------------------------------------------------------
# Rules follow...

all: check-build $(BINARIES) 

%: %.vala Makefile 
	echo "class SMDConf { \
		public static const string PREFIX = \"/$(PREFIX)\"; \
		public static const string VERSION = \"$(VERSION)\"; \
		}" \
		> config.vala
	valac -o $@ $< config.vala --thread \
		--pkg glib-2.0 --pkg gtk+-2.0 \
		--pkg libnotify --pkg gconf-2.0 \
		--pkg posix --pkg gee-1.0

%: %.c
	pkg-config --atleast-version=2.19.1 glib-2.0
	gcc $(CFLAGS) $< -o $@ -DVERSION="$(VERSION)" \
		`pkg-config $(PKG_FLAGS) --cflags --libs glib-2.0` 

check-build: check-w-gcc check-w-valac
check-run: check-w-$(LUA) check-w-bash 

check-w-%:
	@which $* > /dev/null || echo $* not found

test: all check-run misc/Mail.testcase.tgz
	@tests.d/test.sh $T
	@tests.d/check.sh
	@rm -rf test.[0-9]*/

misc/Mail.testcase.tgz: 
	$(MAKE) check-w-polygen
	mkdir -p Mail/cur
	for i in `seq 100`; do \
		echo "Subject: `polygen /usr/share/polygen/eng/manager.grm`"\
			>> Mail/cur/$$i; \
		echo "Message-Id: $$i" >> Mail/cur/$$i; \
		echo >> Mail/cur/$$i;\
		polygen -X 10 /usr/share/polygen/eng/manager.grm\
	       		>> Mail/cur/$$i;\
	done
	tar -czf $@ Mail
	rm -rf Mail

%.1:%.1.txt check-w-txt2man
	txt2man -t $* -v "Sync Mail Dir (smd) documentation" -s 1 $< > $@

define install-replacing
	cat $(1) |\
		$(SED) 's?@PREFIX@?/$(PREFIX)?' |\
		$(SED) 's?@SED@?$(SED)?'  |\
		$(SED) 's?@SHA1SUM@?$(SHA1SUM)?' |\
		$(SED) 's?@XDELTA@?$(XDELTA)?' |\
		$(SED) 's?@CPN@?$(CPN)?' |\
		$(SED) 's?@SSH@?$(SSH)?' |\
		$(SED) 's?#! /usr/bin/env lua.*?#! /usr/bin/env $(LUA)?' |\
		cat > $(DESTDIR)/$(PREFIX)/$(2)/$(1)
	if [ $(2) = "bin" ]; then chmod a+rx $(DESTDIR)/$(PREFIX)/$(2)/$(1); fi
endef

define install
	cp $(1) $(DESTDIR)/$(PREFIX)/$(2)/$(1)
	if [ $(2) = "bin" ]; then chmod a+rx $(DESTDIR)/$(PREFIX)/$(2)/$(1); fi
endef

define mkdir-p
	mkdir -p $(DESTDIR)/$(PREFIX)/$(1)
endef

install: install-bin install-misc

install-bin: $(BINARIES)
	$(call mkdir-p,bin)
	$(call mkdir-p,share/$(PROJECTNAME))
	$(call mkdir-p,share/$(PROJECTNAME)-applet)
	$(call mkdir-p,share/lua/$(LUAV))
	cp $(BINARIES) $(DESTDIR)/$(PREFIX)/bin
	$(call install-replacing,smd-server,bin)
	$(call install-replacing,smd-client,bin)
	$(call install-replacing,smd-pull,bin)
	$(call install-replacing,smd-push,bin)
	$(call install-replacing,smd-loop,bin)
	$(call install-replacing,smd-common,share/$(PROJECTNAME))
	$(call install-replacing,syncmaildir.lua,share/lua/$(LUAV))

install-misc: $(MANPAGES)
	mkdir -p $(DESTDIR)/etc/xdg/autostart
	cp smd-applet.desktop $(DESTDIR)/etc/xdg/autostart
	$(call mkdir-p,share/applications)
	$(call install,smd-applet-configure.desktop,share/applications)
	$(call install,smd-applet.ui,share/$(PROJECTNAME)-applet)
	$(call mkdir-p,share/man/man1)
	cp $(MANPAGES) $(DESTDIR)/$(PREFIX)/share/man/man1

clean: 
	rm -rf $(BINARIES) $(MANPAGES)
	rm -rf test.[0-9]*/ 
	rm -rf $(PROJECTNAME)-$(VERSION)/ $(PROJECTNAME)-$(VERSION).tar.gz
	rm -f $(HTML)
	rm -f config.vala

dist $(PROJECTNAME)-$(VERSION).tar.gz:
	$(MAKE) clean
	mkdir $(PROJECTNAME)-$(VERSION)
	for X in *; do if [ $$X != $(PROJECTNAME)-$(VERSION) ]; then \
		cp -r $$X $(PROJECTNAME)-$(VERSION); fi; done;
	tar -cvzf $(PROJECTNAME)-$(VERSION).tar.gz $(PROJECTNAME)-$(VERSION)
	rm -rf $(PROJECTNAME)-$(VERSION)

$(HTML): check-w-markdown
	cat misc/head.html > index.html
	markdown README >> index.html
	cat misc/tail.html >> index.html
	cat misc/head.html > design.html
	markdown DESIGN >> design.html
	cat misc/tail.html >> design.html

upload-website: $(HTML)
	scp $(HTML) misc/style.css $(SF_LOGIN)@web.sourceforge.net:$(SF_WEB)

upload-tarball: $(PROJECTNAME)-$(VERSION).tar.gz
	scp $< $(SF_LOGIN)@frs.sourceforge.net:$(SF_FRS)/$<

upload-changelog: ChangeLog
	scp $< $(SF_LOGIN)@frs.sourceforge.net:$(SF_FRS)/$<


# ----------------------------------------------------------------------------
# These templates collect standard values for known platforms, like osx.
# To use a template run make TEMPLATE/TARGET, for example:
#   make osx/all && make osx/install
# You may also combine templates. For example, to build only text mode
# utilities on osx type:
#   make osx/text/all && make osx/text/install

text/%:
	$(MAKE) $* \
		BINARIES="$(subst smd-applet,,$(BINARIES))" \
		MANPAGES="$(subst smd-applet.1,,$(MANPAGES))"

static/%:
	$(MAKE) $* \
		CFLAGS="$(CFLAGS) -static " \
		PKG_FLAGS="$(PKG_FLAGS) --static "

osx/%:
	$(MAKE) $* SED=sed CPN=cp 

abspath/%:
	$(MAKE) $* SED=/bin/sed SHA1SUM=/usr/bin/sha1sum \
		XDELTA=/usr/bin/xdelta CPN="/bin/cp -n" SSH=/usr/bin/ssh

# eof

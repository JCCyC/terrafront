ROM     := terrafnt.rom
BIN     := terrafnt.bin
DSK     := terrafnt.dsk
# Empty bootable 720K MSX disk (tracked; made once by blankdisk.py)
BLANKDSK := blank720k.dsk
INCS    := build/sprites.inc build/sfx.inc build/path.inc build/title.inc build/font.inc

# Version from main.asm, for the zip name
VER_PART = $(shell awk '$$1 == "VERSION_$(1)" && $$2 == "equ" { print $$3 }' main.asm)
ZIP      := terrafnt_$(call VER_PART,MAJOR)_$(call VER_PART,MINOR)_$(call VER_PART,PATCH).zip
VERSION  := $(call VER_PART,MAJOR).$(call VER_PART,MINOR).$(call VER_PART,PATCH)

# Any run target: make FS=1 run starts openMSX fullscreen (else windowed),
# make VIDEO=1 run records the session to videos/<target>-<date>-<time>.avi.
# make CMDONLY=1 run only prints the openMSX command (after building).
# Each switch is on only when it's a nonzero number.
# $(call OPENMSX,machine and media options)
nonzero = $(shell ([ $$(($(1)+0)) -ne 0 ] && echo 1) 2>/dev/null)
FS_MODE := $(if $(call nonzero,$(FS)),on,off)
VIDEO_ON := $(call nonzero,$(VIDEO))
CMDONLY_ON := $(call nonzero,$(CMDONLY))
OPENMSX_CMD = openmsx -command "set fullscreen $(FS_MODE)" $(1)$(if $(VIDEO_ON), -command "record start {$$v}")
OPENMSX = $(if $(CMDONLY_ON),@)$(if $(VIDEO_ON),mkdir -p videos; v=$(CURDIR)/videos/$@-$$(date +%Y%m%d-%H%M%S).avi; )$(if $(CMDONLY_ON),echo "$(subst ",\",$(OPENMSX_CMD))",$(OPENMSX_CMD)$(if $(VIDEO_ON),; \
	if [ -f "$$v" ]; then echo "Video created at $$v"; else echo "No video was created"; exit 1; fi))

.DELETE_ON_ERROR:   # sjasmplus writes its output even on errors

all: $(ROM) $(BIN) $(DSK)

$(ROM): main.asm $(INCS)
	sjasmplus --nologo --lst=build/terrafnt.lst --sym=build/terrafnt.sym main.asm

# Same code for BLOAD from Disk BASIC: at 8000h, RAM at C000h
$(BIN): main.asm $(INCS)
	sjasmplus --nologo -DBIN --lst=build/terrafnt-bin.lst --sym=build/terrafnt-bin.sym main.asm

# Disk BASIC finds no MSXDOS.SYS, so it runs AUTOEXEC.BAS, which BLOADs the game
$(DSK): $(BIN) autoexec.bas $(BLANKDSK)
	cp $(BLANKDSK) build/disk.tmp
	mcopy -i build/disk.tmp autoexec.bas ::AUTOEXEC.BAS
	mcopy -i build/disk.tmp $(BIN) ::TERRAFNT.BIN
	mv build/disk.tmp $@

build/sprites.inc: png2spr.py images/player-ship.png images/player-ship-coming.png images/reserve-ship.png \
		images/player-ship-boom-1.png images/player-ship-boom-2.png images/player-ship-boom-3.png \
		images/boss.png $(wildcard images/enemy-*.png) $(wildcard images/formation-enemy-*-color-*.png)
	@mkdir -p build
	python3 png2spr.py > $@

build/sfx.inc: sfx.py
	@mkdir -p build
	python3 sfx.py > $@

build/path.inc: path.py
	@mkdir -p build
	python3 path.py > $@

build/title.inc: title.py png2spr.py images/title.png
	@mkdir -p build
	python3 title.py > $@

build/font.inc: font.py images/font.png
	@mkdir -p build
	python3 font.py > $@

zip: $(ZIP)

$(ZIP): $(ROM) $(BIN) $(DSK) terrafnt.txt changes.txt
	@head -1 terrafnt.txt | grep -qx 'TERRA FRONT v\. $(VERSION)' || \
	  { echo "terrafnt.txt: first line isn't 'TERRA FRONT v. $(VERSION)'"; exit 1; }
	@grep -m1 '^Version ' changes.txt | grep -qx 'Version $(VERSION)' || \
	  { echo "changes.txt: latest entry isn't 'Version $(VERSION)'"; exit 1; }
	rm -f $@
	zip -9 $@ $(ROM) $(BIN) $(DSK) terrafnt.txt changes.txt

# The release zip licensed (licensezip.py: the ROM, BIN and DSK's license lines)
FREEWARE := $(ZIP:.zip=_freeware.zip)
PLAYTEST := $(ZIP:.zip=_playtest.zip)
LICENSE_PY := licensezip.py licenserom.py licensebin.py licensedsk.py

freeware: $(FREEWARE)

playtest: $(PLAYTEST)

$(FREEWARE): $(ZIP) $(LICENSE_PY)
	python3 licensezip.py $< "THIS GAME IS FREEWARE" "SHARE THE ZIPFILE AT WILL" >$@.tmp
	mv $@.tmp $@

$(PLAYTEST): $(ZIP) $(LICENSE_PY)
	python3 licensezip.py $< "PLAYTEST COPY" "DO NOT DISTRIBUTE" >$@.tmp
	mv $@.tmp $@

run: $(ROM)
	$(call OPENMSX,-machine Gradiente_Expert_GPC-1 -carta $(ROM))

run-cbios: $(ROM)
	$(call OPENMSX,-machine C-BIOS_MSX1 -carta $(ROM))

run-nms8250: $(ROM)
	$(call OPENMSX,-machine Philips_NMS_8250 -carta $(ROM))

# Headless check on the three test machines: logs in build/test-<machine>.log
test: $(ROM) test.tcl
	@for m in Gradiente_Expert_GPC-1 C-BIOS_MSX1 Philips_NMS_8250; do \
		LOGFILE=$(CURDIR)/build/test-$$m.log SYMFILE=$(CURDIR)/build/terrafnt.sym SHOT=$(CURDIR)/build/shot-$$m.png \
		xvfb-run -a -s "-screen 0 1024x768x24" openmsx -machine $$m -carta $(ROM) -script test.tcl >/dev/null 2>&1; \
		echo "== $$m"; cat build/test-$$m.log; \
	done

# The disk; the Expert has no drive, so it gets one
rundisk: $(DSK)
	$(call OPENMSX,-machine Gradiente_Expert_GPC-1 -ext Panasonic_FS-FD1A -diska $(DSK))

rundisk-nms8250: $(DSK)
	$(call OPENMSX,-machine Philips_NMS_8250 -diska $(DSK))

# The same check on the disk version, booted from a copy of the disk (C-BIOS
# has no Disk BASIC): logs in build/test-disk-<machine>.log, screenshots
# build/shot-disk-<machine>*.png
test-disk: $(DSK) test.tcl
	@for m in Gradiente_Expert_GPC-1:Panasonic_FS-FD1A Philips_NMS_8250:; do \
		mach=$${m%%:*}; ext=$${m#*:}; \
		cp $(DSK) build/test-disk.dsk; \
		LOGFILE=$(CURDIR)/build/test-disk-$$mach.log SYMFILE=$(CURDIR)/build/terrafnt-bin.sym IMAGE=$(BIN) DISK=$(CURDIR)/build/test-disk.dsk \
		SHOT=$(CURDIR)/build/shot-disk-$$mach.png \
		xvfb-run -a -s "-screen 0 1024x768x24" openmsx -machine $$mach $${ext:+-ext $$ext} -diska build/test-disk.dsk -script test.tcl >/dev/null 2>&1; \
		echo "== $$mach (disk)"; cat build/test-disk-$$mach.log; \
	done

# The main loop's time per frame and per routine while test.tcl runs
# (prof.tcl): build/profile-<machine>.txt; PROF_MACHINE (default the
# Expert), PROF_MS (frames over it listed, default 14). openMSX sometimes
# crashes under Xvfb (ISSUES.md): rerun if the file has no "frames" line.
PROF_MACHINE ?= Gradiente_Expert_GPC-1
PROF_MS ?= 14
profile: $(ROM) test.tcl prof.tcl
	@PROFLST=$(CURDIR)/build/terrafnt.lst PROFOUT=$(CURDIR)/build/profile-$(PROF_MACHINE).txt PROFMS=$(PROF_MS) \
		LOGFILE=$(CURDIR)/build/prof-test-$(PROF_MACHINE).log SYMFILE=$(CURDIR)/build/terrafnt.sym SHOT=$(CURDIR)/build/prof-shot.png \
		xvfb-run -a -s "-screen 0 1024x768x24" openmsx -machine $(PROF_MACHINE) -carta $(ROM) -script test.tcl -script prof.tcl >/dev/null 2>&1; \
	grep "^frames\|^MAX" build/profile-$(PROF_MACHINE).txt; grep "^TOP" build/profile-$(PROF_MACHINE).txt | head -5

clean:
	rm -rf build __pycache__ $(ROM) $(BIN) $(DSK) terrafnt_*_*_*.zip terrafnt_*_*_*.zip.tmp

.PHONY: all zip freeware playtest run run-cbios run-nms8250 rundisk rundisk-nms8250 test test-disk profile clean

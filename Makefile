ROM     := terrafnt.rom
INCS    := build/sprites.inc build/sfx.inc build/path.inc build/title.inc build/font.inc

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

all: $(ROM)

$(ROM): main.asm $(INCS)
	sjasmplus --nologo --lst=build/terrafnt.lst --sym=build/terrafnt.sym main.asm

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

clean:
	rm -rf build $(ROM)

.PHONY: all run run-cbios run-nms8250 test clean

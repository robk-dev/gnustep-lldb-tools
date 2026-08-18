# Builds the debugging demos on Linux/WSL. On Windows use the .ps1 scripts
# next to this file instead.
#
#   make -C demos [CC=/path/to/clang] [PREFIX=/usr/local]
#
# PREFIX must contain a libobjc2 install (include/objc/runtime.h,
# lib/libobjc.so). The Foundation demos additionally need gnustep-base
# installed there; `runtime_demo` deliberately does not, so it can be
# debugged against a bare runtime.
#
# gnustep-2.0, 2.1 and 2.2 emit identical runtime metadata, so the exact
# value below only has to be one the installed runtime supports.
CC ?= clang
PREFIX ?= /usr/local
OUT := out

OBJC_FLAGS = -g -O0 -fno-omit-frame-pointer -fobjc-runtime=gnustep-2.1
FOUNDATION_FLAGS = $(OBJC_FLAGS) -fconstant-string-class=NSConstantString \
	-DGNUSTEP -DGNUSTEP_BASE_LIBRARY=1 \
	-I$(PREFIX)/include/GNUstep -I$(PREFIX)/include
FOUNDATION_LIBS = -L$(PREFIX)/lib -Wl,-rpath,$(PREFIX)/lib \
	-lgnustep-base -lobjc -lpthread -lm

all: $(OUT)/runtime_demo $(OUT)/foundation_demo $(OUT)/foundation_types_demo

# Bare libobjc2: no Foundation, so this one also works on a machine where
# only the runtime has been built.
$(OUT)/runtime_demo: runtime_demo.m
	mkdir -p $(OUT)
	$(CC) -g -O0 -fobjc-runtime=gnustep-2.0 -I$(PREFIX)/include $< -o $@ \
		-L$(PREFIX)/lib -lobjc -Wl,-rpath,$(PREFIX)/lib

# The small Foundation program from examples/, which is also what the
# Windows build-foundation.ps1 compiles.
$(OUT)/foundation_demo: ../examples/simple_test.m
	mkdir -p $(OUT)
	$(CC) $(FOUNDATION_FLAGS) $< -o $@ $(FOUNDATION_LIBS)

# One local per Foundation type, for exercising the data formatters.
$(OUT)/foundation_types_demo: foundation_types_demo.m
	mkdir -p $(OUT)
	$(CC) $(FOUNDATION_FLAGS) $< -o $@ $(FOUNDATION_LIBS)

# foundation_shim.m is Windows-only: it supplies _NSPrintForDebugger, which
# gnustep-base exports on Linux but does not dllexport on MSVC.

clean:
	rm -rf $(OUT)

.PHONY: all clean

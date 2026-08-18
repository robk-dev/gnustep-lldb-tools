# Builds the Foundation example on Linux/WSL against a gnustep-base install.
#
#   make -C examples [CC=/path/to/clang] [PREFIX=/usr/local]
#
# On Windows use demos/build-foundation.ps1 instead.
CC ?= clang
PREFIX ?= /usr/local

CFLAGS = -fobjc-runtime=gnustep-2.1 -g -O0 -fno-omit-frame-pointer \
         -fconstant-string-class=NSConstantString \
         -DGNUSTEP -DGNUSTEP_BASE_LIBRARY=1 -DDEBUG=1 \
         -I$(PREFIX)/include/GNUstep -I$(PREFIX)/include
LDFLAGS = -L$(PREFIX)/lib -Wl,-rpath,$(PREFIX)/lib -g
LIBS = -lgnustep-base -lobjc -lpthread -lm

all: simple_test

simple_test: simple_test.m
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS) $(LIBS)

clean:
	rm -f simple_test *.o

.PHONY: all clean

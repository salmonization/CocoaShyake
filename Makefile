# Build CocoaShyake.app with clang alone; no Xcode project.
#
#   make          build/CocoaShyake.app (ad-hoc signed)
#   make run      build and launch
#   make test     upstream test_crypto against the same objects
#   make format   clang-format our sources (never the submodule)

APP  := build/CocoaShyake.app
UP   := shyake/client
BREW := /opt/homebrew
CC   := clang

# ponytail: host arch + brew's arm64-only static libs; the universal
# build (x86_64 slice, own-built deps) arrives with the M5 release work
ARCH  := $(shell uname -m)
MINOS := 10.13
TFLAGS := -arch $(ARCH) -mmacosx-version-min=$(MINOS)
# Brew bottles target the host macOS, so a binary linking them really
# does need the host version; claiming 10.13 at link time would only
# bury that fact under one ld warning per object file. Our own code
# still compiles against 10.13 so availability checks stay honest.
LDMINOS := $(shell sw_vers -productVersion | cut -d. -f1).0

# upstream lib keeps upstream's own flags; it is not our code
UP_CFLAGS := $(TFLAGS) -std=c11 -D_POSIX_C_SOURCE=200809L -O2 \
	-I$(UP)/include -I$(UP)/src/lib -I$(UP)/src/lib/vendor/cJSON \
	-I$(UP)/src/cli \
	-I$(BREW)/include -I$(BREW)/opt/openssl@3/include
OBJCFLAGS := $(TFLAGS) -fobjc-arc -O2 -Wall -Wextra \
	-Wunguarded-availability -I$(UP)/include

# static liboqs/libcrypto so the app never needs brew at run time;
# curl comes from the SDK stub, i.e. the system libcurl
LIBS := $(BREW)/lib/liboqs.a $(BREW)/opt/openssl@3/lib/libcrypto.a \
	-lcurl -framework Cocoa

# wildcard, same as upstream's Makefile: new upstream .c files are
# picked up automatically, so the file list can never drift.
# drafts.c is upstream CLI code, but it only needs libc, cJSON and the
# public API; compiling it unmodified keeps the draft format identical
# to the CLI's by construction instead of by reimplementation.
UP_SRCS := $(wildcard $(UP)/src/lib/*.c) \
	$(wildcard $(UP)/src/lib/vendor/cJSON/*.c) \
	$(UP)/src/cli/drafts.c
UP_OBJS := $(patsubst $(UP)/src/%.c,build/obj/up/%.o,$(UP_SRCS))
SRCS    := $(wildcard src/*.m)
OBJS    := $(patsubst src/%.m,build/obj/%.o,$(SRCS))

.PHONY: all run test format clean

all: $(APP)

$(APP): build/CocoaShyake res/Info.plist
	rm -rf $@
	mkdir -p $@/Contents/MacOS $@/Contents/Resources
	cp build/CocoaShyake $@/Contents/MacOS/
	cp res/Info.plist $@/Contents/
	cp -R res/*.lproj $@/Contents/Resources/ 2>/dev/null || true
	codesign -s - --force $@

build/CocoaShyake: $(OBJS) build/libshyake.a
	$(CC) -arch $(ARCH) -mmacosx-version-min=$(LDMINOS) $^ $(LIBS) -o $@

build/libshyake.a: $(UP_OBJS)
	ar rcs $@ $^

build/obj/up/%.o: $(UP)/src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(UP_CFLAGS) -MMD -MP -c $< -o $@

build/obj/%.o: src/%.m
	@mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS) -MMD -MP -c $< -o $@

-include $(UP_OBJS:.o=.d) $(OBJS:.o=.d)

run: $(APP)
	open $(APP)

test: build/libshyake.a build/obj/Profile.o build/obj/Session.o
	$(CC) $(UP_CFLAGS) -mmacosx-version-min=$(LDMINOS) \
		$(UP)/tests/test_crypto.c $< \
		$(filter-out -framework Cocoa,$(LIBS)) -o build/test_crypto
	build/test_crypto
	$(CC) $(OBJCFLAGS) -Isrc -mmacosx-version-min=$(LDMINOS) \
		tests/test_profile.m build/obj/Profile.o build/obj/Session.o $< \
		$(LIBS) -o build/test_profile
	# a throwaway home keeps the real Application Support untouched
	CFFIXED_USER_HOME=$$(mktemp -d) build/test_profile

format:
	clang-format -i $(wildcard src/*.m src/*.h)

clean:
	rm -rf build

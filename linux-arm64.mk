include version.mk

BUILD_NUMBER ?= $(VER_BUILD)
VER_SUFFIX ?= PortMaster
VER_STRING = $(VER_MAJOR).$(VER_MINOR).$(VER_RELEASE).$(BUILD_NUMBER) $(VER_SUFFIX)

MKDIR ?= mkdir -p
STRIP ?= strip
ECHO ?= echo
MV ?= mv -f
AR ?= ar
CMAKE ?= cmake
CURL ?= curl
PKG_CONFIG ?= pkg-config
GIT_REVISION ?= $(shell git describe --always 2>/dev/null || echo portmaster)
TARGET_SYSROOT ?=

ifneq ($(TARGET_SYSROOT),)
SYSROOT_FLAG = --sysroot=$(TARGET_SYSROOT)
endif

ASTRONOMY_COMMIT = 865d3da7d8112bbc7911238052c6af4aaf877181
CENTIJSON_COMMIT = 93395382de7ea59f7348759b78d5b2044370fcce
ENET6_COMMIT = bf0003fb0004b12ff1d2b0c51c7c7e9a0d2d7732

include posix_sources.mk

KFX_INCLUDES = \
	-Ideps/centijson/include \
	-Ideps/centitoml \
	-Ideps/astronomy/include \
	-Ideps/enet6/include \
	$(shell $(PKG_CONFIG) --cflags sdl2 SDL2_mixer SDL2_net SDL2_image libavformat libavcodec libswresample libavutil openal luajit spng minizip zlib miniupnpc libcurl)

ARM64_FLAGS ?= -march=armv8-a -fsigned-char
KFX_WARNING_FLAGS = -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unknown-pragmas -Wno-format-truncation -Wno-sign-compare
KFX_CFLAGS += $(SYSROOT_FLAG) -g -DDEBUG -DBFDEBUG_LEVEL=0 -O3 $(ARM64_FLAGS) $(KFX_INCLUDES) $(KFX_WARNING_FLAGS) -Wno-absolute-value
KFX_CXXFLAGS += $(SYSROOT_FLAG) -std=c++20 -g -DDEBUG -DBFDEBUG_LEVEL=0 -O3 $(ARM64_FLAGS) $(KFX_INCLUDES) $(KFX_WARNING_FLAGS)

KFX_LDFLAGS += \
	$(SYSROOT_FLAG) \
	-g \
	-rdynamic \
	-Wall -Wextra -Werror \
	-Ldeps/astronomy -lastronomy \
	-Ldeps/centijson -ljson \
	-Ldeps/enet6 -lenet6 \
	$(shell $(PKG_CONFIG) --libs sdl2 SDL2_mixer SDL2_net SDL2_image libavformat libavcodec libswresample libavutil openal luajit spng minizip zlib miniupnpc libcurl) \
	-lnatpmp \
	-ldl

TOML_SOURCES = deps/centitoml/toml_api.c
TOML_OBJECTS = $(patsubst deps/centitoml/%.c,obj/centitoml/%.o,$(TOML_SOURCES))
TOML_CFLAGS += $(SYSROOT_FLAG) -O3 $(ARM64_FLAGS) -Ideps/centijson/include -Wall -Wextra -Werror -Wno-unused-parameter

ifeq ($(ENABLE_LTO), 1)
KFX_CFLAGS += -flto
KFX_CXXFLAGS += -flto
KFX_LDFLAGS += -flto=auto
TOML_CFLAGS += -flto
endif

DEPS_EXTRACTED = \
	deps/centijson/include/json.h \
	deps/astronomy/include/astronomy.h \
	deps/enet6/include/enet6/enet.h

all: bin/keeperfx.aarch64

clean:
	rm -rf obj bin src/ver_defs.h deps/astronomy deps/centijson deps/enet6

.PHONY: all clean

bin/keeperfx.aarch64: $(KFX_OBJECTS) $(TOML_OBJECTS) deps/astronomy/libastronomy.a deps/centijson/libjson.a deps/enet6/libenet6.a | bin
	$(CXX) -o $@ $(KFX_OBJECTS) $(TOML_OBJECTS) $(KFX_LDFLAGS)
	$(STRIP) $@

$(KFX_C_OBJECTS): obj/%.o: src/%.c src/ver_defs.h | obj $(DEPS_EXTRACTED)
	$(MKDIR) $(dir $@)
	$(CC) $(KFX_CFLAGS) -c $< -o $@

$(KFX_CXX_OBJECTS): obj/%.o: src/%.cpp src/ver_defs.h | obj $(DEPS_EXTRACTED)
	$(MKDIR) $(dir $@)
	$(CXX) $(KFX_CXXFLAGS) -c $< -o $@

$(TOML_OBJECTS): obj/centitoml/%.o: deps/centitoml/%.c | obj/centitoml $(DEPS_EXTRACTED)
	$(CC) $(TOML_CFLAGS) -c $< -o $@

bin obj deps/astronomy deps/centijson deps/enet6 obj/centitoml:
	$(MKDIR) $@

src/actionpt.c: deps/centijson/include/json.h
src/api.c: deps/centijson/include/json.h
src/bflib_enet.cpp: deps/enet6/include/enet6/enet.h
src/moonphase.c: deps/astronomy/include/astronomy.h
src/net_holepunch.c: deps/enet6/include/enet6/enet.h

deps/astronomy-arm64.tar.gz:
	$(CURL) -fL -o $@ "https://github.com/cosinekitty/astronomy/archive/$(ASTRONOMY_COMMIT).tar.gz"

deps/astronomy/libastronomy.a: deps/astronomy-arm64.tar.gz | deps/astronomy
	tar -xzf $< -C deps/astronomy --strip-components=1
	$(MKDIR) deps/astronomy/build deps/astronomy/include
	$(CC) $(SYSROOT_FLAG) $(ARM64_FLAGS) -O3 -c deps/astronomy/source/c/astronomy.c -o deps/astronomy/build/astronomy.o
	$(AR) rcs $@ deps/astronomy/build/astronomy.o
	cp deps/astronomy/source/c/astronomy.h deps/astronomy/include/astronomy.h

deps/astronomy/include/astronomy.h: deps/astronomy/libastronomy.a

deps/centijson-arm64.tar.gz:
	$(CURL) -fL -o $@ "https://github.com/mity/centijson/archive/$(CENTIJSON_COMMIT).tar.gz"

deps/centijson/libjson.a: deps/centijson-arm64.tar.gz | deps/centijson
	tar -xzf $< -C deps/centijson --strip-components=1
	$(CMAKE) -S deps/centijson -B deps/centijson/build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 -DCMAKE_SYSROOT=$(TARGET_SYSROOT) -DCMAKE_C_COMPILER=$(CC)
	$(CMAKE) --build deps/centijson/build --target json --parallel
	$(MKDIR) deps/centijson/include
	cp deps/centijson/src/*.h deps/centijson/include/
	cp deps/centijson/build/libjson.a $@

deps/centijson/include/json.h: deps/centijson/libjson.a

deps/enet6-arm64.tar.gz:
	$(CURL) -fL -o $@ "https://github.com/SirLynix/enet6/archive/$(ENET6_COMMIT).tar.gz"

deps/enet6/libenet6.a: deps/enet6-arm64.tar.gz | deps/enet6
	tar -xzf $< -C deps/enet6 --strip-components=1
	$(CMAKE) -S deps/enet6 -B deps/enet6/build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 -DCMAKE_SYSROOT=$(TARGET_SYSROOT) -DCMAKE_C_COMPILER=$(CC)
	$(CMAKE) --build deps/enet6/build --target enet6 --parallel
	cp deps/enet6/build/libenet6.a $@

deps/enet6/include/enet6/enet.h: deps/enet6/libenet6.a

src/ver_defs.h: version.mk
	$(ECHO) "#define VER_MAJOR   $(VER_MAJOR)" > $@.swp
	$(ECHO) "#define VER_MINOR   $(VER_MINOR)" >> $@.swp
	$(ECHO) "#define VER_RELEASE $(VER_RELEASE)" >> $@.swp
	$(ECHO) "#define VER_BUILD   $(BUILD_NUMBER)" >> $@.swp
	$(ECHO) "#define VER_STRING  \"$(VER_STRING)\"" >> $@.swp
	$(ECHO) "#define PACKAGE_SUFFIX  \"$(VER_SUFFIX)\"" >> $@.swp
	$(ECHO) "#define GIT_REVISION  \"$(GIT_REVISION)\"" >> $@.swp
	$(MV) $@.swp $@

include version.mk

BUILD_NUMBER ?= $(VER_BUILD)
VER_SUFFIX ?= Prototype
VER_STRING = $(VER_MAJOR).$(VER_MINOR).$(VER_RELEASE).$(BUILD_NUMBER) $(VER_SUFFIX)

MKDIR ?= mkdir -p
STRIP ?= strip
ECHO ?= echo
MV ?= mv -f
AR ?= ar
CMAKE ?= cmake
CURL ?= curl

HOMEBREW_PREFIX ?= $(shell brew --prefix)
MACOS_PKG_CONFIG_PATH = $(HOMEBREW_PREFIX)/opt/openal-soft/lib/pkgconfig:$(HOMEBREW_PREFIX)/opt/curl/lib/pkgconfig:$(HOMEBREW_PREFIX)/opt/openssl@3/lib/pkgconfig
USER_PKG_CONFIG_PATH := $(PKG_CONFIG_PATH)
PKG_CONFIG = env PKG_CONFIG_PATH="$(MACOS_PKG_CONFIG_PATH):$(USER_PKG_CONFIG_PATH)" pkg-config

ASTRONOMY_COMMIT = 865d3da7d8112bbc7911238052c6af4aaf877181
CENTIJSON_COMMIT = 93395382de7ea59f7348759b78d5b2044370fcce
ENET6_COMMIT = bf0003fb0004b12ff1d2b0c51c7c7e9a0d2d7732

APP_BUNDLE = bin/KeeperFX.app
CODESIGN_IDENTITY ?= -

include posix_sources.mk

KFX_OBJC_SOURCES = src/macos_metal.m
KFX_OBJC_OBJECTS = $(patsubst src/%.m,obj/%.o,$(KFX_OBJC_SOURCES))
KFX_OBJECTS += $(KFX_OBJC_OBJECTS)

KFX_INCLUDES = \
	-Ideps/centijson/include \
	-Ideps/centitoml \
	-Ideps/astronomy/include \
	-Ideps/enet6/include \
	-I$(HOMEBREW_PREFIX)/opt/libnatpmp/include \
	$(shell $(PKG_CONFIG) --cflags sdl2 SDL2_mixer SDL2_net SDL2_image libavformat libavcodec libswresample libavutil openal luajit spng minizip zlib miniupnpc libcurl)

MACOSX_DEPLOYMENT_TARGET ?= $(shell sw_vers -productVersion | cut -d. -f1).0
MACOS_ARCH_FLAGS = -arch arm64 -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) -mno-global-merge
MACOS_WARNING_FLAGS = -Wno-unused-but-set-variable -Wno-unused-function -Wno-missing-field-initializers -Wno-tautological-constant-out-of-range-compare -Wno-constant-conversion -Wno-gnu-folding-constant -Wno-bitwise-instead-of-logical -Wno-c23-extensions -Wno-parentheses-equality -Wno-absolute-value -Wno-deprecated-declarations

KFX_CFLAGS += -g -DDEBUG -DBFDEBUG_LEVEL=0 -O3 $(MACOS_ARCH_FLAGS) $(KFX_INCLUDES) -Wall -Wextra -Werror -Wno-unused-parameter -Wno-absolute-value -Wno-unknown-pragmas -Wno-sign-compare $(MACOS_WARNING_FLAGS)
KFX_CXXFLAGS += -std=c++20 -g -DDEBUG -DBFDEBUG_LEVEL=0 -O3 $(MACOS_ARCH_FLAGS) $(KFX_INCLUDES) -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unknown-pragmas -Wno-sign-compare $(MACOS_WARNING_FLAGS)

KFX_LDFLAGS += \
	-g \
	-arch arm64 \
	-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) \
	-Wl,-no_fixup_chains \
	-Wl,-no_warn_reduced_section_align \
	-Wl,-unaligned_pointers,suppress \
	-Wall -Wextra -Werror \
	-Ldeps/astronomy -lastronomy \
	-Ldeps/centijson -ljson \
	-Ldeps/enet6 -lenet6 \
	$(shell $(PKG_CONFIG) --libs sdl2 SDL2_mixer SDL2_net SDL2_image libavformat libavcodec libswresample libavutil openal luajit spng minizip zlib miniupnpc libcurl) \
	-L$(HOMEBREW_PREFIX)/opt/libnatpmp/lib -lnatpmp \
	-framework CoreGraphics \
	-framework QuartzCore \
	-liconv

TOML_SOURCES = \
	deps/centitoml/toml_api.c

TOML_OBJECTS = $(patsubst deps/centitoml/%.c,obj/centitoml/%.o,$(TOML_SOURCES))

TOML_INCLUDES = \
	-Ideps/centijson/include

TOML_CFLAGS += -O3 $(MACOS_ARCH_FLAGS) $(TOML_INCLUDES) -Wall -Wextra -Werror -Wno-unused-parameter

ifeq ($(ENABLE_LTO), 1)
KFX_CFLAGS += -flto
KFX_CXXFLAGS += -flto
KFX_LDFLAGS += -flto=auto
TOML_CFLAGS += -flto
endif

# All downloaded dependencies must be unpacked before any object is compiled.
# Otherwise a parallel build (make -jN) can start compiling a source that
# includes a not-yet-extracted dependency header (e.g. <enet6/enet.h>) and fail
# on the first run. Used as an order-only prerequisite of every object below.
DEPS_EXTRACTED = \
	deps/centijson/include/json.h \
	deps/astronomy/include/astronomy.h \
	deps/enet6/include/enet6/enet.h

MACOS_STATIC_DEPS = \
	deps/astronomy/libastronomy.a \
	deps/centijson/libjson.a \
	deps/enet6/libenet6.a

all: bin/keeperfx

app: $(APP_BUNDLE)

clean:
	rm -rf obj bin src/ver_defs.h

clean-deps:
	rm -rf deps/astronomy deps/centijson deps/enet6
	rm -f deps/astronomy-macos-arm64.tar.gz deps/centijson-macos-arm64.tar.gz deps/enet6-macos-arm64.tar.gz

.PHONY: all app clean clean-deps

$(APP_BUNDLE): bin/keeperfx macos/Info.plist.in macos/bundle_dylibs.sh res/keeperfx_icon512-24bpp.png
	rm -rf $(APP_BUNDLE) bin/KeeperFX.iconset
	$(MKDIR) $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Frameworks $(APP_BUNDLE)/Contents/Resources bin/KeeperFX.iconset
	cp bin/keeperfx $(APP_BUNDLE)/Contents/MacOS/keeperfx
	sed -e 's/@VERSION@/$(VER_MAJOR).$(VER_MINOR).$(VER_RELEASE)/g' -e 's/@BUILD@/$(BUILD_NUMBER)/g' -e 's/@MINIMUM_SYSTEM_VERSION@/$(MACOSX_DEPLOYMENT_TARGET)/g' macos/Info.plist.in > $(APP_BUNDLE)/Contents/Info.plist
	cp res/keeperfx_icon016-08bpp.png bin/KeeperFX.iconset/icon_16x16.png
	cp res/keeperfx_icon032-08bpp.png bin/KeeperFX.iconset/icon_16x16@2x.png
	cp res/keeperfx_icon032-08bpp.png bin/KeeperFX.iconset/icon_32x32.png
	cp res/keeperfx_icon064-08bpp.png bin/KeeperFX.iconset/icon_32x32@2x.png
	cp res/keeperfx_icon128-24bpp.png bin/KeeperFX.iconset/icon_128x128.png
	cp res/keeperfx_icon256-24bpp.png bin/KeeperFX.iconset/icon_128x128@2x.png
	cp res/keeperfx_icon256-24bpp.png bin/KeeperFX.iconset/icon_256x256.png
	cp res/keeperfx_icon512-24bpp.png bin/KeeperFX.iconset/icon_256x256@2x.png
	cp res/keeperfx_icon512-24bpp.png bin/KeeperFX.iconset/icon_512x512.png
	sips -z 1024 1024 res/keeperfx_icon512-24bpp.png --out bin/KeeperFX.iconset/icon_512x512@2x.png >/dev/null
	iconutil -c icns bin/KeeperFX.iconset -o $(APP_BUNDLE)/Contents/Resources/KeeperFX.icns
	rm -rf bin/KeeperFX.iconset
	macos/bundle_dylibs.sh $(APP_BUNDLE) "$(CODESIGN_IDENTITY)"

bin/keeperfx: $(KFX_OBJECTS) $(TOML_OBJECTS) $(MACOS_STATIC_DEPS) | bin
	$(CXX) -o $@ $(KFX_OBJECTS) $(TOML_OBJECTS) $(KFX_LDFLAGS)

$(KFX_C_OBJECTS): obj/%.o: src/%.c src/ver_defs.h | obj $(DEPS_EXTRACTED)
	$(MKDIR) $(dir $@)
	$(CC) $(KFX_CFLAGS) -c $< -o $@

$(KFX_CXX_OBJECTS): obj/%.o: src/%.cpp src/ver_defs.h | obj $(DEPS_EXTRACTED)
	$(MKDIR) $(dir $@)
	$(CXX) $(KFX_CXXFLAGS) -c $< -o $@

$(KFX_OBJC_OBJECTS): obj/%.o: src/%.m src/ver_defs.h | obj $(DEPS_EXTRACTED)
	$(MKDIR) $(dir $@)
	$(CC) $(KFX_CFLAGS) -c $< -o $@

$(TOML_OBJECTS): obj/centitoml/%.o: deps/centitoml/%.c | obj/centitoml $(DEPS_EXTRACTED)
	$(CC) $(TOML_CFLAGS) -c $< -o $@

bin obj deps/astronomy deps/centijson deps/enet6 obj/centitoml:
	$(MKDIR) $@

src/actionpt.c: deps/centijson/include/json.h
src/api.c: deps/centijson/include/json.h
src/bflib_enet.cpp: deps/enet6/include/enet6/enet.h
src/moonphase.c: deps/astronomy/include/astronomy.h
src/net_holepunch.c: deps/enet6/include/enet6/enet.h
deps/centitoml/toml_api.c: deps/centijson/include/json.h
deps/centitoml/toml_conv.c: deps/centijson/include/json.h

deps/astronomy-macos-arm64.tar.gz:
	$(CURL) -fL -o $@ "https://github.com/cosinekitty/astronomy/archive/$(ASTRONOMY_COMMIT).tar.gz"

deps/astronomy/libastronomy.a: deps/astronomy-macos-arm64.tar.gz | deps/astronomy
	tar -xzf $< -C deps/astronomy --strip-components=1
	$(MKDIR) deps/astronomy/build deps/astronomy/include
	$(CC) $(MACOS_ARCH_FLAGS) -O3 -c deps/astronomy/source/c/astronomy.c -o deps/astronomy/build/astronomy.o
	$(AR) rcs $@ deps/astronomy/build/astronomy.o
	cp deps/astronomy/source/c/astronomy.h deps/astronomy/include/astronomy.h

deps/astronomy/include/astronomy.h: deps/astronomy/libastronomy.a

deps/centijson-macos-arm64.tar.gz:
	$(CURL) -fL -o $@ "https://github.com/mity/centijson/archive/$(CENTIJSON_COMMIT).tar.gz"

deps/centijson/libjson.a: deps/centijson-macos-arm64.tar.gz | deps/centijson
	tar -xzf $< -C deps/centijson --strip-components=1
	$(CMAKE) -S deps/centijson -B deps/centijson/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=$(MACOSX_DEPLOYMENT_TARGET)
	$(CMAKE) --build deps/centijson/build --target json --parallel
	$(MKDIR) deps/centijson/include
	cp deps/centijson/src/*.h deps/centijson/include/
	cp deps/centijson/build/libjson.a $@

deps/centijson/include/json.h: deps/centijson/libjson.a

deps/enet6-macos-arm64.tar.gz:
	$(CURL) -fL -o $@ "https://github.com/SirLynix/enet6/archive/$(ENET6_COMMIT).tar.gz"

deps/enet6/libenet6.a: deps/enet6-macos-arm64.tar.gz | deps/enet6
	tar -xzf $< -C deps/enet6 --strip-components=1
	$(CMAKE) -S deps/enet6 -B deps/enet6/build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=$(MACOSX_DEPLOYMENT_TARGET)
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
	$(ECHO) "#define GIT_REVISION  \"$(shell git describe  --always)\"" >> $@.swp
	$(MV) $@.swp $@

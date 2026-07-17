include version.mk

BUILD_NUMBER ?= $(VER_BUILD)
VER_SUFFIX ?= Prototype
VER_STRING = $(VER_MAJOR).$(VER_MINOR).$(VER_RELEASE).$(BUILD_NUMBER) $(VER_SUFFIX)

MKDIR ?= mkdir -p
STRIP ?= strip
ECHO ?= echo
MV ?= mv -f

include posix_sources.mk

KFX_INCLUDES = \
	-Ideps/centijson/include \
	-Ideps/centitoml \
	-Ideps/astronomy/include \
	-Ideps/enet6/include \
	-Ideps/libcurl/include \
	$(shell pkg-config --cflags-only-I luajit) \
	$(shell pkg-config --cflags-only-I libavformat)

KFX_CFLAGS += -g -DDEBUG -DBFDEBUG_LEVEL=0 -O3 -march=x86-64 $(KFX_INCLUDES) -Wall -Wextra -Werror -Wno-unused-parameter -Wno-absolute-value -Wno-unknown-pragmas -Wno-format-truncation -Wno-sign-compare
KFX_CXXFLAGS += -g -DDEBUG -DBFDEBUG_LEVEL=0 -O3 -march=x86-64 $(KFX_INCLUDES) -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unknown-pragmas -Wno-format-truncation -Wno-sign-compare

KFX_LDFLAGS += \
	-g \
	-rdynamic \
	-Wall -Wextra -Werror \
	-Ldeps/astronomy -lastronomy \
	-Ldeps/centijson -ljson \
	-Ldeps/enet6 -lenet6 \
	$(shell pkg-config --libs-only-l sdl2) \
	$(shell pkg-config --libs-only-l SDL2_mixer) \
	$(shell pkg-config --libs-only-l SDL2_net) \
	$(shell pkg-config --libs-only-l SDL2_image) \
	$(shell pkg-config --libs-only-l libavformat) \
	$(shell pkg-config --libs-only-l libavcodec) \
	$(shell pkg-config --libs-only-l libswresample) \
	$(shell pkg-config --libs-only-l libavutil) \
	$(shell pkg-config --libs-only-l openal) \
	$(shell pkg-config --libs-only-l luajit) \
	$(shell pkg-config --libs-only-l spng) \
	$(shell pkg-config --libs-only-l minizip) \
	$(shell pkg-config --libs-only-l zlib) \
	-lminiupnpc \
	-lnatpmp \
	-Ldeps/libcurl/lib -lcurl -lssl -lcrypto -lzstd \
	-ldl

TOML_SOURCES = \
	deps/centitoml/toml_api.c

TOML_OBJECTS = $(patsubst deps/centitoml/%.c,obj/centitoml/%.o,$(TOML_SOURCES))

TOML_INCLUDES = \
	-Ideps/centijson/include

TOML_CFLAGS += -O3 -march=x86-64 $(TOML_INCLUDES) -Wall -Wextra -Werror -Wno-unused-parameter

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
	deps/enet6/include/enet6/enet.h \
	deps/libcurl/lib/libcurl.a

all: bin/keeperfx

clean:
	rm -rf obj bin src/ver_defs.h deps/astronomy deps/centijson deps/enet6 deps/libcurl
	rm -f deps/libcurl-lin64.tar.gz

.PHONY: all clean

bin/keeperfx: $(KFX_OBJECTS) $(TOML_OBJECTS) deps/libcurl/lib/libcurl.a | bin
	$(CXX) -o $@ $(KFX_OBJECTS) $(TOML_OBJECTS) $(KFX_LDFLAGS)

$(KFX_C_OBJECTS): obj/%.o: src/%.c src/ver_defs.h | obj $(DEPS_EXTRACTED)
	$(MKDIR) $(dir $@)
	$(CC) $(KFX_CFLAGS) -c $< -o $@

$(KFX_CXX_OBJECTS): obj/%.o: src/%.cpp src/ver_defs.h | obj $(DEPS_EXTRACTED)
	$(MKDIR) $(dir $@)
	$(CXX) $(KFX_CXXFLAGS) -c $< -o $@

$(TOML_OBJECTS): obj/centitoml/%.o: deps/centitoml/%.c | obj/centitoml $(DEPS_EXTRACTED)
	$(CC) $(TOML_CFLAGS) -c $< -o $@

bin obj deps/astronomy deps/centijson deps/enet6 deps/libcurl obj/centitoml:
	$(MKDIR) $@

src/actionpt.c: deps/centijson/include/json.h
src/api.c: deps/centijson/include/json.h
src/bflib_enet.cpp: deps/enet6/include/enet6/enet.h
src/moonphase.c: deps/astronomy/include/astronomy.h
src/net_holepunch.c: deps/enet6/include/enet6/enet.h
src/net_matchmaking.c: deps/libcurl/include/curl/curl.h
deps/centitoml/toml_api.c: deps/centijson/include/json.h
deps/centitoml/toml_conv.c: deps/centijson/include/json.h

deps/astronomy-lin64.tar.gz:
	curl -Lso $@ "https://github.com/dkfans/kfx-deps/releases/download/20250418/astronomy-lin64.tar.gz"

deps/astronomy/include/astronomy.h: deps/astronomy-lin64.tar.gz | deps/astronomy
	tar xzmf $< -C deps/astronomy

deps/centijson-lin64.tar.gz:
	curl -Lso $@ "https://github.com/dkfans/kfx-deps/releases/download/20250418/centijson-lin64.tar.gz"

deps/centijson/include/json.h: deps/centijson-lin64.tar.gz | deps/centijson
	tar xzmf $< -C deps/centijson

deps/enet6-lin64.tar.gz:
	curl -Lso $@ "https://github.com/dkfans/kfx-deps/releases/download/20260213/enet6-lin64.tar.gz"

deps/enet6/include/enet6/enet.h: deps/enet6-lin64.tar.gz | deps/enet6
	tar xzmf $< -C deps/enet6

deps/libcurl-lin64.tar.gz:
	curl -Lso $@ "https://github.com/dkfans/kfx-deps/releases/download/20260310/libcurl-lin64.tar.gz"

deps/libcurl/lib/libcurl.a: deps/libcurl-lin64.tar.gz | deps/libcurl
	tar xzmf $< -C deps/libcurl

deps/libcurl/include/curl/curl.h: deps/libcurl/lib/libcurl.a

src/ver_defs.h: version.mk
	$(ECHO) "#define VER_MAJOR   $(VER_MAJOR)" > $@.swp
	$(ECHO) "#define VER_MINOR   $(VER_MINOR)" >> $@.swp
	$(ECHO) "#define VER_RELEASE $(VER_RELEASE)" >> $@.swp
	$(ECHO) "#define VER_BUILD   $(BUILD_NUMBER)" >> $@.swp
	$(ECHO) "#define VER_STRING  \"$(VER_STRING)\"" >> $@.swp
	$(ECHO) "#define PACKAGE_SUFFIX  \"$(VER_SUFFIX)\"" >> $@.swp
	$(ECHO) "#define GIT_REVISION  \"$(shell git describe  --always)\"" >> $@.swp
	$(MV) $@.swp $@

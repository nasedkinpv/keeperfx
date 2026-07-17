FROM ubuntu:24.04 AS build

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       build-essential ca-certificates cmake curl \
       gcc-aarch64-linux-gnu g++-aarch64-linux-gnu make pkg-config python3 \
    && rm -rf /var/lib/apt/lists/*

RUN dpkg --add-architecture arm64 \
    && sed -i '/^Types:/a Architectures: amd64' /etc/apt/sources.list.d/ubuntu.sources \
    && printf '%s\n' \
       'Types: deb' \
       'URIs: http://ports.ubuntu.com/ubuntu-ports/' \
       'Suites: noble noble-updates noble-security' \
       'Components: main universe multiverse' \
       'Architectures: arm64' \
       'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg' \
       > /etc/apt/sources.list.d/arm64.sources \
    && apt-get update \
    && apt-get install -y --download-only --no-install-recommends \
       libavcodec-dev:arm64 libavformat-dev:arm64 libavutil-dev:arm64 \
       libcurl4-openssl-dev:arm64 libluajit-5.1-dev:arm64 \
       libminiupnpc-dev:arm64 libminizip-dev:arm64 libnatpmp-dev:arm64 \
       libopenal-dev:arm64 libspng-dev:arm64 \
       libsdl2-dev:arm64 libsdl2-image-dev:arm64 \
       libsdl2-mixer-dev:arm64 libsdl2-net-dev:arm64 \
       libswresample-dev:arm64 zlib1g-dev:arm64 \
    && mkdir -p /opt/arm64-sysroot \
    && for deb in /var/cache/apt/archives/*.deb; do dpkg-deb -x "$deb" /opt/arm64-sysroot; done \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

ENV PKG_CONFIG_SYSROOT_DIR=/opt/arm64-sysroot
ENV PKG_CONFIG_LIBDIR=/opt/arm64-sysroot/usr/lib/aarch64-linux-gnu/pkgconfig:/opt/arm64-sysroot/usr/share/pkgconfig

RUN ln -s usr/lib /opt/arm64-sysroot/lib

COPY . /src
WORKDIR /src
ARG GIT_REVISION=portmaster-aarch64
RUN make -f linux-arm64.mk -j"$(nproc)" \
    CC=aarch64-linux-gnu-gcc \
    CXX=aarch64-linux-gnu-g++ \
    AR=aarch64-linux-gnu-ar \
    STRIP=aarch64-linux-gnu-strip \
    TARGET_SYSROOT=/opt/arm64-sysroot \
    GIT_REVISION="$GIT_REVISION" \
    VER_SUFFIX=PortMaster

RUN mkdir -p /artifact/libs.aarch64 \
    && cp -L /opt/arm64-sysroot/usr/lib/aarch64-linux-gnu/libspng.so.0 /artifact/libs.aarch64/ \
    && cp -L /opt/arm64-sysroot/usr/lib/aarch64-linux-gnu/libminiupnpc.so.17 /artifact/libs.aarch64/ \
    && cp -L /opt/arm64-sysroot/usr/lib/aarch64-linux-gnu/libnatpmp.so.1 /artifact/libs.aarch64/ \
    && cp -L /opt/arm64-sysroot/usr/lib/aarch64-linux-gnu/libminizip.so.1 /artifact/libs.aarch64/

FROM scratch AS artifact
COPY --from=build /src/bin/keeperfx.aarch64 /keeperfx.aarch64
COPY --from=build /artifact/libs.aarch64 /libs.aarch64

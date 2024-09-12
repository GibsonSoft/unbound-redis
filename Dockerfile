# syntax=docker/dockerfile:1.9.0

# DL3018: We're specifying pkgs via ARGs + want latest security updates if possible. 
#         Will pin if there are any future issues.
# SC2086: Not needed in the majority of cases here (like apk calls that expect a list of pkgs, not a string).
# DL3020: A bug maybe? All these appear for ARGs with URLs in ADD statements.
# DL3003: Not splitting up RUNs just to cd.
# hadolint global ignore=DL3018,SC2086,DL3020,DL3003

ARG ALPINE_VERSION=latest
ARG XX_VERSION=latest

FROM --platform=${BUILDPLATFORM} tonistiigi/xx:${XX_VERSION} AS xx
FROM --platform=${BUILDPLATFORM} alpine:${ALPINE_VERSION} AS core-base
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG CORE_BUILD_DEPS
ARG BUILD_THREADS

ENV CC="xx-clang"
ENV CXX="xx-clang++"
ENV CFLAGS="-fPIE -fPIC"
ENV CXXFLAGS="-fPIE -fPIC"
ENV LDFLAGS="-fuse-ld=lld -rtlib=compiler-rt -unwindlib=libunwind -static-pie -fpic"
ENV XX_CC_PREFER_LINKER=lld
ENV XX_CC_PREFER_STATIC_LINKER=lld
ENV BUILD_THREADS=${BUILD_THREADS:-1}
ENV CORE_BUILD_DEPS=${CORE_BUILD_DEPS}

ARG OPENSSL_GIT_COMMIT
ARG OPENSSL_VERSION
ENV OPENSSL_VERSION=${OPENSSL_VERSION}@${OPENSSL_GIT_COMMIT}

ARG UNBOUND_GIT_COMMIT
ARG UNBOUND_VERSION
ENV UNBOUND_VERSION=${UNBOUND_VERSION}@${UNBOUND_GIT_COMMIT}

ARG LDNS_GIT_COMMIT
ARG LDNS_VERSION
ENV LDNS_VERSION=${LDNS_VERSION}@${LDNS_GIT_COMMIT}

ARG PROTOBUF_GIT_COMMIT
ARG PROTOBUF_VERSION
ENV PROTOBUF_VERSION=${PROTOBUF_VERSION}@${PROTOBUF_GIT_COMMIT}

ARG PROTOBUFC_GIT_COMMIT
ARG PROTOBUFC_VERSION
ENV PROTOBUFC_VERSION=${PROTOBUFC_VERSION}@${PROTOBUFC_GIT_COMMIT}

ARG HIREDIS_GIT_COMMIT
ARG HIREDIS_VERSION
ENV HIREDIS_VERSION=${HIREDIS_VERSION}@${HIREDIS_GIT_COMMIT}


COPY --from=xx / /

RUN <<EOF
    echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories
    echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
    apk --no-cache upgrade 
    apk add --no-cache ${CORE_BUILD_DEPS}
EOF



FROM scratch AS sources
WORKDIR /tmp/src

ARG OPENSSL_GIT_COMMIT
ARG OPENSSL_SOURCE
ARG OPENSSL_VERSION
ADD --keep-git-dir=true ${OPENSSL_SOURCE}#${OPENSSL_GIT_COMMIT} ./openssl-src

ARG UNBOUND_GIT_COMMIT
ARG UNBOUND_VERSION
ARG UNBOUND_SOURCE
ADD --keep-git-dir=true ${UNBOUND_SOURCE}#${UNBOUND_GIT_COMMIT} ./unbound-src

ARG LDNS_GIT_COMMIT
ARG LDNS_SOURCE
ARG LDNS_VERSION
ADD --keep-git-dir=true ${LDNS_SOURCE}#${LDNS_GIT_COMMIT} ./ldns-src

ARG PROTOBUF_GIT_COMMIT
ARG PROTOBUF_SOURCE
ARG PROTOBUF_VERSION
ADD --keep-git-dir=true ${PROTOBUF_SOURCE}#${PROTOBUF_GIT_COMMIT} ./protobuf-src

ARG PROTOBUFC_GIT_COMMIT
ARG PROTOBUFC_SOURCE
ARG PROTOBUFC_VERSION
ADD --keep-git-dir=true ${PROTOBUFC_SOURCE}#${PROTOBUFC_GIT_COMMIT} ./protobuf-c-src

ARG HIREDIS_GIT_COMMIT
ARG HIREDIS_SOURCE
ARG HIREDIS_VERSION
ADD --keep-git-dir=true ${HIREDIS_SOURCE}#${HIREDIS_GIT_COMMIT} ./hiredis-src



FROM core-base AS target-base
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGET_BUILD_DEPS

RUN <<EOF
    xx-info env # Prevent docker build bug that spams console when apk line w/ variable is first
    xx-apk add --no-cache ${TARGET_BUILD_DEPS}
    ln -s "$(xx-info sysroot)"usr/lib/libunwind.so.1 "$(xx-info sysroot)"usr/lib/libunwind.so
    xx-clang --setup-target-triple

    TARGET_TRIPLE=$(xx-clang --print-target-triple)
    export TARGET_TRIPLE && echo "export TARGET_TRIPLE=${TARGET_TRIPLE}" >> /etc/env
    TARGET_SYSROOT=$(xx-info sysroot)
    export TARGET_SYSROOT && echo "export TARGET_SYSROOT=${TARGET_SYSROOT}" >> /etc/env
    PKG_CONFIG=${TARGET_TRIPLE}-pkg-config
    export PKG_CONFIG && echo "export PKG_CONFIG=${PKG_CONFIG}" >> /etc/env

    if [ $(xx-info march) = "s390x" ]; then
       export LDFLAGS="-fuse-ld=lld -static-pie -fpic" && echo "export LDFLAGS='${LDFLAGS}'" >> /etc/env
    fi
EOF



FROM core-base AS protobuf-build
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG CORE_BUILD_DEPS
ARG TARGET_BUILD_DEPS
ARG PROTOBUF_BUILD_DEPS_BUILD

COPY --from=sources /tmp/src/protobuf-src /tmp/src/protobuf-src

RUN <<EOF
    cd ./protobuf-src || exit
    apk add --no-cache --virtual build-deps ${TARGET_BUILD_DEPS} ${PROTOBUF_BUILD_DEPS_BUILD}

    cmake \
        -S. \
        -Bcmake-out \
        -DCMAKE_INSTALL_PREFIX=/opt/protobuf \
        -DZLIB_LIBRARY_RELEASE:FILEPATH=/lib/libz.a \
        -DABSL_BUILD_TESTING=OFF \
        -Dprotobuf_BUILD_TESTS=OFF \
        -DCMAKE_BUILD_TYPE=Release
    cd cmake-out || exit
    make -j ${BUILD_THREADS} install

    rm -rf /tmp/*
EOF



FROM core-base AS protobuf-c-build
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG CORE_BUILD_DEPS
ARG TARGET_BUILD_DEPS

COPY --from=protobuf-build /opt/protobuf/bin /usr/bin
COPY --from=protobuf-build /opt/protobuf/lib /usr/lib
COPY --from=protobuf-build /opt/protobuf/include /usr/include
COPY --from=sources /tmp/src/protobuf-c-src /tmp/src/protobuf-c-src

RUN <<EOF
    cd protobuf-c-src || exit
    apk add --no-cache --virtual build-deps ${TARGET_BUILD_DEPS}

    ./autogen.sh && ./configure --prefix=/opt/protobuf-c
    make -j ${BUILD_THREADS} install-binPROGRAMS
    ln -s protoc-gen-c /opt/protobuf-c/bin/protoc-c

    rm -rf /tmp/*
EOF



FROM target-base AS protobuf-host
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG CORE_BUILD_DEPS
ARG TARGET_BUILD_DEPS
ARG PROTOBUF_BUILD_DEPS_HOST
ARG TARGETARCH

COPY --from=sources /tmp/src/protobuf-src /tmp/src/protobuf-src

RUN <<EOF
    . /etc/env
    cd ./protobuf-src || exit
    xx-apk add --no-cache --virtual build-deps ${PROTOBUF_BUILD_DEPS_HOST}

    if [ ${TARGETARCH} = 'ppc64le' ]; then
        export CFLAGS="${CFLAGS} -DABSL_USE_UNSCALED_CYCLECLOCK=0"
        export CXXFLAGS="${CXXFLAGS} -DABSL_USE_UNSCALED_CYCLECLOCK=0"
    fi

    cmake \
        -S. \
        -Bcmake-out \
        -DCMAKE_INSTALL_PREFIX=/opt/protobuf \
        -DZLIB_LIBRARY_RELEASE:FILEPATH=${TARGET_SYSROOT}lib/libz.a \
        -DZLIB_INCLUDE_DIR=${TARGET_SYSROOT}usr/include \
        -DABSL_BUILD_TESTING=OFF \
        -Dprotobuf_BUILD_TESTS=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        $(xx-clang --print-cmake-defines)
    cd cmake-out || exit
    make -j ${BUILD_THREADS} install

    rm -rf /tmp/*
EOF



FROM target-base AS protobuf-c-host
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG CORE_BUILD_DEPS
ARG TARGET_BUILD_DEPS

COPY --from=protobuf-build /opt/protobuf/bin /usr/bin
COPY --from=protobuf-host /opt/protobuf/lib /usr/lib
COPY --from=protobuf-host /opt/protobuf/include /usr/include
COPY --from=sources /tmp/src/protobuf-c-src /tmp/src/protobuf-c-src

RUN <<EOF
    . /etc/env

    cd protobuf-c-src || exit

    ./autogen.sh && ./configure \
        PROTOC=/usr/bin/protoc \
        --with-sysroot=${TARGET_SYSROOT} \
        --prefix=/opt/protobuf-c \
        --host=${TARGET_TRIPLE} \
        --disable-protoc
    make -j ${BUILD_THREADS} install

    rm -rf /tmp/*
EOF



FROM target-base AS openssl
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG CORE_BUILD_DEPS
ARG TARGET_BUILD_DEPS
ARG OPENSSL_BUILD_DEPS

COPY --from=sources /tmp/src/openssl-src /tmp/src/openssl-src

RUN <<EOF
    . /etc/env
    cd ./openssl-src || exit
    xx-apk add --no-cache --virtual build-deps ${OPENSSL_BUILD_DEPS}

    export OS=$(xx-info os) MARCH=$(xx-info march)

    if [ ${MARCH} = "armv6l" ] || [ ${MARCH} = "armv7l" ]; then
       export MARCH="armv4"
    elif [ ${MARCH} = "i386" ]; then
       export MARCH="generic32"
    fi

    if [ ${MARCH} = "riscv64" ] || [ ${MARCH} = "s390x"  ]; then
       export OS="linux64"
    fi

    if [ ${MARCH} != "armv4" ] && [ ${MARCH} != "generic32" ] && [ ${MARCH} != "s390x"  ]; then
       export EC_NISTP="enable-ec_nistp_64_gcc_128"
    fi    

    ./Configure ${OS}-${MARCH} \
        --prefix=/opt/openssl \
        --openssldir=/opt/openssl \
        no-ssl3 \
        no-docs \
        no-tests \
        no-filenames \
        no-legacy \
        no-shared \
        no-pinshared \
        ${EC_NISTP} \
        -static
    make -j ${BUILD_THREADS}
    make -j ${BUILD_THREADS} install_sw

    rm -rf /tmp/*
EOF



FROM target-base AS hiredis
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG CORE_BUILD_DEPS
ARG TARGET_BUILD_DEPS

COPY --from=sources /tmp/src/hiredis-src /tmp/src/hiredis-src
COPY --from=openssl /opt/openssl /opt/openssl

RUN <<EOF
    cd ./hiredis-src || exit

    export CFLAGS="${CFLAGS} -I/opt/openssl/include"
    export LDFLAGS="${LDFLAGS} -L/opt/openssl/lib"
    make -j ${BUILD_THREADS} USE_SSL=1 static
    mkdir -p /opt/hiredis/lib /opt/hiredis/include/hiredis
    cp -r *.h adapters /opt/hiredis/include/hiredis
    cp *.a /opt/hiredis/lib

    rm -rf /tmp/*
EOF



FROM target-base AS unbound
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]

ARG UNBOUND_BUILD_DEPS

COPY --from=sources /tmp/src/unbound-src /tmp/src/unbound-src
COPY --from=openssl /opt/openssl /opt/openssl
COPY --from=protobuf-c-build /opt/protobuf-c/bin /opt/protobuf-c/bin
COPY --from=protobuf-c-host /opt/protobuf-c /opt/protobuf-c
COPY --from=hiredis /opt/hiredis /opt/hiredis

RUN <<EOF
    . /etc/env

    cd ./unbound-src || exit
    xx-apk add --no-cache --virtual build-deps ${UNBOUND_BUILD_DEPS}

    addgroup -S _unbound
    adduser -S -s /dev/null -h /etc/unbound -G _unbound _unbound
    
    ./configure \
        PROTOC_C=/opt/protobuf-c/bin/protoc-c \
        --host=$(xx-clang --print-target-triple) \
        --prefix= \
        --with-chroot-dir=/var/chroot/unbound \
        --with-pidfile=/var/chroot/unbound/var/run/unbound.pid \
        --with-rootkey-file=/var/root.key \
        --with-rootcert-file=/var/icannbundle.pem \
        --with-pthreads \
        --with-username=_unbound \
        --with-ssl=/opt/openssl \
        --with-sysroot=${TARGET_SYSROOT} \
        --with-libevent=${TARGET_SYSROOT}usr \
        --with-libexpat=${TARGET_SYSROOT}usr \
        --with-libnghttp2=${TARGET_SYSROOT}usr \
        --with-libhiredis=/opt/hiredis \
        --with-libsodium=${TARGET_SYSROOT}usr \
        --with-protobuf-c=/opt/protobuf-c \
        --enable-dnstap \
        --enable-tfo-server \
        --enable-tfo-client \
        --enable-event-api \
        --enable-subnet \
        --enable-cachedb \
        --enable-dnscrypt \
        --disable-shared \
        --disable-static \
        --enable-fully-static
    make -j install
    mv /etc/unbound/unbound.conf /etc/unbound/unbound.conf.example

    rm -rf /tmp/*
EOF



FROM target-base AS ldns
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]

COPY --from=sources /tmp/src/ldns-src /tmp/src/ldns-src
COPY --from=openssl /opt/openssl /opt/openssl

RUN <<EOF
    . /etc/env
    cd ./ldns-src || exit
    
    libtoolize -ci
    autoreconf -fi
    ./configure \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/opt/ldns \
        --with-ssl=/opt/openssl \
        --with-drill \
        --disable-shared \
        --disable-static
    make -j ${BUILD_THREADS}
    make -j ${BUILD_THREADS} install-drill

    rm -rf /tmp/*
EOF



FROM scratch AS final
WORKDIR /
SHELL ["/bin/ash", "-cexo", "pipefail"]
ENV PATH="/bin:/sbin"
ARG ROOT_HINTS
ARG ICANN_CERT

ADD ${ROOT_HINTS} /var/chroot/unbound/var/unbound/root.hints
ADD ${ICANN_CERT} /var/chroot/unbound/var/unbound/icannbundle.pem

COPY ./data/etc/ /var/chroot/unbound/etc/
COPY --chmod=744 ./data/unbound.bootstrap /unbound

COPY --from=target-base /bin/busybox /lib/ld-musl*.so.1 /lib/
COPY --from=target-base /etc/ssl/certs/ /etc/ssl/certs/

COPY --from=openssl /opt/openssl/bin/openssl /bin/openssl

COPY --from=ldns /opt/ldns/bin/drill /bin/drill

COPY --from=unbound /sbin/unbound* /sbin/
COPY --from=unbound /etc/unbound/ /var/chroot/unbound/etc/unbound/
COPY --from=unbound /etc/passwd /etc/group /etc/

RUN ["/lib/busybox", "ln", "-s", "/lib/busybox", "/bin/ash"]
RUN <<EOF
    SH_CMDS="ln sed grep chmod chown mkdir cp awk uniq bc rm find nproc sh cat mv"
    
    for link in ${SH_CMDS}; do
        /lib/busybox ln -s /lib/busybox /bin/${link}
    done

    ln -s /var/chroot/unbound/var/unbound/ /var/unbound
    ln -s /var/chroot/unbound/etc/unbound/ /etc/unbound

    mkdir -p /var/chroot/unbound/var/run/
    mkdir -p /var/chroot/unbound/dev/
    cp -a /dev/random /dev/urandom /dev/null /var/chroot/unbound/dev/
EOF

EXPOSE 53/tcp
EXPOSE 53/udp

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 CMD ["/bin/drill", "@127.0.0.1", "cloudflare.com"]
ENTRYPOINT ["/unbound", "-d"]
CMD ["-c", "/etc/unbound/unbound.conf"]
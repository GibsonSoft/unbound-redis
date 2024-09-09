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
ARG CORE_BUILD_DEPS
ENV CORE_BUILD_DEPS=${CORE_BUILD_DEPS}

ENV CC="xx-clang"
ENV CXX="xx-clang++"
ENV CFLAGS="-fPIE -fPIC"
ENV CXXFLAGS="-fPIE -fPIC"
ENV LDFLAGS="-fuse-ld=lld -rtlib=compiler-rt -unwindlib=libunwind -static-pie -fpic"
ENV XX_CC_PREFER_LINKER=lld
ENV XX_CC_PREFER_STATIC_LINKER=lld

WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]

COPY --from=xx / /

RUN <<EOF
    apk --no-cache upgrade 
    apk add --no-cache ${CORE_BUILD_DEPS}
EOF



FROM scratch AS sources
WORKDIR /tmp/src
ARG OPENSSL_SHA256
ARG OPENSSL_SOURCE
ARG OPENSSL_VERSION
ARG OPENSSL_SOURCE_FILE=openssl-${OPENSSL_VERSION}.tar.gz
ARG OPENSSL_DOWNLOAD_URL=${OPENSSL_SOURCE}/${OPENSSL_SOURCE_FILE}
ADD --checksum=sha256:${OPENSSL_SHA256} ${OPENSSL_DOWNLOAD_URL} openssl.tar.gz
ADD ${OPENSSL_DOWNLOAD_URL}.asc openssl.tar.gz.asc

ARG UNBOUND_SHA256
ARG UNBOUND_SOURCE
ARG UNBOUND_VERSION
ARG UNBOUND_SOURCE_FILE=unbound-${UNBOUND_VERSION}.tar.gz
ARG UNBOUND_DOWNLOAD_URL=${UNBOUND_SOURCE}/${UNBOUND_SOURCE_FILE}
ADD --checksum=sha256:${UNBOUND_SHA256} ${UNBOUND_DOWNLOAD_URL} unbound.tar.gz

ARG LDNS_SHA256
ARG LDNS_SOURCE
ARG LDNS_VERSION
ARG LDNS_SOURCE_FILE=ldns-${LDNS_VERSION}.tar.gz
ARG LDNS_DOWNLOAD_URL=${LDNS_SOURCE}/${LDNS_SOURCE_FILE}
ADD --checksum=sha256:${LDNS_SHA256} ${LDNS_DOWNLOAD_URL} ldns.tar.gz

ARG PROTOBUF_GIT_COMMIT
ARG PROTOBUF_SOURCE
ADD --keep-git-dir=true ${PROTOBUF_SOURCE}#${PROTOBUF_GIT_COMMIT} ./protobuf-src

ARG PROTOBUFC_GIT_COMMIT
ARG PROTOBUFC_SOURCE
ADD --keep-git-dir=true ${PROTOBUFC_SOURCE}#${PROTOBUFC_GIT_COMMIT} ./protobuf-c-src



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
EOF



FROM core-base AS protobuf-build
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG TARGET_BUILD_DEPS
ARG PROTOBUF_BUILD_DEPS_BUILD

COPY --from=sources /tmp/src/protobuf-src /tmp/src/protobuf-src

RUN <<EOF
    cd ./protobuf-src || exit
    apk add --no-cache --virtual build-deps ${TARGET_BUILD_DEPS} ${PROTOBUF_BUILD_DEPS_BUILD}

    git submodule update --init --recursive

    cmake \
        -S. \
        -Bcmake-out \
        -DCMAKE_PREFIX=/opt/protobuf-build \
        -DZLIB_LIBRARY_RELEASE:FILEPATH=/lib/libz.a
    cd cmake-out || exit
    make -j protoc
EOF



FROM core-base AS protobuf-c-build
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG TARGET_BUILD_DEPS
ARG PROTOBUFC_BUILD_DEPS_BUILD

COPY --from=sources /tmp/src/protobuf-c-src /tmp/src/protobuf-c-src

RUN <<EOF
    apk add --no-cache --virtual build-deps ${TARGET_BUILD_DEPS} ${PROTOBUFC_BUILD_DEPS_BUILD}
    cd protobuf-c-src || exit

    ./configure --prefix=/opt/protobuf-c-host
    make -j install

    rm -rf /tmp/*
    apk del build-deps ${CORE_BUILD_DEPS}
EOF



FROM target-base AS protobuf-host
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG TARGET_BUILD_DEPS
ARG PROTOBUF_BUILD_DEPS_BUILD

COPY --from=sources /tmp/src/protobuf-src /tmp/src/protobuf-src

RUN <<EOF
    cd ./protobuf-src || exit
    apk add --no-cache --virtual build-deps ${TARGET_BUILD_DEPS} ${PROTOBUF_BUILD_DEPS_BUILD}

    git submodule update --init --recursive

    cmake \
        -S. \
        -Bcmake-out \
        -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=/opt/protobuf-build/bin \
        -DCMAKE_ARCHIVE_OUTPUT_DIRECTORY=/opt/protobuf-build/lib \
        -DZLIB_LIBRARY_RELEASE:FILEPATH=/lib/libz.a
    cd cmake-out || exit
    make -j libprotobuf libprotoc
EOF



FROM target-base AS protobuf-c-host
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG PROTOBUFC_BUILD_DEPS_BUILD
ARG PROTOBUFC_BUILD_DEPS_HOST

COPY --from=sources /tmp/src/protobuf-c.tar.gz /tmp/src/protobuf-c.tar.gz

RUN <<EOF
    . /etc/env

    mkdir ./protobuf-c-src
    apk add --no-cache --virtual build-deps-build ${PROTOBUFC_BUILD_DEPS_BUILD}
    xx-apk add --no-cache --virtual build-deps-host ${PROTOBUFC_BUILD_DEPS_HOST}
    tar -xzf protobuf-c.tar.gz --strip-components=1 -C ./protobuf-c-src
    cd protobuf-c-src || exit

    ./configure \
        PROTOC=/usr/bin/protoc \
        --with-sysroot=${TARGET_SYSROOT} \
        --prefix=/opt/protobuf-c-target \
        --host=${TARGET_TRIPLE} \
        --disable-protoc
    make -j install

    rm -rf /tmp/*
    xx-apk del build-deps-host ${TARGET_BUILD_DEPS}
    apk del build-deps-build ${CORE_BUILD_DEPS}
EOF



FROM target-base AS openssl
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]

ARG OPENSSL_BUILD_DEPS
ARG OPENSSL_OPGP_KEYS

COPY --from=sources /tmp/src/openssl.tar.gz /tmp/src/openssl.tar.gz.asc /tmp/src/

RUN <<EOF
    GNUPGHOME="$(mktemp -d)"
    export GNUPGHOME
    xx-apk add --no-cache --virtual build-deps ${OPENSSL_BUILD_DEPS}
    gpg --no-tty --keyserver keyserver.ubuntu.com --recv-keys ${OPENSSL_OPGP_KEYS}
    gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz
    mkdir ./openssl-src
    tar -xzf openssl.tar.gz --strip-components=1 -C ./openssl-src
    rm -f openssl.tar.gz openssl.tar.gz.asc
    cd ./openssl-src || exit

    ./Configure $(xx-info os)-$(xx-info march) \
        --prefix=/opt/openssl \
        --openssldir=/opt/openssl \
        no-ssl3 \
        no-docs \
        no-tests \
        no-filenames \
        no-legacy \
        no-shared \
        no-pinshared \
        enable-ec_nistp_64_gcc_128 \
        -static
    make -j
    make -j install_sw
    xx-apk del build-deps ${TARGET_BUILD_DEPS}
    apk del ${CORE_BUILD_DEPS}
    rm -rf /tmp/*
EOF



FROM target-base AS unbound
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]

ARG UNBOUND_BUILD_DEPS

COPY --from=sources /tmp/src/unbound.tar.gz /tmp/src/unbound.tar.gz
COPY --from=openssl /opt/openssl /opt/openssl
COPY --from=protobuf-c-host /opt/protobuf-c-host/bin /opt/protobuf-c-host/bin
COPY --from=protobuf-c-target /opt/protobuf-c-target /opt/protobuf-c-target

# Ignore SC2034, Needed to static-compile unbound/ldns, per https://github.com/NLnetLabs/unbound/issues/91#issuecomment-1707544943
# hadolint ignore=SC2034
RUN <<EOF
    . /etc/env

    mkdir ./unbound-src
    xx-apk add --no-cache --virtual build-deps ${UNBOUND_BUILD_DEPS}
    tar -xzf unbound.tar.gz --strip-components=1 -C ./unbound-src
    rm -f unbound.tar.gz
    cd ./unbound-src || exit
    addgroup -S _unbound
    adduser -S -s /dev/null -h /etc/unbound -G _unbound _unbound

    for file in $(find /opt/protobuf-c-host/bin/lib/* -type f); do
        symlinkpath=$(dirname $file | sed -e "s/\/opt\/protobuf-c-host\/bin\/lib\//\//")
        mkdir -p $symlinkpath
        cp -ns $file $symlinkpath/$(basename $file)
    done
    
    sed -e 's/@LDFLAGS@/@LDFLAGS@ -all-static/' -i Makefile.in
    ./configure \
        PROTOC_C=/opt/protobuf-c-host/bin/protoc-c \
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
        --with-libhiredis=${TARGET_SYSROOT}usr \
        --with-libsodium=${TARGET_SYSROOT}usr \
        --with-protobuf-c=/opt/protobuf-c-target \
        --enable-dnstap \
        --enable-tfo-server \
        --enable-tfo-client \
        --enable-event-api \
        --enable-subnet \
        --enable-cachedb \
        --enable-dnscrypt \
        --disable-flto \
        --disable-shared \
        --disable-static \
        --enable-fully-static
    make -j install
    mv /etc/unbound/unbound.conf /etc/unbound/unbound.conf.example
    xx-apk del build-deps ${TARGET_BUILD_DEPS}
    apk del ${CORE_BUILD_DEPS}
    rm -rf /tmp/*
EOF



FROM target-base AS ldns
WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG TARGETPLATFORM

ARG LDNS_BUILD_DEPS

COPY --from=sources /tmp/src/ldns.tar.gz /tmp/src/ldns.tar.gz
COPY --from=openssl /opt/openssl /opt/openssl

# Ignore SC2034, Needed to static-compile unbound/ldns, per https://github.com/NLnetLabs/unbound/issues/91#issuecomment-1707544943
# hadolint ignore=SC2034
RUN <<EOF
    mkdir ./ldns-src
    xx-apk add --no-cache --virtual build-deps ${LDNS_BUILD_DEPS}
    tar -xzf ldns.tar.gz --strip-components=1 -C ./ldns-src
    rm -f ldns.tar.gz
    cd ./ldns-src || exit
    
    sed -e 's/@LDFLAGS@/@LDFLAGS@ -all-static/' -i Makefile.in
    LIBS="-lpthread -lm"
    LDFLAGS="-Wl,-static -static -static-libgcc"
    ./configure \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/opt/ldns \
        --with-ssl=/opt/openssl \
        --with-drill \
        --disable-shared \
        --enable-static
    make -j
    make -j install
    xx-apk del build-deps ${TARGET_BUILD_DEPS}
    apk del ${CORE_BUILD_DEPS}
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
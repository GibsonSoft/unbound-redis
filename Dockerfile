# DL3018: We're specifying pkgs via ARGs + want latest security updates if possible. 
#         Will pin if there are any future issues.
# SC2086: Not needed in the majority of cases here (like apk calls that expect a list of pkgs, not a string).
# DL3020: A bug maybe? All these appear for ARGs with URLs in ADD statements.
# DL3003: Not splitting up RUNs just to cd.
# hadolint global ignore=DL3018,SC2086,DL3020,DL3003

ARG ALPINE_VERSION=latest

FROM --platform=${BUILDPLATFORM} alpine:${ALPINE_VERSION} AS base
ARG CORE_BUILD_DEPS
ENV CORE_BUILD_DEPS=${CORE_BUILD_DEPS}

WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]

RUN <<EOF
    apk --no-cache upgrade
    apk add --no-cache ${CORE_BUILD_DEPS}
EOF

FROM base AS openssl
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG TARGETOS
ARG TARGETARCH

ARG OPENSSL_BUILD_DEPS
ARG OPENSSL_OPGP_KEYS
ARG OPENSSL_SHA256
ARG OPENSSL_SOURCE
ARG OPENSSL_VERSION 

ARG OPENSSL_SOURCE_FILE=openssl-${OPENSSL_VERSION}.tar.gz
ARG OPENSSL_DOWNLOAD_URL=${OPENSSL_SOURCE}/${OPENSSL_SOURCE_FILE}

ADD --checksum=sha256:${OPENSSL_SHA256} ${OPENSSL_DOWNLOAD_URL} openssl.tar.gz
ADD ${OPENSSL_DOWNLOAD_URL}.asc openssl.tar.gz.asc

RUN <<EOF
    GNUPGHOME="$(mktemp -d)"
    export GNUPGHOME
    TARGET_BUILD="${TARGETOS}-${TARGETARCH}"
    OPENSSL_TARGET=$(echo ${TARGET_BUILD} | sed \
        -e "s/\<linux-amd64\>/linux-x86_64/" \
        -e "s/\<linux-arm\>/linux-armv4/" \
        -e "s/\<linux-arm64\>/linux-aarch64/" \
        -e "s/\<linux-ppc64le\>/linux-ppc64le/" \
        -e "s/\<linux-386\>/linux-generic32/" \
        -e "s/\<linux-riscv64\>/linux64-riscv64/" \
        -e "s/\<linux-s390x\>/linux32-s390x/")
    apk add --no-cache --virtual build-deps ${OPENSSL_BUILD_DEPS}
    gpg --no-tty --keyserver keyserver.ubuntu.com --recv-keys ${OPENSSL_OPGP_KEYS}
    gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz
    mkdir ./openssl-src
    tar -xzf openssl.tar.gz --strip-components=1 -C ./openssl-src
    rm -f openssl.tar.gz openssl.tar.gz.asc
    cd ./openssl-src || exit
    ./Configure ${OPENSSL_TARGET} \
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
    strip /opt/openssl/bin/openssl
    upx --best --lzma -q /opt/openssl/bin/openssl
    apk del build-deps ${CORE_BUILD_DEPS}
    rm -rf /tmp/*
EOF

FROM base AS unbound
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG TARGETPLATFORM

ARG UNBOUND_BUILD_DEPS
ARG UNBOUND_SHA256
ARG UNBOUND_SOURCE
ARG UNBOUND_VERSION
ARG UNBOUND_SOURCE_FILE=unbound-${UNBOUND_VERSION}.tar.gz
ARG UNBOUND_DOWNLOAD_URL=${UNBOUND_SOURCE}/${UNBOUND_SOURCE_FILE}

ADD --checksum=sha256:${UNBOUND_SHA256} ${UNBOUND_DOWNLOAD_URL} unbound.tar.gz
COPY --from=openssl /opt/openssl /opt/openssl

# Ignore SC2034, Needed to static-compile unbound/ldns, per https://github.com/NLnetLabs/unbound/issues/91#issuecomment-1707544943
# hadolint ignore=SC2034
RUN <<EOF
    UNBOUND_TARGET=$(echo ${TARGETPLATFORM} | sed \
        -e "s/\<linux\/amd64\>/x86_64-pc-linux-musl/" \
        -e "s/\<linux\/arm\/v6\>/armv6l-unknown-linux-musleabihf/" \
        -e "s/\<linux\/arm\/v7\>/armv7l-unknown-linux-musleabihf/" \
        -e "s/\<linux\/arm64\/v8\>/aarch64-unknown-linux-musl/" \
        -e "s/\<linux\/ppc64le\>/powerpc64le-unknown-linux-musl/" \
        -e "s/\<linux\/386\>/i386-pc-linux-musl/" \
        -e "s/\<linux\/riscv64\>/riscv64-unknown-linux-musl/" \
        -e "s/\<linux\/s390x\>/s390x-ibm-linux-musl/")
    mkdir ./unbound-src
    apk add --no-cache --virtual build-deps ${UNBOUND_BUILD_DEPS}
    tar -xzf unbound.tar.gz --strip-components=1 -C ./unbound-src
    rm -f unbound.tar.gz
    cd ./unbound-src || exit
    addgroup -S _unbound
    adduser -S -s /dev/null -h /etc/unbound -G _unbound _unbound
    
    sed -e 's/@LDFLAGS@/@LDFLAGS@ -all-static/' -i Makefile.in
    LIBS="-lpthread -lm"
    LDFLAGS="-Wl,-static -static -static-libgcc"
    ./configure \
        --host=${UNBOUND_TARGET} \
        --prefix= \
        --with-chroot-dir=/var/chroot/unbound \
        --with-pidfile=/var/chroot/unbound/var/run/unbound.pid \
        --with-rootkey-file=/var/root.key \
        --with-rootcert-file=/var/icannbundle.pem \
        --with-pthreads \
        --with-username=_unbound \
        --with-ssl=/opt/openssl \
        --with-libevent \
        --with-libnghttp2 \
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
        --enable-fully-static \
        --disable-rpath
    make -j install
    mv /etc/unbound/unbound.conf /etc/unbound/unbound.conf.example
    find /sbin -type f ! -name "unbound-control-setup" -name "unbound*" -exec strip '{}' \; -exec upx --best --lzma -q '{}' \;
    apk del build-deps ${CORE_BUILD_DEPS}
EOF

FROM base AS ldns
SHELL ["/bin/ash", "-cexo", "pipefail"]
ARG TARGETPLATFORM

ARG LDNS_BUILD_DEPS
ARG LDNS_SHA256
ARG LDNS_SOURCE
ARG LDNS_VERSION
ARG LDNS_SOURCE_FILE=ldns-${LDNS_VERSION}.tar.gz
ARG LDNS_DOWNLOAD_URL=${LDNS_SOURCE}/${LDNS_SOURCE_FILE}

ADD --checksum=sha256:${LDNS_SHA256} ${LDNS_DOWNLOAD_URL} ldns.tar.gz
COPY --from=openssl /opt/openssl /opt/openssl

# Ignore SC2034, Needed to static-compile unbound/ldns, per https://github.com/NLnetLabs/unbound/issues/91#issuecomment-1707544943
# hadolint ignore=SC2034
RUN <<EOF
    LDNS_TARGET=$(echo ${TARGETPLATFORM} | sed \
        -e "s/\<linux\/amd64\>/x86_64-pc-linux-musl/" \
        -e "s/\<linux\/arm\/v6\>/armv6l-unknown-linux-musleabihf/" \
        -e "s/\<linux\/arm\/v7\>/armv7l-unknown-linux-musleabihf/" \
        -e "s/\<linux\/arm64\/v8\>/aarch64-unknown-linux-musl/" \
        -e "s/\<linux\/ppc64le\>/powerpc64le-unknown-linux-musl/" \
        -e "s/\<linux\/386\>/i386-pc-linux-musl/" \
        -e "s/\<linux\/riscv64\>/riscv64-unknown-linux-musl/" \
        -e "s/\<linux\/s390x\>/s390x-ibm-linux-musl/")
    mkdir ./ldns-src
    apk add --no-cache --virtual build-deps ${LDNS_BUILD_DEPS}
    tar -xzf ldns.tar.gz --strip-components=1 -C ./ldns-src
    rm -f ldns.tar.gz
    cd ./ldns-src || exit
    
#   Needed to static-compile LDNS, per https://github.com/NLnetLabs/unbound/issues/91#issuecomment-1707544943
    sed -e 's/@LDFLAGS@/@LDFLAGS@ -all-static/' -i Makefile.in
    LIBS="-lpthread -lm"
    LDFLAGS="-Wl,-static -static -static-libgcc -no-pie"
    ./configure \
        --host=${LDNS_TARGET} \
        --prefix=/opt/ldns \
        --with-ssl=/opt/openssl \
        --with-drill \
        --disable-shared \
        --enable-static
    make -j
    make -j install
    strip /opt/ldns/bin/drill
    upx --best --lzma -q /opt/ldns/bin/drill
    apk del build-deps ${CORE_BUILD_DEPS}
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

COPY --from=base /bin/busybox /lib/ld-musl*.so.1 /lib/
COPY --from=base /etc/ssl/certs/ /etc/ssl/certs/

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
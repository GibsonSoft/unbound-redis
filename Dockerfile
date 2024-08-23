ARG ALPINE_VERSION=latest

FROM alpine:${ALPINE_VERSION} AS openssl
ARG OPENSSL_BUILD_DEPS
ARG OPENSSL_OPGP_1
ARG OPENSSL_OPGP_2
ARG OPENSSL_OPGP_3
ARG OPENSSL_OPGP_4
ARG OPENSSL_OPGP_5
ARG OPENSSL_SHA256
ARG OPENSSL_SOURCE
ARG OPENSSL_VERSION 

ARG OPENSSL_SOURCE_FILE=openssl-${OPENSSL_VERSION}.tar.gz
ARG OPENSSL_DOWNLOAD_URL=${OPENSSL_SOURCE}/${OPENSSL_SOURCE_FILE}

LABEL maintainer="Matthew Vance"

WORKDIR /tmp/src

SHELL ["/bin/ash", "-cexo", "pipefail"]

# Ignore DL3018, we're specifying pkgs via env
# Ignore SC2086, need to leave out double quotes to bring in deps via env
# Ignore DL3003, switching via WORKDIR explodes image size due additial RUNs
# hadolint ignore=DL3018,SC2086,DL3003
RUN <<EOF
    # shellcheck source=/dev/null
    apk update
    apk add --no-cache --virtual build-deps ${OPENSSL_BUILD_DEPS}
    curl -L "${OPENSSL_DOWNLOAD_URL}" -o openssl.tar.gz
    echo "${OPENSSL_SHA256} ./openssl.tar.gz" | sha256sum -c -
    curl -L "${OPENSSL_DOWNLOAD_URL}.asc" -o openssl.tar.gz.asc
    GNUPGHOME="$(mktemp -d)"
    export GNUPGHOME
    gpg --no-tty --keyserver keyserver.ubuntu.com --recv-keys \
        "${OPENSSL_OPGP_1}" \
        "${OPENSSL_OPGP_2}" \
        "${OPENSSL_OPGP_3}" \
        "${OPENSSL_OPGP_4}" \
        "${OPENSSL_OPGP_5}"
    gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz
    mkdir ./openssl-src
    tar -xzf openssl.tar.gz --strip-components=1 -C ./openssl-src
    cd /tmp/src/openssl-src || exit
    ./config \
        --prefix=/opt/openssl \
        --openssldir=/opt/openssl \
        no-weak-ssl-ciphers \
        no-ssl3 \
        no-shared \
        enable-ec_nistp_64_gcc_128 \
        -DOPENSSL_NO_HEARTBEATS \
        -fstack-protector-strong
    make depend
    nproc | xargs -I % make -j%
    make install_sw
    apk del build-deps
    rm -rf \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*
EOF

FROM alpine:${ALPINE_VERSION} AS unbound
ARG UNBOUND_BUILD_DEPS
ARG UNBOUND_RUNTIME_DEPS
ARG UNBOUND_SHA256
ARG UNBOUND_SOURCE
ARG UNBOUND_VERSION

ARG UNBOUND_SOURCE_FILE=unbound-${UNBOUND_VERSION}.tar.gz
ARG UNBOUND_DOWNLOAD_URL=${UNBOUND_SOURCE}/${UNBOUND_SOURCE_FILE}

LABEL maintainer="Matthew Vance"

WORKDIR /tmp/src

COPY --from=openssl /opt/openssl /opt/openssl

SHELL ["/bin/ash", "-cexo", "pipefail"]

# Ignore DL3018, we're specifying pkgs via env
# Ignore SC2086, need to leave out double quotes to bring in deps via env
# Ignore DL3003, switching via WORKDIR explodes image size due additial RUNs
# hadolint ignore=DL3018,SC2086,DL3003
RUN <<EOF
    # shellcheck source=/dev/null
    apk add --no-cache --virtual build-deps ${UNBOUND_BUILD_DEPS} 
    apk add --no-cache ${UNBOUND_RUNTIME_DEPS}
    curl -sSL "${UNBOUND_DOWNLOAD_URL}" -o unbound.tar.gz
    echo "${UNBOUND_SHA256} ./unbound.tar.gz" | sha256sum -c -
    mkdir ./unbound-src
    tar -xzf unbound.tar.gz --strip-components=1 -C ./unbound-src
    rm -f unbound.tar.gz
    cd /tmp/src/unbound-src || exit
    adduser -D -s /dev/null -h /etc _unbound _unbound
    ./configure \
        --disable-dependency-tracking \
        --prefix=/opt/unbound \
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
        --enable-dnscrypt
    make install
    mv /opt/unbound/etc/unbound/unbound.conf /opt/unbound/etc/unbound/unbound.conf.example
    apk del build-deps
    rm -rf \
        /opt/unbound/share/man \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*
EOF

COPY data/ /

RUN chmod +x /unbound.sh

WORKDIR /opt/unbound/

ENV PATH=/opt/unbound/sbin:"$PATH"

LABEL org.opencontainers.image.version=${UNBOUND_VERSION} \
      org.opencontainers.image.title="mvance/unbound" \
      org.opencontainers.image.description="a validating, recursive, and caching DNS resolver" \
      org.opencontainers.image.url="https://github.com/MatthewVance/unbound-docker" \
      org.opencontainers.image.vendor="Matthew Vance" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/MatthewVance/unbound-docker"

EXPOSE 53/tcp
EXPOSE 53/udp

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 CMD drill @127.0.0.1 cloudflare.com || exit 1

CMD ["/unbound.sh"]

ARG ALPINE_VERSION=latest

FROM alpine:${ALPINE_VERSION} as base
ARG OPENSSL_BUILD_DEPS
ARG UNBOUND_BUILD_DEPS
ARG UNBOUND_RUNTIME_DEPS

WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]

# Ignore DL3018, we're specifying pkgs via env
# Ignore SC2086, need to leave out double quotes to bring in deps via env
# hadolint ignore=DL3018,SC2086
RUN <<EOF
    apk update
    apk add --no-cache --virtual build-deps ${BUILD_DEPS}
    apk add --no-cache ${RUNTIME_DEPS}
EOF

FROM base AS openssl
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

# Ignore DL3020, using ADD to grab remote file. Cannot do with COPY
# hadolint ignore=DL3020
ADD --checksum=sha256:${OPENSSL_SHA256} ${OPENSSL_DOWNLOAD_URL} openssl.tar.gz
# hadolint ignore=DL3020
ADD ${OPENSSL_DOWNLOAD_URL}.asc openssl.tar.gz.asc

# Ignore DL3003, only need to cd for this RUN
# hadolint ignore=DL3003
RUN <<EOF
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
    rm -f openssl.tar.gz openssl.tar.gz.asc
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
    rm -rf \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*
EOF

FROM base AS unbound

ARG UNBOUND_SHA256
ARG UNBOUND_SOURCE
ARG UNBOUND_VERSION

ARG UNBOUND_SOURCE_FILE=unbound-${UNBOUND_VERSION}.tar.gz
ARG UNBOUND_DOWNLOAD_URL=${UNBOUND_SOURCE}/${UNBOUND_SOURCE_FILE}

LABEL maintainer="Matthew Vance"

WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]

COPY --from=openssl /opt/openssl /opt/openssl

# Ignore DL3020, using ADD to grab remote file. Cannot do with COPY
# hadolint ignore=DL3020
ADD --checksum=sha256:${UNBOUND_SHA256} ${UNBOUND_DOWNLOAD_URL} unbound.tar.gz

# Ignore DL3003, only need to cd for this RUN
# hadolint ignore=DL3003
RUN <<EOF
    # shellcheck source=/dev/null
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
    rm -rf \
        /opt/unbound/share/man \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*
EOF

FROM base as final

COPY --from=openssl /opt/openssl /opt/openssl
COPY --from=unbound /opt/unbound /opt/unbound
COPY data/ /

RUN <<EOF
    chmod +x /unbound.sh
    apk del build-deps
    adduser -D -s /dev/null -h /etc _unbound _unbound
EOF

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

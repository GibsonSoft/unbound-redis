ARG ALPINE_IMAGE_VERSION=3.20.2

FROM alpine:$ALPINE_IMAGE_VERSION AS openssl
LABEL maintainer="Matthew Vance"

WORKDIR /tmp/src
COPY env/openssl.env openssl.env

SHELL ["/bin/ash", "-cexo", "pipefail"]

# Ignore DL3018, we're specifying pkgs via env
# Ignore SC2086, need to leave out double quotes to bring in deps via env
# hadolint ignore=DL3018,SC2086
RUN <<EOF
    # shellcheck source=/dev/null
    set -a && . ./openssl.env && set +a
    apk update
    apk add --no-cache --virtual build-deps ${BUILD_DEPS_OPENSSL}
    curl -L "${SOURCE_OPENSSL}""${VERSION_OPENSSL}".tar.gz -o openssl.tar.gz
    echo "${SHA256_OPENSSL} ./openssl.tar.gz" | sha256sum -c -
    curl -L "${SOURCE_OPENSSL}""${VERSION_OPENSSL}".tar.gz.asc -o openssl.tar.gz.asc
    GNUPGHOME="$(mktemp -d)"
    export GNUPGHOME
    gpg --no-tty --keyserver keyserver.ubuntu.com --recv-keys "${OPGP_OPENSSL_1}" "${OPGP_OPENSSL_2}" "${OPGP_OPENSSL_3}" "${OPGP_OPENSSL_4}" "${OPGP_OPENSSL_5}"
    gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz
    mkdir ./openssl-src
    tar -xzf openssl.tar.gz --strip-components=1 -C ./openssl-src
EOF
 
WORKDIR /tmp/src/openssl-src

RUN <<EOF
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

FROM alpine:$ALPINE_IMAGE_VERSION AS unbound
LABEL maintainer="Matthew Vance"

WORKDIR /tmp/src
COPY env/unbound.env unbound.env

COPY --from=openssl /opt/openssl /opt/openssl

SHELL ["/bin/ash", "-cexo", "pipefail"]

# Ignore DL3018, we're specifying pkgs via env
# Ignore SC2086, need to leave out double quotes to bring in deps via env
# hadolint ignore=DL3018,SC2086
RUN <<EOF
    # shellcheck source=/dev/null
    set -a && . ./unbound.env && set +a
    apk add --no-cache --virtual build-deps ${BUILD_DEPS_UNBOUND} 
    apk add --no-cache ${RUNTIME_DEPS_UNBOUND}
    curl -sSL $UNBOUND_DOWNLOAD_URL -o unbound.tar.gz
    echo "${UNBOUND_SHA256} *unbound.tar.gz" | sha256sum -c -
    mkdir ./unbound-src
    tar -xzf unbound.tar.gz --strip-components=1 -C ./unbound-src
    rm -f unbound.tar.gz
EOF

WORKDIR /tmp/src/unbound-src

RUN <<EOF
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
        --enable-subnet
    make install
    mv /opt/unbound/etc/unbound/unbound.conf /opt/unbound/etc/unbound/unbound.conf.example
    apk del build-deps
    rm -rf \
        /opt/unbound/share/man \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*
EOF

FROM alpine:$ALPINE_IMAGE_VERSION AS final
LABEL maintainer="Matthew Vance"

WORKDIR /tmp/src

COPY --from=unbound /opt /opt

RUN set -x && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      bsdmainutils \
      ca-certificates \
      ldnsutils \
      libevent-2.1-7 \
      libnghttp2-14 \
      libexpat1 \
      libprotobuf-c1 && \
    groupadd _unbound && \
    useradd -g _unbound -s /dev/null -d /etc _unbound && \
    apt-get purge -y --auto-remove \
      $build_deps && \
    rm -rf \
        /opt/unbound/share/man \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*

COPY data/ /

RUN chmod +x /unbound.sh

WORKDIR /opt/unbound/

ENV PATH /opt/unbound/sbin:"$PATH"

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

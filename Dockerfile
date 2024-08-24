ARG ALPINE_VERSION=latest

FROM alpine:${ALPINE_VERSION} AS base
ARG CORE_BUILD_DEPS
ENV CORE_BUILD_DEPS=${CORE_BUILD_DEPS}

WORKDIR /tmp/src
SHELL ["/bin/ash", "-cexo", "pipefail"]

# Ignore DL3018, we're specifying pkgs via env
# Ignore SC2086, need to leave out double quotes to bring in deps via env
# hadolint ignore=DL3018,SC2086
RUN <<EOF
    apk update
    apk add --no-cache ${CORE_BUILD_DEPS}
EOF

FROM base AS openssl
ARG OPENSSL_BUILD_DEPS
ARG OPENSSL_OPGP_KEYS
ARG OPENSSL_SHA256
ARG OPENSSL_SOURCE
ARG OPENSSL_VERSION 

ARG OPENSSL_SOURCE_FILE=openssl-${OPENSSL_VERSION}.tar.gz
ARG OPENSSL_DOWNLOAD_URL=${OPENSSL_SOURCE}/${OPENSSL_SOURCE_FILE}

LABEL maintainer="Matthew Vance"

# Ignore DL3020, using ADD to grab remote file. Cannot do with COPY
# hadolint ignore=DL3020
ADD --checksum=sha256:${OPENSSL_SHA256} ${OPENSSL_DOWNLOAD_URL} openssl.tar.gz
# hadolint ignore=DL3020
ADD ${OPENSSL_DOWNLOAD_URL}.asc openssl.tar.gz.asc

# Ignore DL3018, we're specifying pkgs via env
# Ignore SC2086, need to leave out double quotes to bring in deps via env
# Ignore DL3003, only need to cd for this RUN
# hadolint ignore=DL3003,DL3018,SC2086
RUN <<EOF
    GNUPGHOME="$(mktemp -d)"
    export GNUPGHOME
    apk add --no-cache --virtual build-deps ${OPENSSL_BUILD_DEPS}
    gpg --no-tty --keyserver keyserver.ubuntu.com --recv-keys ${OPENSSL_OPGP_KEYS}
    gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz
    mkdir ./openssl-src
    tar -xzf openssl.tar.gz --strip-components=1 -C ./openssl-src
    rm -f openssl.tar.gz openssl.tar.gz.asc
    cd ./openssl-src || exit
    ./Configure \
        --prefix=/opt/openssl \
        --openssldir=/opt/openssl \
        no-ssl3 \
        enable-ec_nistp_64_gcc_128 \
        -static
    make -j
    make -j install_sw
    strip /opt/openssl/bin/openssl
    apk del build-deps ${CORE_BUILD_DEPS}
EOF

FROM base AS unbound
ARG UNBOUND_BUILD_DEPS
ARG UNBOUND_SHA256
ARG UNBOUND_SOURCE
ARG UNBOUND_VERSION

ARG UNBOUND_SOURCE_FILE=unbound-${UNBOUND_VERSION}.tar.gz
ARG UNBOUND_DOWNLOAD_URL=${UNBOUND_SOURCE}/${UNBOUND_SOURCE_FILE}

LABEL maintainer="Matthew Vance"

COPY --from=openssl /opt/openssl /opt/openssl

# Ignore DL3020, using ADD to grab remote file. Cannot do with COPY
# hadolint ignore=DL3020
ADD --checksum=sha256:${UNBOUND_SHA256} ${UNBOUND_DOWNLOAD_URL} unbound.tar.gz

# Ignore DL3018, we're specifying pkgs via env
# Ignore SC2086, need to leave out double quotes to bring in deps via env
# Ignore DL3003, only need to cd for this RUN
# Ignore SC2034, Needed to static-compile unbound, per https://github.com/NLnetLabs/unbound/issues/91#issuecomment-1707544943
# hadolint ignore=DL3018,SC2086,DL3003,SC2034
RUN <<EOF
    mkdir ./unbound-src
    apk add --no-cache --virtual build-deps ${UNBOUND_BUILD_DEPS}
    tar -xzf unbound.tar.gz --strip-components=1 -C ./unbound-src
    rm -f unbound.tar.gz
    cd ./unbound-src || exit
    adduser -D -s /dev/null -h /etc _unbound _unbound
    
#   Needed to static-compile unbound, per https://github.com/NLnetLabs/unbound/issues/91#issuecomment-1707544943
    sed -e 's/@LDFLAGS@/@LDFLAGS@ -all-static/' -i Makefile.in
    LIBS="-lpthread -lm"
    LDFLAGS="-Wl,-static -static -static-libgcc -no-pie"
    ./configure \
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
        --enable-dnscrypt \
        --disable-flto \
        --disable-shared \
        --enable-fully-static
    make -j install
    mv /opt/unbound/etc/unbound/unbound.conf /opt/unbound/etc/unbound/unbound.conf.example
    strip /opt/unbound/sbin/unbound
    strip /opt/unbound/sbin/unbound-anchor
    strip /opt/unbound/sbin/unbound-checkconf
    strip /opt/unbound/sbin/unbound-control
    strip /opt/unbound/sbin/unbound-host
    rm -rf /opt/unbound/share/man
    apk del build-deps ${CORE_BUILD_DEPS}
EOF

FROM base AS ldns
ARG LDNS_BUILD_DEPS
ARG LDNS_SHA256
ARG LDNS_SOURCE
ARG LDNS_VERSION

ARG LDNS_SOURCE_FILE=ldns-${LDNS_VERSION}.tar.gz
ARG LDNS_DOWNLOAD_URL=${LDNS_SOURCE}/${LDNS_SOURCE_FILE}

COPY --from=openssl /opt/openssl /opt/openssl

# Ignore DL3020, using ADD to grab remote file. Cannot do with COPY
# hadolint ignore=DL3020
ADD --checksum=sha256:${LDNS_SHA256} ${LDNS_DOWNLOAD_URL} ldns.tar.gz

# Ignore DL3018, we're specifying pkgs via env
# Ignore SC2086, need to leave out double quotes to bring in deps via env
# Ignore DL3003, only need to cd for this RUN
# Ignore SC2034, Needed to static-compile unbound, per https://github.com/NLnetLabs/unbound/issues/91#issuecomment-1707544943
# hadolint ignore=DL3018,SC2086,DL3003,SC2034
RUN <<EOF
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
        --prefix=/opt/ldns \
        --with-ssl=/opt/openssl \
        --with-drill \
        --disable-shared \
        --enable-static
    make -j
    make -j install
    strip /opt/ldns/bin/drill
    apk del build-deps ${CORE_BUILD_DEPS}
EOF

FROM scratch as final
WORKDIR /
SHELL ["/bin/sh", "-cexo", "pipefail"]

COPY --from=base /bin/ /bin/
COPY --from=base /usr/bin/ /usr/bin/
COPY --from=base /lib/ld-musl*.so.1 /lib/
COPY --from=base /etc/ssl/certs/ /etc/ssl/certs/
COPY --from=ldns /opt/ldns/bin/drill /opt/drill/bin/drill
COPY --from=unbound /opt/unbound/sbin/ /opt/unbound/sbin/
COPY --from=unbound /opt/unbound/etc/ /opt/unbound/etc/
COPY --from=unbound /etc/passwd /etc/group /etc/
COPY data/ /

ENV PATH=/opt/unbound/sbin:/opt/drill/bin:/bin:/usr/bin

RUN chmod +x /unbound.sh

EXPOSE 53/tcp
EXPOSE 53/udp

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 CMD drill @127.0.0.1 cloudflare.com || exit 1
CMD ["/unbound.sh"]






# FROM base AS final2
# ARG RUNTIME_DEPS

# COPY --from=unbound /opt/unbound /opt/unbound
# COPY --from=ldns /opt/ldns/bin/drill /opt/ldns/bin/drill

# COPY data/ /

# Ignore DL3018, we're specifying pkgs via env
# Ignore SC2086, need to leave out double quotes to bring in deps via env
# hadolint ignore=DL3018,SC2086
# RUN <<EOF
#     chmod +x /unbound.sh
#     apk del ${CORE_BUILD_DEPS}
#     adduser -D -s /dev/null -h /etc _unbound _unbound
# EOF

# WORKDIR /opt/unbound/

# ENV PATH=/opt/unbound/sbin:/opt/ldns/bin:"$PATH"

# LABEL org.opencontainers.image.version=${UNBOUND_VERSION} \
#       org.opencontainers.image.title="mvance/unbound" \
#       org.opencontainers.image.description="a validating, recursive, and caching DNS resolver" \
#       org.opencontainers.image.url="https://github.com/MatthewVance/unbound-docker" \
#       org.opencontainers.image.vendor="Matthew Vance" \
#       org.opencontainers.image.licenses="MIT" \
#       org.opencontainers.image.source="https://github.com/MatthewVance/unbound-docker"

# EXPOSE 53/tcp
# EXPOSE 53/udp

# HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 CMD drill @127.0.0.1 cloudflare.com || exit 1

# CMD ["/unbound.sh"]

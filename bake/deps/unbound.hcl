target "default" {
    args = {
        UNBOUND_BUILD_DEPS = yamldecode(<<EOF
            deps: >
              expat-dev
              expat-static
              libevent-dev
              libevent-static
              libsodium-dev
              libsodium-static
              nghttp2-dev
              nghttp2-static
        EOF
        ).deps
    }
}
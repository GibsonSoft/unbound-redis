target "default" {
    args = {
        PROTOBUF_BUILD_DEPS_BUILD = yamldecode(<<EOF
            deps: >
              zlib-dev
              zlib-static
        EOF
        ).deps,
        PROTOBUF_BUILD_DEPS_HOST = yamldecode(<<EOF
            deps: >
              zlib-dev
              zlib-static
        EOF
        ).deps
    }
}
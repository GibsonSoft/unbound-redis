target "default" {
    args = {
        PROTOBUF_BUILD_DEPS_BUILD = join(" ", [
            "zlib-dev",
            "zlib-static"
        ]),
        PROTOBUF_BUILD_DEPS_HOST = join(" ", [
            "zlib-dev",
            "zlib-static"
        ])
    }
}
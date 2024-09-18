target "default" {
    args = {
        UNBOUND_BUILD_DEPS = join(" ", [
            "expat-dev",
            "expat-static",
            "libevent-dev",
            "libevent-static",
            "libsodium-dev",
            "libsodium-static",
            "nghttp2-dev",
            "nghttp2-static"
        ])
    }
}
target "default" {
    args = {
        CORE_BUILD_DEPS = join(" ", [
            "clang",
            "llvm",
            "make",
            "cmake",
            "git",
            "perl",
            "file",
            "upx",
            "gnupg",
            "flex",
            "bison",
            "pkgconf",
            "automake",
            "autoconf",
            "libtool"
        ]),
        CORE_BUILD_DEPS_EDGE = join(" ", [
            "lld"
        ])
    }
}
target "default" {
    args = {
        CORE_BUILD_DEPS = join(" ", [
            "clang",
            "lld@edge=~18.1",
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
        ])
    }
}
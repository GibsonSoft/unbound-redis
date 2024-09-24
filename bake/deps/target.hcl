target "default" {
    args = {
        TARGET_BUILD_DEPS = join(" ", [
            "g++",
            "compiler-rt",
            "llvm-libunwind",
            "llvm-libunwind-static",
            "musl-dev",
            "linux-headers",
            "busybox"
        ]),
        TARGET_BUILD_DEPS_EDGE = join(" ", [
            
        ])
    }
}
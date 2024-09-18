target "default" {
    args = {
        TARGET_BUILD_DEPS = yamldecode(<<EOF
            deps: >
              g++
              llvm
              compiler-rt
              llvm-libunwind
              llvm-libunwind-static
              musl-dev
              linux-headers
              busybox
        EOF
        ).deps
    }
}
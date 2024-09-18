target "default" {
    args = {
        CORE_BUILD_DEPS = yamldecode(<<EOF
            deps: >
              clang
              lld@edge=~18.1
              make
              cmake
              git
              perl
              file
              upx
              gnupg
              flex
              bison
              pkgconf
              automake
              autoconf
              libtool
        EOF
        ).deps
    }
}
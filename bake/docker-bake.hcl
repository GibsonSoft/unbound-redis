target "default" {
    dockerfile = "Dockerfile"
    context = ".."
    target = "final"
    platforms = [
        "linux/amd64",
        "linux/arm64/v8",
        "linux/ppc64le",
        "linux/arm/v6",
        "linux/arm/v7",
        "linux/386",
        "linux/riscv64",
        "linux/s390x"
    ]
}
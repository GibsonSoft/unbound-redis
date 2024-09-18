target "default" {
    args = {
        # Protobuf-C 1.5.0 currently doesn't cooperate with Protobuf > 25
        # Upgrade both Protobuf and Protobuf-C once PC (officially) releases an update with fixes
        PROTOBUF_GIT_COMMIT = "e915ce24b3d43c0fffcbf847354288c07dda1de0",
        PROTOBUF_SOURCE = "https://github.com/protocolbuffers/protobuf.git",
        PROTOBUF_VERSION = "25.4"
    }
}
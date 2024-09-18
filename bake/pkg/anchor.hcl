target "default" {
    args = {
        ROOT_HINTS = "https://www.internic.net/domain/named.root",
        ICANN_CERT = "https://data.iana.org/root-anchors/icannbundle.pem"
    }
}
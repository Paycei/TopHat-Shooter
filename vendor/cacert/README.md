# Root certificates

`cacert.pem` is Mozilla's store of trusted root certificates, as curl publishes
it at https://curl.se/docs/caextract.html (certificate data from Mozilla as of
2026-09-25; SHA-256 `a41b5d356aea97a529fe27e0f7316d2f9d946d75927476cf9cf1b90637d00505`,
checked against curl's published `cacert.pem.sha256`). It is unmodified.

It is under the Mozilla Public License 2.0. Its source is Mozilla's
`certdata.txt`, linked from the file's header. The game embeds it
(`src/network/tls.nim`) to check the servers the mod Marketplace downloads from.

To update, download https://curl.se/ca/cacert.pem and check it against
https://curl.se/ca/cacert.pem.sha256.

# bearssl, vendored

[status-im/nim-bearssl](https://github.com/status-im/nim-bearssl) 0.3.0, commit
`2c919a5e94768c7b8d977257bef1981ea2f5699c`, with BearSSL's C sources (its
`bearssl/csources` submodule, commit `7bea48e5e850ab4cafbe68d3765cdaba13a86d6f`) trimmed to
`inc/`, `src/`, `tools/`, `LICENSE.txt` and `README.txt`. Licenses: `LICENSE-APACHEv2` /
`LICENSE-MIT` (the wrapper), `bearssl/csources/LICENSE.txt` (BearSSL, MIT; `help licenses`
prints it), Mozilla's roots in `bearssl/certs` (MPL-2.0).

It is vendored, not a Nimble dependency, because the package cannot be cross-compiled from a
Windows host (`nimble androidLib`): it builds its paths with the *target's* separator, which
cannot split a Windows path, and at build time it copies and patches its C sources into the
nimcache. Changes from upstream:

- `bearssl/csources.patch` (upstream's UB fixes) is already applied to `bearssl/csources`.
- `bearssl/abi/csources.nim`: the nimcache copy is gone (`patched` is this tree), and paths
  are built with `/` from `currentSourcePath` split on both `/` and `\`.
- `bearssl/secp256r1_verify.nim`: the same separator fix.
- `bearssl/abi/csources_patch.nims` (the copy-and-patch script) is removed, as are the
  upstream tests and tooling.

To update: take the new release, apply `csources.patch` inside `bearssl/csources`
(`git apply`), and redo the edits above.

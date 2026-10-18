## TLS for the mod marketplace's downloads: the vendored BearSSL
## (vendor/bearssl, see its LICENSE.txt; the commit is in its VERSION.txt),
## compiled straight into the executable like Lua (no DLL), checking servers
## against Mozilla's root certificates (vendor/cacert, MPL-2.0), embedded too.
## A TLS 1.2 client and nothing else: https.nim is its one user.
##
## It runs on the marketplace's worker thread, so nothing here touches a
## global, t(), the mod runtime or a {.moddable.} proc. BearSSL never calls
## back into Nim while moving data: the record loop that carries its buffers
## through the socket (BearSSL's br_sslio "run until" loop) is written here,
## so no Nim exception can cross a C frame. Every wait is cut into 200 ms
## slices, so a cancel or a stalled server is noticed.

import std/[macros, net, nativesockets, atomics, os, strutils]

const
  BearDir = currentSourcePath().parentDir.parentDir.parentDir / "vendor" / "bearssl"
  BearInc = BearDir / "inc"
  BearSrc = BearDir / "src"

# Only inc/ (bearssl*.h and nothing else) goes on the global include path:
# src/ holds a config.h of its own that must never shadow raylib's, so it is
# passed to BearSSL's own files only.
{.passC: "-I\"" & BearInc & "\"".}
const BearCFlags = "-I\"" & BearInc & "\" -I\"" & BearSrc & "\"" &
  # clang-cl is both clang and MSVC to BearSSL's inner.h, which then includes
  # clang's <cpuid.h> and MSVC's <intrin.h> together (they clash on __cpuid):
  # it is told the compiler is clang only (a documented override).
  (when defined(clang_cl): " -DBR_MSC=0" else: "")

const BearSources = [
  "aes_ct", "aes_ct_cbcdec", "aes_ct_cbcenc", "aes_ct_ctr", "aes_ct_ctrcbc", "aes_ct_dec",
  "aes_ct_enc", "aes_ct64", "aes_ct64_cbcdec", "aes_ct64_cbcenc", "aes_ct64_ctr",
  "aes_ct64_ctrcbc", "aes_ct64_dec", "aes_ct64_enc", "aes_x86ni", "aes_x86ni_cbcdec",
  "aes_x86ni_cbcenc", "aes_x86ni_ctr", "aes_x86ni_ctrcbc", "ccm", "ccopy", "chacha20_ct",
  "chacha20_sse2", "dec32be", "dec32le", "dec64be", "des_ct", "des_ct_cbcdec", "des_ct_cbcenc",
  "des_support", "ec_all_m15", "ec_all_m31", "ec_c25519_m15", "ec_c25519_m64", "ec_p256_m15",
  "ec_p256_m64", "ec_prime_i15", "ec_prime_i31", "ec_secp256r1", "ec_secp384r1", "ec_secp521r1",
  "ecdsa_atr", "ecdsa_i15_bits", "ecdsa_i15_vrfy_asn1", "ecdsa_i15_vrfy_raw", "ecdsa_i31_bits",
  "ecdsa_i31_vrfy_asn1", "ecdsa_i31_vrfy_raw", "enc32be", "enc32le", "enc64be", "ghash_ctmul32",
  "ghash_ctmul64", "ghash_pclmul", "hmac", "hmac_ct", "hmac_drbg", "i15_add", "i15_bitlen",
  "i15_decmod", "i15_decode", "i15_encode", "i15_fmont", "i15_iszero", "i15_modpow",
  "i15_modpow2", "i15_montmul", "i15_muladd", "i15_ninv15", "i15_rshift", "i15_sub", "i15_tmont",
  "i31_add", "i31_bitlen", "i31_decmod", "i31_decode", "i31_encode", "i31_fmont", "i31_iszero",
  "i31_modpow", "i31_montmul", "i31_muladd", "i31_ninv31", "i31_rshift", "i31_sub", "i31_tmont",
  "i32_div32", "i62_modpow2", "md5", "multihash", "poly1305_ctmul", "poly1305_ctmul32",
  "poly1305_ctmulq", "prf", "prf_md5sha1", "prf_sha256", "prf_sha384", "rsa_default_pkcs1_vrfy",
  "rsa_default_pub", "rsa_i15_pkcs1_vrfy", "rsa_i15_pub", "rsa_i62_pkcs1_vrfy", "rsa_i62_pub",
  "rsa_pkcs1_sig_unpad", "sha1", "sha2big", "sha2small", "ssl_client",
  "ssl_client_default_rsapub", "ssl_client_full", "ssl_engine", "ssl_engine_default_aescbc",
  "ssl_engine_default_aesccm", "ssl_engine_default_aesgcm", "ssl_engine_default_chapol",
  "ssl_engine_default_descbc", "ssl_engine_default_ecdsa", "ssl_engine_default_rsavrfy",
  "ssl_hs_client", "ssl_rec_cbc", "ssl_rec_ccm", "ssl_rec_chapol", "ssl_rec_gcm", "sysrng",
  "x509_decoder", "x509_minimal"]
  ## The BearSSL files a TLS client links (br_ssl_client_init_full, the engine
  ## and the X.509 decoder), on 64-bit targets and on ones without 128-bit
  ## multiplies, AES-NI or SSE2: measured by linking against all of BearSSL as
  ## a static archive (gcc -Wl,-Map lists the members it took). Not all 294:
  ## the release link puts every object on clang-cl's command line, which
  ## Windows caps at 32K characters. A BearSSL update that moves code shows up
  ## as an undefined br_* symbol at link time: add the file that defines it.

macro compileBearSSL() =
  ## One {.compile.} per file of BearSources, with BearSSL's include paths.
  ## Object files are named after the source, so two of one name would clash.
  result = newStmtList()
  var found: seq[string]
  for path in walkDirRec(BearSrc):
    let name = extractFilename(path)
    if not name.endsWith(".c") or name[0 ..< ^2] notin BearSources: continue
    if name in found: error("vendor/bearssl has two sources named " & name)
    found.add(name)
    result.add(parseStmt("{.compile(" & path.replace('\\', '/').escape & ", " &
                         BearCFlags.escape & ").}"))
  for n in BearSources:
    if n & ".c" notin found: error("vendor/bearssl has no " & n & ".c")

compileBearSSL()

when defined(windows) and not (defined(vcc) or defined(clang_cl)):
  # BearSSL seeds its generator from CryptGenRandom; its #pragma comment(lib)
  # only reaches MSVC-style linkers.
  {.passL: "-ladvapi32".}

# ------------------------------------------------------------- bindings ----
type
  BrEngine {.importc: "br_ssl_engine_context", header: "bearssl.h", incompleteStruct.} = object
  BrClient {.importc: "br_ssl_client_context", header: "bearssl.h".} = object
    eng: BrEngine
  BrX509Minimal {.importc: "br_x509_minimal_context", header: "bearssl.h".} = object
  BrX509Decoder {.importc: "br_x509_decoder_context", header: "bearssl.h".} = object
  BrRsaKey {.importc: "br_rsa_public_key", header: "bearssl.h".} = object
    n, e: ptr uint8
    nlen, elen: csize_t
  BrEcKey {.importc: "br_ec_public_key", header: "bearssl.h".} = object
    curve: cint
    q: ptr uint8
    qlen: csize_t
  BrPkeyKey {.union.} = object   # the anonymous union of br_x509_pkey (fields only)
    rsa: BrRsaKey
    ec: BrEcKey
  BrPkey {.importc: "br_x509_pkey", header: "bearssl.h".} = object
    key_type: uint8
    key: BrPkeyKey
  BrX500Name {.importc: "br_x500_name", header: "bearssl.h".} = object
    data: ptr uint8
    len: csize_t
  BrTrustAnchor {.importc: "br_x509_trust_anchor", header: "bearssl.h".} = object
    dn: BrX500Name
    flags: cuint
    pkey: BrPkey

const
  BrSslClosed = 0x0001'u32
  BrSslSendRec = 0x0002'u32
  BrSslRecvRec = 0x0004'u32
  BrSslSendApp = 0x0008'u32
  BrSslRecvApp = 0x0010'u32
  BrErrIo = 31
  BrErrX509TimeUnknown = 53
  BrErrX509Expired = 54
  BrKeyTypeRsa = 1'u8
  BrKeyTypeEc = 2'u8
  BrX509TaCa = 1'u32

let BrBufsizeBidi {.importc: "BR_SSL_BUFSIZE_BIDI", header: "bearssl.h".}: cint

{.push importc, cdecl, header: "bearssl.h".}
proc br_ssl_client_init_full(cc: ptr BrClient, xc: ptr BrX509Minimal,
                             anchors: ptr BrTrustAnchor, count: csize_t)
proc br_ssl_engine_set_buffer(cc: ptr BrEngine, buf: pointer, len: csize_t, bidi: cint)
proc br_ssl_client_reset(cc: ptr BrClient, serverName: cstring, resume: cint): cint
proc br_ssl_engine_current_state(cc: ptr BrEngine): cuint
proc br_ssl_engine_last_error(cc: ptr BrEngine): cint
proc br_ssl_engine_sendrec_buf(cc: ptr BrEngine, len: ptr csize_t): ptr uint8
proc br_ssl_engine_sendrec_ack(cc: ptr BrEngine, len: csize_t)
proc br_ssl_engine_recvrec_buf(cc: ptr BrEngine, len: ptr csize_t): ptr uint8
proc br_ssl_engine_recvrec_ack(cc: ptr BrEngine, len: csize_t)
proc br_ssl_engine_sendapp_buf(cc: ptr BrEngine, len: ptr csize_t): ptr uint8
proc br_ssl_engine_sendapp_ack(cc: ptr BrEngine, len: csize_t)
proc br_ssl_engine_recvapp_buf(cc: ptr BrEngine, len: ptr csize_t): ptr uint8
proc br_ssl_engine_recvapp_ack(cc: ptr BrEngine, len: csize_t)
proc br_ssl_engine_flush(cc: ptr BrEngine, force: cint)
# appendDn is passed as a plain pointer: its C type takes a `const void *`,
# which no Nim proc type can spell (gcc 14 rejects the mismatch).
proc br_x509_decoder_init(ctx: ptr BrX509Decoder, appendDn: pointer, appendCtx: pointer)
proc br_x509_decoder_push(ctx: ptr BrX509Decoder, data: pointer, len: csize_t)
proc br_x509_decoder_get_pkey(ctx: ptr BrX509Decoder): ptr BrPkey
{.pop.}

# ------------------------------------------------------ root certificates ----
proc pemCertificates(pem: string): seq[string] =
  ## The DER bytes of every certificate in a PEM bundle. Base64 by hand: the
  ## game uses no std/base64. Runs at compile time.
  const Begin = "-----BEGIN CERTIFICATE-----"
  const Finish = "-----END CERTIFICATE-----"
  var at = 0
  while true:
    let b = pem.find(Begin, at)
    if b < 0: break
    let e = pem.find(Finish, b)
    if e < 0: break
    var der = ""
    var acc = 0
    var bits = 0
    for i in b + Begin.len ..< e:
      let c = pem[i]
      let v = case c
        of 'A'..'Z': ord(c) - ord('A')
        of 'a'..'z': ord(c) - ord('a') + 26
        of '0'..'9': ord(c) - ord('0') + 52
        of '+': 62
        of '/': 63
        else: -1   # line breaks and the '=' padding
      if v < 0: continue
      acc = ((acc shl 6) or v) and 0xFFFFFF
      bits += 6
      if bits >= 8:
        bits -= 8
        der.add(char((acc shr bits) and 0xFF))
    result.add(der)
    at = e + Finish.len

const RootCertificates = pemCertificates(staticRead("../../vendor/cacert/cacert.pem"))

type TrustStore = object
  anchors: seq[BrTrustAnchor]
  bytes: seq[string]   ## every DN and key the anchors point into (never touched once built)

proc appendDn(ctx: pointer, buf: pointer, len: csize_t) {.cdecl, raises: [].} =
  ## br_x509_decoder's callback: the subject's DN arrives in pieces.
  let dn = cast[ptr string](ctx)
  let start = dn[].len
  dn[].setLen(start + int(len))
  if len > 0: copyMem(addr dn[][start], buf, int(len))

proc keyBytes(p: ptr uint8, len: csize_t): string =
  result = newString(int(len))
  if len > 0: copyMem(addr result[0], p, int(len))

proc buildTrustStore(): TrustStore =
  ## The embedded roots as BearSSL trust anchors (a few ms; built per
  ## connection so no thread shares it). A root BearSSL cannot read is
  ## skipped, as curl does.
  type Parsed = tuple[dn, a, b: int, rsa: bool, curve: cint]
  var parsed: seq[Parsed]
  for der in RootCertificates:
    var data = der
    var dn = ""
    var dc: BrX509Decoder
    br_x509_decoder_init(addr dc, cast[pointer](appendDn), addr dn)
    br_x509_decoder_push(addr dc, addr data[0], csize_t(data.len))
    let pk = br_x509_decoder_get_pkey(addr dc)
    if pk.isNil or dn.len == 0: continue
    var p: Parsed
    if pk.key_type == BrKeyTypeRsa:
      p.rsa = true
      p.a = result.bytes.len
      result.bytes.add(keyBytes(pk.key.rsa.n, pk.key.rsa.nlen))
      p.b = result.bytes.len
      result.bytes.add(keyBytes(pk.key.rsa.e, pk.key.rsa.elen))
    elif pk.key_type == BrKeyTypeEc:
      p.curve = pk.key.ec.curve
      p.a = result.bytes.len
      result.bytes.add(keyBytes(pk.key.ec.q, pk.key.ec.qlen))
    else:
      continue
    p.dn = result.bytes.len
    result.bytes.add(dn)
    parsed.add(p)
  # Second pass, once `bytes` is final: the anchors point into its strings.
  result.anchors = newSeq[BrTrustAnchor](parsed.len)
  for i, p in parsed:
    template ta: untyped = result.anchors[i]
    ta.dn.data = cast[ptr uint8](addr result.bytes[p.dn][0])
    ta.dn.len = csize_t(result.bytes[p.dn].len)
    ta.flags = BrX509TaCa
    if p.rsa:
      ta.pkey.key_type = BrKeyTypeRsa
      ta.pkey.key.rsa.n = cast[ptr uint8](addr result.bytes[p.a][0])
      ta.pkey.key.rsa.nlen = csize_t(result.bytes[p.a].len)
      ta.pkey.key.rsa.e = cast[ptr uint8](addr result.bytes[p.b][0])
      ta.pkey.key.rsa.elen = csize_t(result.bytes[p.b].len)
    else:
      ta.pkey.key_type = BrKeyTypeEc
      ta.pkey.key.ec.curve = p.curve
      ta.pkey.key.ec.q = cast[ptr uint8](addr result.bytes[p.a][0])
      ta.pkey.key.ec.qlen = csize_t(result.bytes[p.a].len)

proc rootCertificateCount*(): int =
  ## How many embedded roots BearSSL accepted (tests).
  buildTrustStore().anchors.len

# ----------------------------------------------------------- connection ----
type
  TlsError* = enum
    tlsOk
    tlsNetwork       ## no route, refused, reset, DNS failure
    tlsTimeout       ## connect or a read/write stalled too long
    tlsCancelled     ## the cancel flag was raised
    tlsCertificate   ## the server's certificate is not trusted for that name
    tlsClock         ## the certificate looks expired: often the PC's clock
    tlsProtocol      ## the TLS session itself failed

  TlsConn* = ref object
    sock: Socket
    cc: BrClient
    xc: BrX509Minimal
    iobuf: seq[uint8]
    trust: TrustStore
    cancel: ptr Atomic[bool]
    idleMs: int
    open: bool
    eof: bool                ## the server closed the TCP connection
    error*: TlsError
    detail*: string          ## English, for the log

proc fail(c: TlsConn, kind: TlsError, detail: string) =
  if c.error == tlsOk:
    c.error = kind
    c.detail = detail

proc engineFailed(c: TlsConn, err: cint) =
  let e = int(err)
  if e == BrErrIo: c.fail(tlsNetwork, "connection lost")
  elif e in [BrErrX509TimeUnknown, BrErrX509Expired]:
    c.fail(tlsClock, "certificate expired or not yet valid (BearSSL error " & $e & ")")
  elif e in 32 .. 63: c.fail(tlsCertificate, "certificate not trusted (BearSSL error " & $e & ")")
  else: c.fail(tlsProtocol, "TLS failed (BearSSL error " & $e & ")")

proc waitSocket(c: TlsConn, write: bool): bool =
  var waited = 0
  while true:
    if not c.cancel.isNil and c.cancel[].load:
      c.fail(tlsCancelled, "cancelled")
      return false
    var fds = @[c.sock.getFd]
    let ready = if write: selectWrite(fds, 200) else: selectRead(fds, 200)
    if ready > 0: return true
    if ready < 0:
      c.fail(tlsNetwork, "select failed: " & osErrorMsg(osLastError()))
      return false
    waited += 200
    if waited >= c.idleMs:
      c.fail(tlsTimeout, "no data for " & $(c.idleMs div 1000) & " s")
      return false

proc lowWrite(c: TlsConn, buf: ptr uint8, len: int): int =
  if not c.waitSocket(write = true): return -1
  result = c.sock.send(buf, len)
  if result < 0: c.fail(tlsNetwork, "send failed: " & osErrorMsg(osLastError()))

proc lowRead(c: TlsConn, buf: ptr uint8, len: int): int =
  if not c.waitSocket(write = false): return -1
  result = c.sock.recv(buf, len)
  if result == 0: c.eof = true
  elif result < 0: c.fail(tlsNetwork, "receive failed: " & osErrorMsg(osLastError()))

proc runUntil(c: TlsConn, target: uint32): bool =
  ## Move records until the engine is in one of the `target` states; false
  ## when it closed, failed or the socket did.
  let eng = addr c.cc.eng
  while true:
    let state = uint32(br_ssl_engine_current_state(eng))
    if (state and BrSslClosed) != 0:
      let err = br_ssl_engine_last_error(eng)
      if err != 0: c.engineFailed(err)
      return false
    if (state and BrSslSendRec) != 0:   # outgoing records take precedence
      var len: csize_t
      let buf = br_ssl_engine_sendrec_buf(eng, addr len)
      let n = c.lowWrite(buf, int(len))
      if n < 0: return false
      br_ssl_engine_sendrec_ack(eng, csize_t(n))
      continue
    if (state and target) != 0: return true
    if (state and BrSslRecvApp) != 0:
      # Data to read while we wait to write: HTTP never does this.
      c.fail(tlsProtocol, "unexpected data from the server")
      return false
    if (state and BrSslRecvRec) != 0:
      var len: csize_t
      let buf = br_ssl_engine_recvrec_buf(eng, addr len)
      let n = c.lowRead(buf, int(len))
      if n <= 0: return false
      br_ssl_engine_recvrec_ack(eng, csize_t(n))
      continue
    br_ssl_engine_flush(eng, 0)

proc tlsConnect*(host: string, port = 443, cancel: ptr Atomic[bool] = nil,
                 connectMs = 10_000, idleMs = 30_000): TlsConn =
  ## Open a TCP connection and set up a TLS session for `host` (its name is
  ## both the SNI and what the certificate must match). The handshake itself
  ## runs on the first write. Check `error` before use.
  result = TlsConn(cancel: cancel, idleMs: idleMs)
  try:
    result.sock = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, buffered = false)
    result.sock.connect(host, Port(port), connectMs)
  except TimeoutError:
    result.fail(tlsTimeout, "connecting to " & host & " timed out")
    return
  except OSError as e:
    result.fail(tlsNetwork, "cannot connect to " & host & ": " & e.msg)
    return
  except CatchableError as e:
    result.fail(tlsNetwork, "cannot connect to " & host & ": " & e.msg)
    return
  result.open = true
  result.trust = buildTrustStore()
  if result.trust.anchors.len == 0:
    result.fail(tlsCertificate, "no usable root certificates")
    return
  br_ssl_client_init_full(addr result.cc, addr result.xc, addr result.trust.anchors[0],
                          csize_t(result.trust.anchors.len))
  result.iobuf = newSeq[uint8](int(BrBufsizeBidi))
  br_ssl_engine_set_buffer(addr result.cc.eng, addr result.iobuf[0], csize_t(result.iobuf.len), 1)
  if br_ssl_client_reset(addr result.cc, host.cstring, 0) == 0:
    result.engineFailed(br_ssl_engine_last_error(addr result.cc.eng))

proc tlsWrite*(c: TlsConn, data: string): bool =
  ## Send all of `data` and flush it (the first call runs the handshake).
  if c.error != tlsOk or not c.open: return false
  let eng = addr c.cc.eng
  var off = 0
  while off < data.len:
    if not c.runUntil(BrSslSendApp): return false
    var room: csize_t
    let buf = br_ssl_engine_sendapp_buf(eng, addr room)
    let n = min(int(room), data.len - off)
    copyMem(buf, unsafeAddr data[off], n)
    br_ssl_engine_sendapp_ack(eng, csize_t(n))
    off += n
  br_ssl_engine_flush(eng, 0)
  c.runUntil(BrSslSendApp or BrSslRecvApp)

proc tlsRead*(c: TlsConn, buf: pointer, size: int): int =
  ## Up to `size` decrypted bytes into `buf`: the count, 0 once the server
  ## has closed the connection, -1 on an error (see `error`).
  if c.error != tlsOk or not c.open: return -1
  if size <= 0: return 0
  let eng = addr c.cc.eng
  if not c.runUntil(BrSslRecvApp):
    return if c.error == tlsOk: 0 else: -1
  var avail: csize_t
  let src = br_ssl_engine_recvapp_buf(eng, addr avail)
  result = min(int(avail), size)
  copyMem(buf, src, result)
  br_ssl_engine_recvapp_ack(eng, csize_t(result))

proc tlsClose*(c: TlsConn) =
  ## Drop the connection (no close_notify: every request says Connection: close).
  if c.open:
    c.open = false
    try:
      c.sock.close()
    except CatchableError:
      discard

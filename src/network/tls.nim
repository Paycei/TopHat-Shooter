## TLS for the mod marketplace's downloads: BearSSL from the bearssl Nimble
## package (status-im/nim-bearssl), whose C sources are compiled straight into
## the executable like Lua (no DLL), checking servers against the Mozilla root
## certificates that package ships as precompiled BearSSL trust anchors.
## A TLS 1.2 client and nothing else: https.nim is its one user.
##
## It runs on the marketplace's worker thread, so nothing here touches a game
## global, t(), the mod runtime or a {.moddable.} proc (the roots are a
## constant C table, read only). BearSSL never calls back into Nim while
## moving data: the record loop that carries its buffers through the socket
## (BearSSL's br_sslio "run until" loop) is written here, so no Nim exception
## can cross a C frame. Every wait is cut into 200 ms slices, so a cancel or a
## stalled server is noticed.

import std/[macros, net, nativesockets, atomics, os]
import bearssl/[ssl, x509]
import bearssl/certs/cacert

macro declaredIn(sym: typed): string =
  ## The file that declares `sym`.
  newLit(sym.getImpl.lineInfoObj.filename)

const BearSSLLicense* = staticRead(declaredIn(MozillaTrustAnchors).parentDir.parentDir /
                                   "csources" / "LICENSE.txt")
  ## BearSSL's MIT license, from the bearssl package wherever Nimble installed
  ## it (help licenses prints it).

when defined(clang_cl):
  # clang-cl is both clang and MSVC to BearSSL's inner.h, which then includes
  # clang's <cpuid.h> and MSVC's <intrin.h> together (they clash on __cpuid):
  # it is told the compiler is clang only (a documented override, read by
  # BearSSL alone).
  {.passC: "-DBR_MSC=0".}

when defined(windows) and not (defined(vcc) or defined(clang_cl)):
  # BearSSL seeds its generator from CryptGenRandom; its #pragma comment(lib)
  # only reaches MSVC-style linkers.
  {.passL: "-ladvapi32".}

proc rootCertificateCount*(): int =
  ## How many roots the client trusts (tests).
  MozillaTrustAnchors.len

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
    cc: SslClientContext
    xc: X509MinimalContext
    iobuf: seq[uint8]
    cancel: ptr Atomic[bool]
    idleMs: int
    open: bool
    error*: TlsError
    detail*: string          ## English, for the log

proc fail(c: TlsConn, kind: TlsError, detail: string) =
  if c.error == tlsOk:
    c.error = kind
    c.detail = detail

proc engineFailed(c: TlsConn, err: cint) =
  let e = int(err)
  if e == ERR_IO: c.fail(tlsNetwork, "connection lost")
  elif e in [ERR_X509_TIME_UNKNOWN, ERR_X509_EXPIRED]:
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
  if result < 0: c.fail(tlsNetwork, "receive failed: " & osErrorMsg(osLastError()))

proc runUntil(c: TlsConn, target: cuint): bool =
  ## Move records until the engine is in one of the `target` states; false
  ## when it closed, failed or the socket did.
  while true:
    let state = sslEngineCurrentState(c.cc.eng)
    if (state and SSL_CLOSED) != 0:
      let err = sslEngineLastError(c.cc.eng)
      if err != 0: c.engineFailed(err)
      return false
    if (state and SSL_SENDREC) != 0:   # outgoing records take precedence
      var len: csize_t
      let buf = sslEngineSendrecBuf(c.cc.eng, len)
      let n = c.lowWrite(buf, int(len))
      if n < 0: return false
      sslEngineSendrecAck(c.cc.eng, csize_t(n))
      continue
    if (state and target) != 0: return true
    if (state and SSL_RECVAPP) != 0:
      # Data to read while we wait to write: HTTP never does this.
      c.fail(tlsProtocol, "unexpected data from the server")
      return false
    if (state and SSL_RECVREC) != 0:
      var len: csize_t
      let buf = sslEngineRecvrecBuf(c.cc.eng, len)
      let n = c.lowRead(buf, int(len))
      if n <= 0: return false
      sslEngineRecvrecAck(c.cc.eng, csize_t(n))
      continue
    sslEngineFlush(c.cc.eng, 0)

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
  sslClientInitFull(result.cc, addr result.xc, addr MozillaTrustAnchors[0],
                    csize_t(MozillaTrustAnchors.len))
  result.iobuf = newSeq[uint8](SSL_BUFSIZE_BIDI)
  sslEngineSetBuffer(result.cc.eng, addr result.iobuf[0], csize_t(result.iobuf.len), 1)
  if sslClientReset(result.cc, host.cstring, 0) == 0:
    result.engineFailed(sslEngineLastError(result.cc.eng))

proc tlsWrite*(c: TlsConn, data: string): bool =
  ## Send all of `data` and flush it (the first call runs the handshake).
  if c.error != tlsOk or not c.open: return false
  var off = 0
  while off < data.len:
    if not c.runUntil(SSL_SENDAPP): return false
    var room: csize_t
    let buf = sslEngineSendappBuf(c.cc.eng, room)
    let n = min(int(room), data.len - off)
    copyMem(buf, unsafeAddr data[off], n)
    sslEngineSendappAck(c.cc.eng, csize_t(n))
    off += n
  sslEngineFlush(c.cc.eng, 0)
  c.runUntil(SSL_SENDAPP or SSL_RECVAPP)

proc tlsRead*(c: TlsConn, buf: pointer, size: int): int =
  ## Up to `size` decrypted bytes into `buf`: the count, 0 once the server
  ## has closed the connection, -1 on an error (see `error`).
  if c.error != tlsOk or not c.open: return -1
  if size <= 0: return 0
  if not c.runUntil(SSL_RECVAPP):
    return if c.error == tlsOk: 0 else: -1
  var avail: csize_t
  let src = sslEngineRecvappBuf(c.cc.eng, avail)
  result = min(int(avail), size)
  copyMem(buf, src, result)
  sslEngineRecvappAck(c.cc.eng, csize_t(result))

proc tlsClose*(c: TlsConn) =
  ## Drop the connection (no close_notify: every request says Connection: close).
  if c.open:
    c.open = false
    try:
      c.sock.close()
    except CatchableError:
      discard

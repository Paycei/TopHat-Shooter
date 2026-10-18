## HTTP/1.1 GET over tls.nim, streamed into a file: what the mod marketplace
## needs from GitHub (registry and mod archives from codeload.github.com),
## nothing more. Redirects (https only), chunked bodies and Content-Length
## are handled; a body cut short is an error.
##
## Runs on the marketplace's worker thread (see tls.nim for the rules that
## follows): progress goes out and cancel comes in through atomics.

import std/[atomics, strutils]
import tls

export TlsError

type
  HttpsResult* = object
    ok*: bool
    status*: int         ## the last response's HTTP status (0 if none arrived)
    error*: TlsError     ## tlsOk with ok = false: an HTTP-level failure
    detail*: string      ## English, for the log
    bytes*: int          ## body bytes written

const
  MaxRedirects = 5
  MaxHeaderLine = 8192
  MaxHeaders = 100
  ReadChunk = 16384

proc splitHttpsUrl*(url: string, host: var string, port: var int, path: var string): bool =
  ## "https://host[:port]/path" -> parts. No std/uri (the game does not use it).
  const Scheme = "https://"
  if url.len <= Scheme.len or url[0 ..< Scheme.len].toLowerAscii != Scheme: return false
  let rest = url[Scheme.len .. ^1]
  let slash = rest.find('/')
  let authority = if slash < 0: rest else: rest[0 ..< slash]
  path = if slash < 0: "/" else: rest[slash .. ^1]
  let fragment = path.find('#')
  if fragment >= 0: path.setLen(fragment)
  if authority.len == 0 or '@' in authority or ' ' in authority or ' ' in path: return false
  let colon = authority.rfind(':')
  if colon >= 0:
    host = authority[0 ..< colon]
    try:
      port = parseInt(authority[colon + 1 .. ^1])
    except ValueError:
      return false
  else:
    host = authority
    port = 443
  host.len > 0 and port in 1 .. 65535

type Reader = object
  conn: TlsConn
  buf: string
  pos: int

proc fill(r: var Reader): bool =
  ## More bytes into the buffer; false at the end of the stream or on an
  ## error (the connection's `error` tells which).
  if r.pos == r.buf.len:
    r.buf.setLen(0)
    r.pos = 0
  elif r.pos > 4 * ReadChunk:
    r.buf = r.buf[r.pos .. ^1]
    r.pos = 0
  let start = r.buf.len
  r.buf.setLen(start + ReadChunk)
  let n = tlsRead(r.conn, addr r.buf[start], ReadChunk)
  r.buf.setLen(start + max(n, 0))
  n > 0

proc readLine(r: var Reader, line: var string): bool =
  ## One CRLF-terminated line (without the CRLF).
  while true:
    let at = r.buf.find("\r\n", r.pos)
    if at >= 0:
      line = r.buf[r.pos ..< at]
      r.pos = at + 2
      return true
    if r.buf.len - r.pos > MaxHeaderLine: return false
    if not r.fill(): return false

proc copyBody(r: var Reader, f: File, count: int, written: var int,
              received: ptr Atomic[int]): bool =
  ## Exactly `count` body bytes into `f` (count < 0: until the stream ends).
  var left = count
  while left != 0:
    if r.pos == r.buf.len and not r.fill():
      return count < 0 and r.conn.error == tlsOk
    let n = if left < 0: r.buf.len - r.pos else: min(left, r.buf.len - r.pos)
    if f.writeBuffer(addr r.buf[r.pos], n) != n: return false
    r.pos += n
    written += n
    if left > 0: left -= n
    if not received.isNil: received[].store(written)
  true

proc failWith(res: var HttpsResult, conn: TlsConn, fallback: string) =
  ## The connection's error if it has one, else an HTTP-level failure.
  if not conn.isNil and conn.error != tlsOk:
    res.error = conn.error
    res.detail = conn.detail
  else:
    res.detail = fallback

proc httpsGetToFile*(url, dest: string, received: ptr Atomic[int] = nil,
                     total: ptr Atomic[int] = nil, cancel: ptr Atomic[bool] = nil,
                     userAgent = "TopHatShooterOS"): HttpsResult =
  ## GET `url` and stream a 200 response's body into the file `dest`
  ## (replaced). `received` counts body bytes; `total` is the length the
  ## server announced, or -1.
  var url = url
  for hop in 0 .. MaxRedirects:
    var host, path: string
    var port: int
    if not splitHttpsUrl(url, host, port, path):
      result.detail = "not an https URL: " & url
      return
    let conn = tlsConnect(host, port, cancel)
    defer: tlsClose(conn)
    if conn.error != tlsOk:
      result.failWith(conn, "")
      return
    let hostHeader = if port == 443: host else: host & ":" & $port
    if not conn.tlsWrite("GET " & path & " HTTP/1.1\r\nHost: " & hostHeader &
                         "\r\nUser-Agent: " & userAgent &
                         "\r\nAccept: */*\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n"):
      result.failWith(conn, "the request could not be sent")
      return
    var r = Reader(conn: conn)
    var line: string
    if not r.readLine(line):
      result.failWith(conn, "no response from " & host)
      return
    let parts = line.splitWhitespace()
    if parts.len < 2 or not parts[0].startsWith("HTTP/1."):
      result.detail = "not an HTTP response: " & line[0 ..< min(line.len, 60)]
      return
    try:
      result.status = parseInt(parts[1])
    except ValueError:
      result.detail = "bad HTTP status: " & parts[1]
      return
    var location = ""
    var length = -1
    var chunked = false
    var headers = 0
    while true:
      if not r.readLine(line):
        result.failWith(conn, "the response headers were cut short")
        return
      if line.len == 0: break
      inc headers
      if headers > MaxHeaders:
        result.detail = "too many response headers"
        return
      let colon = line.find(':')
      if colon <= 0: continue
      let key = line[0 ..< colon].strip.toLowerAscii
      let value = line[colon + 1 .. ^1].strip
      case key
      of "location": location = value
      of "content-length":
        try: length = parseInt(value)
        except ValueError: length = -1
      of "transfer-encoding": chunked = "chunked" in value.toLowerAscii
      else: discard
    if result.status in [301, 302, 303, 307, 308]:
      if location.len == 0:
        result.detail = "redirect without a Location"
        return
      url = if location.startsWith("//"): "https:" & location
            elif location.startsWith("/"): "https://" & hostHeader & location
            else: location
      continue
    if result.status != 200:
      result.detail = "HTTP " & $result.status & " from " & host & path
      return
    if not total.isNil: total[].store(if chunked: -1 else: length)
    if not received.isNil: received[].store(0)
    var f: File
    if not open(f, dest, fmWrite):
      result.detail = "cannot write " & dest
      return
    defer: f.close()
    var written = 0
    var complete = false
    if chunked:
      complete = true
      while true:
        if not r.readLine(line):
          complete = false
          break
        let semi = line.find(';')
        let sizeText = (if semi >= 0: line[0 ..< semi] else: line).strip
        var size = 0
        try:
          size = parseHexInt(sizeText)
        except ValueError:
          complete = false
          break
        if size == 0:   # the last chunk; trailers end with an empty line
          while r.readLine(line) and line.len > 0: discard
          break
        if size < 0 or not r.copyBody(f, size, written, received) or
           not r.readLine(line) or line.len != 0:
          complete = false
          break
    else:
      complete = r.copyBody(f, length, written, received)
    result.bytes = written
    if not complete:
      result.failWith(conn, "the download was cut short (" & $written & " bytes)")
      return
    result.ok = true
    return
  result.detail = "too many redirects"

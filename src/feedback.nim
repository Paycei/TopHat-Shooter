## Player feedback / bug reports.
##
## The game has no backend, so a report goes out the one way that needs none:
## a pre-filled "new issue" page on the project's GitHub, opened in the player's
## browser, where they review it and press submit. Copying to the clipboard and
## saving a Markdown file are the fallbacks for players without an account.
##
## Everything here is pure composition plus the three delivery actions; the
## form itself lives in ui/feedback_window.nim. The report text is written for
## the developer and is deliberately not localized -- only the form is.

import std/[strutils, times, os]
import raylib
import save_system, settings, types, localization

# ---------------------------------------------------------------------------
# External links: project support / donation buttons and the browser opener.
#
# SupportEnabled is the single switch for the donation feature. Set it to
# `false` and every support affordance disappears from the build: the SUPPORT
# panel at the bottom of the Credits window is not laid out, not drawn and not
# clickable, and the window shrinks to fit the credits alone. The feedback
# form's openExternalUrl is not gated by it.
# ---------------------------------------------------------------------------

const
  SupportEnabled* = true
    ## Master switch for the support/donation UI. Flip to `false` to ship a
    ## build with no donation links at all.

type
  SupportLink* = object
    ## One external "support the project" destination, rendered as a button.
    label*: string   ## Button caption (a brand name; deliberately not localized)
    url*: string
    fill*: Color     ## Button body colour (roughly the brand colour)
    text*: Color     ## Caption colour, picked for contrast against `fill`

let supportLinks*: seq[SupportLink] = @[
  SupportLink(label: "GitHub Sponsors", url: "https://github.com/sponsors/Paycei",
              fill: Color(r: 219, g: 97, b: 162, a: 255),
              text: Color(r: 255, g: 255, b: 255, a: 255)),
  SupportLink(label: "Ko-fi", url: "https://ko-fi.com/paycei",
              fill: Color(r: 255, g: 94, b: 91, a: 255),
              text: Color(r: 255, g: 255, b: 255, a: 255)),
  SupportLink(label: "Buy Me a Coffee", url: "https://buymeacoffee.com/paycei",
              fill: Color(r: 255, g: 221, b: 0, a: 255),
              text: Color(r: 25, g: 22, b: 8, a: 255))
]

const ProjectRepoUrl* = "https://github.com/Paycei/TopHat-Shooter"

# raylib ships OpenURL on every platform (xdg-open on Linux, an Intent on
# Android) but naylib does not wrap it. Binding it directly reuses naylib's
# include path and avoids pulling in std/browsers, which would shell out and
# does nothing useful on Android.
#
# Windows is the exception: raylib runs `explorer "<url>"`, and explorer treats
# its argument as a path, silently cutting it at MAX_PATH (259 characters). A
# pre-filled feedback issue is far longer, so there the URL goes through cmd's
# `start` instead, which passes it on whole. The URL must be fully
# percent-encoded either way: no quotes, spaces, `&` or `^` can reach cmd.
when not defined(windows):
  proc rlOpenURL(url: cstring) {.importc: "OpenURL", header: "raylib.h".}

proc openExternalUrl*(url: string) =
  ## Hand `url` to the system browser. Not gated on SupportEnabled: the
  ## feedback window uses it too. Callers must pass a fully percent-encoded URL.
  if url.len == 0 or '"' in url or '\'' in url:
    return
  when defined(windows):
    # The empty "" is start's window title; without it the quoted URL would be
    # taken as the title and nothing would open.
    discard execShellCmd("start \"\" \"" & url & "\"")
  else:
    rlOpenURL(url.cstring)

proc openSupportUrl*(url: string) =
  ## Hand `url` to the system browser. Silently does nothing when support is
  ## compiled out, so a stray call site can never open a donation page.
  when SupportEnabled:
    openExternalUrl(url)
  else:
    discard url

# ---------------------------------------------------------------------------
# Feedback reports
# ---------------------------------------------------------------------------

type
  FeedbackKind* = enum
    fkBug
    fkIdea
    fkOther

  SendResult* = enum
    srOpened      ## whole report fits in the link
    srTruncated   ## link carries the start; the full report went to the clipboard

const
  FeedbackTitleMaxLen* = 90
  FeedbackBodyMaxLen* = 1500

  # On Windows the link travels on a cmd.exe command line (see openExternalUrl),
  # which tops out at 8191 characters; a 5 KB link was verified to arrive whole.
  # Staying well under that means the page always opens intact; anything
  # longer is handed over through the clipboard instead.
  MaxIssueUrlLen = 6000

proc readNimbleVersion(): string {.compileTime.} =
  ## The .nimble file is the single source of the version (tools/ship.ps1 reads
  ## it too), so the report can never be stamped with a stale number.
  for line in staticRead("../TopHatShooter.nimble").splitLines():
    let l = line.strip()
    if l.startsWith("version"):
      let parts = l.split('"')
      if parts.len >= 2:
        return parts[1]
  "unknown"

const GameVersion* = readNimbleVersion()

proc kindTag(kind: FeedbackKind): string =
  case kind
  of fkBug: "Bug"
  of fkIdea: "Idea"
  of fkOther: "Feedback"

proc kindLabel(kind: FeedbackKind): string =
  ## GitHub's default label set. Only applied when the reporter can triage, so
  ## the [Tag] title prefix is what actually sorts reports from everyone else.
  case kind
  of fkBug: "bug"
  of fkIdea: "enhancement"
  of fkOther: ""

proc systemInfoLines*(): seq[string] =
  ## What the developer needs to reproduce a report, and nothing identifying:
  ## no paths, user names, profile names or hardware serials.
  let build = when defined(debug): "debug" else: "release"
  result.add("Version: " & GameVersion & " (" & build & ")")
  result.add("Platform: " & hostOS & " / " & hostCPU)
  result.add("Difficulty: " & $currentDifficulty)
  result.add("Language: " & $currentLanguage)
  result.add("Window: " & $getScreenWidth() & "x" & $getScreenHeight())
  let s = globalSettings
  if not s.isNil:
    result.add("Fullscreen: " & (if s.fullscreen: "yes" else: "no") &
               ", VSync: " & (if s.vsyncEnabled: "on" else: "off") &
               ", render scaling: " & $s.renderResolutionMode)
    result.add("HUD: " & $s.hudStyle & " / " & $s.hudLayout &
               ", UI scale " & formatFloat(s.uiScale, ffDecimal, 2))

proc issueTitle(kind: FeedbackKind, title, body: string): string =
  var t = title.strip()
  if t.len == 0:
    # Fall back to the first line of the details so the issue list stays readable.
    t = body.strip().splitLines()[0]
    if t.len > 60:
      t = t[0 ..< 60] & "..."
  "[" & kindTag(kind) & "] " & t

proc composeReport*(kind: FeedbackKind, title, body: string,
                    includeInfo: bool): string =
  ## The Markdown body of the issue (and of the copied / saved report).
  result = "### " & kindTag(kind) & "\n\n"
  let details = body.strip()
  result.add(if details.len > 0: details else: "_(no details)_")
  result.add("\n")
  if includeInfo:
    result.add("\n### System info\n\n")
    for line in systemInfoLines():
      result.add("- " & line & "\n")
  result.add("\n_Sent from FEEDBACK.exe in TopHat-ShooterOS._\n")

proc hasContent*(title, body: string): bool =
  title.strip().len > 0 or body.strip().len > 0

proc percentEncode(s: string): string =
  ## RFC 3986 query encoding: only unreserved characters stay literal; every
  ## other byte (UTF-8 included) becomes %XX. Quotes, spaces, `&`, `^` and `%`
  ## are all escaped, which is what makes the link safe for openExternalUrl:
  ## on Windows it runs `start "" "<url>"` through cmd.exe (so a literal `"` or
  ## `&` would break out of the quotes), and on Linux raylib wraps the URL in
  ## single quotes for xdg-open.
  ##
  ## cmd.exe does still expand `%NAME%` when NAME is a defined variable. An
  ## encoded report can only put a two-hex-digit prefix after a `%` (bytes this
  ## encoder emits: 0A, 20-7E punctuation, 80-BF, C2, C3), and no standard
  ## Windows variable name starts that way.
  const Unreserved = {'A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'}
  for c in s:
    if c in Unreserved:
      result.add(c)
    else:
      result.add('%')
      result.add(toHex(ord(c), 2))

proc issueUrl(kind: FeedbackKind, title, report: string): string =
  result = ProjectRepoUrl & "/issues/new?title=" & percentEncode(title) &
           "&body=" & percentEncode(report)
  let label = kindLabel(kind)
  if label.len > 0:
    result.add("&labels=" & label)

proc sendToGitHub*(kind: FeedbackKind, title, body: string,
                   includeInfo: bool): SendResult =
  ## Open the pre-filled issue page. When the report is too long for a link,
  ## the full text goes to the clipboard and the page opens with a note asking
  ## for it to be pasted, so nothing the player wrote is silently lost.
  let fullTitle = issueTitle(kind, title, body)
  let report = composeReport(kind, title, body, includeInfo)
  let url = issueUrl(kind, fullTitle, report)
  if url.len <= MaxIssueUrlLen:
    openExternalUrl(url)
    return srOpened

  # The title still fits in the link, so only the body goes to the clipboard.
  setClipboardText(report)
  let stub = "### " & kindTag(kind) & "\n\n" &
             "_The full report was copied to the clipboard by the game: " &
             "select all of this text (Ctrl+A) and paste (Ctrl+V) to replace it._\n"
  openExternalUrl(issueUrl(kind, fullTitle, stub))
  srTruncated

proc copyReport*(kind: FeedbackKind, title, body: string, includeInfo: bool) =
  setClipboardText(issueTitle(kind, title, body) & "\n\n" &
                   composeReport(kind, title, body, includeInfo))

proc saveReport*(kind: FeedbackKind, title, body: string,
                 includeInfo: bool): string =
  ## Write the report under <profile>/feedback/ and return its path, or "" on
  ## failure. One file per save, timestamped, so nothing is ever overwritten.
  let dir = getAppDataPath() / "feedback"
  let stamp = now().format("yyyyMMdd'_'HHmmss")
  let path = dir / ("report_" & stamp & ".md")
  try:
    createDir(dir)
    writeFile(path, "# " & issueTitle(kind, title, body) & "\n\n" &
                    composeReport(kind, title, body, includeInfo))
    result = path
  except CatchableError:
    result = ""

## Project support / donation links.
##
## SupportEnabled is the single switch for the whole feature. Set it to `false`
## and every support affordance disappears from the build: the SUPPORT panel at
## the bottom of the Credits window is not laid out, not drawn and not clickable,
## and the window shrinks to fit the credits alone. Nothing else changes -- the
## Credits.txt desktop icon and the credits themselves are always available.
##
## Leaf module: imports only raylib, so any ui/ module can use it freely.

import raylib

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

# raylib ships OpenURL on every platform (ShellExecute on Windows, xdg-open on
# Linux, an Intent on Android) but naylib does not wrap it. Binding it directly
# reuses naylib's include path and avoids pulling in std/browsers, which would
# shell out and does nothing useful on Android.
when SupportEnabled:
  proc rlOpenURL(url: cstring) {.importc: "OpenURL", header: "raylib.h".}

proc openSupportUrl*(url: string) =
  ## Hand `url` to the system browser. Silently does nothing when support is
  ## compiled out, so a stray call site can never open a donation page.
  when SupportEnabled:
    if url.len > 0:
      rlOpenURL(url.cstring)
  else:
    discard url

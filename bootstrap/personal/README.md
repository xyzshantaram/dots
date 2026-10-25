# personal

Optional. The image, audio, video, office, typesetting, mail and chat
applications, kept out of the main ladder because none of it is needed for a
working niri session: the main ladder builds a session, this one gives you
something to make, read and talk in it. It can be removed without touching
anything else — with one exception: the main ladder's `90-fish` installs a
`shrinkpdf` function, and that needs `gs` from this ladder's `40-typesetting`.

It is its own ladder, run with the same runner from the repo root:

```
bun run ladder personal list
bun run ladder personal plan
bun run ladder personal up
```

Both installation modes apply, as everywhere else: `ROOT_MNT` in `.env` or
`--live` decides whether it writes into a mounted target root or into the running
system.

- `10-graphics` — ImageMagick, GIMP, Inkscape and optipng.
- `20-media` — Audacity, Kdenlive and qBittorrent.
- `30-office` — LibreOffice, and OnlyOffice built from the AUR.
- `40-typesetting` — Typst, its language service, fonttools and Ghostscript.
- `50-color-picker` — `wl-color-picker`, from the AUR: pick a colour off the screen.
- `60-spotify` — `spotify-launcher`: the native client for Spotify's own repository.
- `70-comms` — `himalaya` for mail, and Discord for chat.

## What it installs, and where

| tool | from | package |
| --- | --- | --- |
| `magick` | the repositories | `imagemagick` |
| GIMP | the repositories | `gimp` |
| Inkscape | the repositories | `inkscape` |
| `optipng` | the repositories | `optipng` |
| Audacity | the repositories | `audacity` |
| Kdenlive | the repositories | `kdenlive` |
| qBittorrent | the repositories | `qbittorrent` |
| LibreOffice | the repositories | `libreoffice-fresh` |
| OnlyOffice | the AUR, built by `aurInstall` | `onlyoffice-bin` |
| `typst`, `tinymist` | the repositories | `typst`, `tinymist` |
| `fonttools` | the repositories | `python-fonttools` |
| Ghostscript | the repositories | `ghostscript` |
| `wl-color-picker` | the AUR, built by `aurInstall` | `wl-color-picker` |
| Spotify | the repositories, via `spotify-launcher` | `spotify-launcher` |
| `himalaya` | the repositories | `himalaya` |
| Discord | the repositories | `discord` |

`ffmpeg` is deliberately not here. It is installed by the main ladder's
`40-packages`, because it is useful on its own and not only as something
Audacity or Kdenlive lean on.

## Why OnlyOffice is built rather than installed

`onlyoffice-bin` is the upstream binary build; the AUR also has `onlyoffice`,
which rebuilds the desktop editors from source, and that is a much longer build
for the same application. LibreOffice, the other suite in this step, is in the
repositories and needs none of this.

The build goes through the same `aurInstall` helper `110-niri` uses for vicinae:
clone as the account, install the dependencies out of `.SRCINFO` as root,
`makepkg` as the account, `pacman -U` as root. It needs `base-devel`, which the
main ladder's `40-packages` installs.

`wl-color-picker` is the ladder's other AUR package and takes the same path.

## Typst, and Ghostscript

`typst` is a compiler, so a document builds from a terminal without an editor
involved:

```
typst compile doc.typ
```

`tinymist` is the language service in the same step, because that is what an
editor needs for completions and live preview — with the software-dev ladder installed,
Zed talks to it. The formatter, `typstyle`, is in the repositories too and is a
one-word addition to that step if it is wanted.

`ghostscript` is in that step because a PDF is what the compiler writes and `gs`
is the interpreter that reads one back. The main ladder's `shrinkpdf` function is
a thin wrapper around it:

```
shrinkpdf file.pdf              # writes "file (shrunk).pdf"
shrinkpdf --replace file.pdf    # ...and removes the original on success
```

## Mail and chat

`himalaya` reads its accounts from `~/.config/himalaya`, and some backends keep
credentials there. `70-comms` installs the binary and leaves that file to you,
for the same reason the software-dev ladder leaves its tokens alone: a
credential is the one thing a repository cannot re-derive.

Discord is the repositories' native client. Its account lives in the app's own
config and is created on first login.

## Undo

`down` runs `pacman -Rns` over each step's package list, ignoring failures, and
leaves orphans in place — the same contract as `40-packages`. `30-office`
removes `libreoffice-fresh` and `onlyoffice-bin`; anything pacman pulled in as a
dependency stays until you clean orphans yourself.

# creative

Optional. The image, audio, video, office and typesetting applications, kept out
of the main ladder because none of it is needed for a working niri session: the
main ladder builds a session, this one gives you something to make things in it.
**Nothing in the main ladder depends on this**, and it can be removed without
touching anything else.

It is its own ladder, run with the same runner from the repo root:

```
bun run ladder creative list
bun run ladder creative plan
bun run ladder creative up
```

Both installation modes apply, as everywhere else: `ROOT_MNT` in `.env` or
`--live` decides whether it writes into a mounted target root or into the running
system.

- `10-graphics` — ImageMagick, GIMP, Inkscape and optipng.
- `20-media` — Audacity, Kdenlive.
- `30-office` — OnlyOffice, built from the AUR.
- `40-typesetting` — Typst, its language service, and fonttools.
- `50-color-picker` — `wl-color-picker`, from the AUR: pick a colour off the screen.

## What it installs, and where

| tool | from | package |
| --- | --- | --- |
| `magick` | the repositories | `imagemagick` |
| GIMP | the repositories | `gimp` |
| Inkscape | the repositories | `inkscape` |
| `optipng` | the repositories | `optipng` |
| Audacity | the repositories | `audacity` |
| Kdenlive | the repositories | `kdenlive` |
| OnlyOffice | the AUR, built by `aurInstall` | `onlyoffice-bin` |
| `typst`, `tinymist` | the repositories | `typst`, `tinymist` |
| `fonttools` | the repositories | `python-fonttools` |
| `wl-color-picker` | the AUR, built by `aurInstall` | `wl-color-picker` |

`ffmpeg` is deliberately not here. It is installed by the main ladder's
`40-packages`, because it is useful on its own and not only as something
Audacity or Kdenlive lean on.

## Why OnlyOffice is built rather than installed

It is the only package in this ladder that the repositories do not carry.
`onlyoffice-bin` is the upstream binary build; the AUR also has `onlyoffice`,
which rebuilds the desktop editors from source, and that is a much longer build
for the same application. The build goes through the same `aurInstall` helper
`110-niri` uses for vicinae: clone as the account, install the dependencies out
of `.SRCINFO` as root, `makepkg` as the account, `pacman -U` as root. It needs
`base-devel`, which the main ladder's `40-packages` installs.

## Typst

`typst` is a compiler, so a document builds from a terminal without an editor
involved:

```
typst compile doc.typ
```

`tinymist` is the language service in the same step, because that is what an
editor needs for completions and live preview — with the software-dev ladder installed,
Zed talks to it. The formatter, `typstyle`, is in the repositories too and is a
one-word addition to that step if it is wanted.

## Undo

`down` runs `pacman -Rns` over each step's package list, ignoring failures, and
leaves orphans in place — the same contract as `40-packages`. `30-office` simply
removes `onlyoffice-bin`; anything pacman pulled in as its dependency stays until
you clean orphans yourself.

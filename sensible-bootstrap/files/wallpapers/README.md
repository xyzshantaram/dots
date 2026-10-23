# Your wallpapers live here.

This directory is tracked. **Its contents are ignored** — see `.gitignore` — so
whatever you drop in here stays on your machine and never lands in a commit.

Populate it with whatever you want; the filenames do not matter. At every niri
startup, `wallpaper-random` picks one at random and hands it to `swaybg`.

Recognised extensions: `.png`, `.jpg`, `.jpeg`, `.webp`, `.gif`, `.bmp`.

## Why a directory and not a file

A single committed wallpaper is a decision that ages badly, and it makes the
repo carry a binary nobody agreed to. A directory means the choice stays yours,
the repo carries the mechanism instead of the content, and adding a wallpaper
is dropping a file in.

## What gets installed

`112-wallpaper.ts` copies anything in here into `~/wallpapers` inside the
target. It only ever adds: a file already in `~/wallpapers` is left alone, and
files you put there by hand are never touched. `down` removes only what this
step copied.

If this directory is empty the step still installs `wallpaper-random` and points
niri at it. It logs that it found nothing and exits cleanly at startup, so a
machine with no wallpapers still boots to a session.

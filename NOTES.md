# Notes

Machine-specific things that are not ladder steps: what was done by hand, why,
and how to undo or repeat it.

## Console keymap: `en` was a PinePhone keymap

`/etc/vconsole.conf` had `KEYMAP=en`, and the only `en.map.gz` on the system is
`/usr/share/kbd/keymaps/pine/en.map.gz` — the factory keymap for a PinePhone
keyboard, not a PC one. It happened to map `keycode 14 = BackSpace`, while
`i386/qwerty/us.map.gz` maps the same keycode to `Delete`, so the console was
neither the kernel default nor predictable. Symptom: backspace did nothing in
ttys, intermittently.

Fixed by hand:

```
sudo localectl set-keymap us
```

That rewrites `/etc/vconsole.conf` and, because localed owns the xkb settings
too, also sets `XKBLAYOUT=us`, `XKBMODEL=pc105+inet` and
`XKBOPTIONS=terminate:ctrl_alt_bksp`.

Two things about the side effect:

- niri takes its keymap from localed whenever `input { keyboard { xkb { } } }` is
  empty, which it is here, so this is niri's keymap as well now.
- `key <FK13>` still resolves to `XF86Tools` under `pc105+inet`, so the
  Super-tap launcher bind in `files/niri/config.kdl` is unaffected. Checked with
  `xkbcli compile-keymap --layout us --model 'pc105+inet' | grep 'key <FK13>'`.

The ladder does not set the console keymap. This stays a manual fix unless a
reinstall shows the same `en` default.

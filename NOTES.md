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

## External brightness: DDC/CI dies in the dock

The Acer EK220Q E3 is reached through a USB-C dock that converts to HDMI
(`DP-2` through that dock, `DP-1` when plugged in directly; kanshi matches the
monitor by identity, see `bootstrap/README.md`, Outputs). EDID gets through:
`ddcutil detect` names the monitor, and the bus answers at `0x37`. But
`getvcp 10` fails `DDCRC_RETRIES / DDCRC_DDC_DATA`, so the brightness keys
change nothing on that output.

Not permissions — `i2c_dev` is loaded, the account is in `video`, and the i2c
nodes carry an ACL. The connector's hardware DDC bus (`i2c-6`) is empty, so
traffic goes over AUX (`i2c-14`), which is why EDID works and DDC/CI does not.

Left alone deliberately: no overlay dimming, no new dock. Adjust the monitor by
hand. The DDC branch in `files/bin/brightness` stays for a machine where the
monitor is plugged straight into HDMI or DisplayPort.

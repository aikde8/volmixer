# Audio patches — Bluetooth headset microphone in HFP

A standalone rebuild of the `libspa-bluez5.so` plugin with three PipeWire patches.
Unrelated to the applet itself: this fixes the same class of breakage that the
applet works around with its "switch to HFP during a call" logic. Install only
if the microphone on your Bluetooth headset does not come up in headset mode
(HFP, mSBC/LC3) or drops after the first session.

## Why

HUAWEI FreeBuds Pro 5, FreeClip and several other headsets send AT+BCC about
160 ms after the AG (adapter) opens the eSCO channel. PipeWire ≤ 1.6.x reacts
to the subsequent AT+BCS by re-creating the transport and tearing down a
channel that is not open yet — the microphone in HFP never comes up. See
[bluez/bluez#2562](https://github.com/bluez/bluez/issues/2562),
[pipewire#5506](https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/5506).

Symptoms this fixes:
- A recording application lists the headset microphone, but no audio comes
  through when you select it.
- `wpctl status` shows only the A2DP profile for the headset; HFP never engages,
  or engages but the microphone stays silent.
- `journalctl --user -u wireplumber` prints `node removed` / `transport destroyed`
  right after `AT+BCC`.

If the microphone works for you already — you do not need this.

## What the script installs

Builds one `libspa-bluez5.so` strictly for the installed PipeWire version
(from `pipewire --version`), with the three patches from `patches/`, and feeds
it to WirePlumber via the `SPA_PLUGIN_DIR` environment variable.

| File | Purpose |
|---|---|
| `~/.local/lib/spa-0.2-patched/bluez5/libspa-bluez5.so` | the patched plugin |
| `~/.local/lib/spa-0.2-patched/version` | which PipeWire version it was built for |
| `~/.config/systemd/user/wireplumber.service.d/spa-bluez5-fix.conf` | drop-in setting `SPA_PLUGIN_DIR=<...-patched>:<system>` |

No system files are touched. `sudo` is only used to `apt-get install` the build
dependencies (meson, ninja, dev packages for bluez / dbus / glib / sbc / lc3 /
opus). PipeWire sources are cloned into `addons/pipewire-<version>/` (~40 MB)
from freedesktop.org (with a GitHub mirror as a fallback).

## The patches

| № | What it fixes | Source |
|---|---|---|
| `0001` | asynchronous device/node removal (WirePlumber 0.5.17+) — the plugin crashes without it | PipeWire main, [b7246d0d](https://gitlab.freedesktop.org/pipewire/pipewire/-/commit/b7246d0d) |
| `0002` | reset the transport error counter on a successful `acquire` — otherwise accumulated errors cause the next `acquire` to fail with `-EIO` | PipeWire main, [d80b8060](https://gitlab.freedesktop.org/pipewire/pipewire/-/commit/d80b8060) |
| `0003` | do not re-create the transport if `AT+BCS` confirms the current codec — the actual fix for the AT+BCC race | [github.com/abrus861/pipewire-hfp-atbcc-fix](https://github.com/abrus861/pipewire-hfp-atbcc-fix) |

0001 and 0002 are already in PipeWire main — the script skips them when they
are already applied. 0003 is still waiting to be merged.

## Install

```sh
sh addons/install.sh
```

If the matching patches are already in place for this PipeWire version the
script does nothing (`bluez5 patch for PipeWire <version> already installed`).
If all three patches have already made it upstream, no separate plugin is
needed and the script removes the drop-in that may be left over from an earlier
PipeWire version.

**Re-run after a PipeWire upgrade** — the plugin is bound to the exact version.
On the same version the script is a no-op.

## Rollback

```sh
rm ~/.config/systemd/user/wireplumber.service.d/spa-bluez5-fix.conf
systemctl --user daemon-reload
systemctl --user restart wireplumber
```

Files under `~/.local/lib/spa-0.2-patched/` can stay — without the drop-in,
WirePlumber does not look at them.

## The previous workaround

Before these patches the workaround was `bluez5.enable-msbc = false` in
`wireplumber.conf.d/52-hfp-no-msbc.conf`: force CVSD 8 kHz. The microphone
came up, but the audio was narrow-band. The file is left in place with a
`.disabled` suffix next to the WirePlumber config — remove the suffix if you
need to fall back to it.

## Relation to the applet

The applet does not fix this on its own: HFP is engaged at the PipeWire /
WirePlumber layer, not inside Plasma. But volmixer has related behaviour on
its "Logic" page — "During a call, when a Bluetooth microphone is selected,
switch the device into headset mode" — that moves the device's card to the
best HFP profile once active recording streams appear. Without the patch the
card does not always stay in HFP, and the addon helps; with the patch, the
applet's logic is what you need.

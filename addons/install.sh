#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEST=$HOME/.local/lib/spa-0.2-patched
DROPIN=$HOME/.config/systemd/user/wireplumber.service.d/spa-bluez5-fix.conf
in_session() { [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; }

command -v pipewire >/dev/null || { echo "no PipeWire — skipping"; exit 0; }
VER=$(pipewire --version | awk '/Compiled with/{print $NF}')
SYSLIB=$(find /usr/lib /usr/lib64 -path '*/spa-0.2/bluez5/libspa-bluez5.so' 2>/dev/null | head -1)
[ -n "$SYSLIB" ] || { echo "no libspa-0.2-bluetooth — skipping"; exit 0; }
if [ -e "$DROPIN" ] && [ "$(cat "$DEST/version" 2>/dev/null)" = "$VER" ]; then echo "bluez5 patch for PipeWire $VER already installed"; exit 0; fi

sudo apt-get install -y --no-install-recommends git meson ninja-build gcc pkg-config libdbus-1-dev libglib2.0-dev libsbc-dev \
	libbluetooth-dev libusb-1.0-0-dev liblc3-dev libopus-dev
SRC=$HERE/pipewire-$VER
[ -d "$SRC/.git" ] || git clone -q --depth 1 --branch "$VER" https://gitlab.freedesktop.org/pipewire/pipewire.git "$SRC" \
	|| git clone -q --depth 1 --branch "$VER" https://github.com/PipeWire/pipewire.git "$SRC"
cd "$SRC"
git checkout -q -f "$VER"
n=0
for p in "$HERE"/patches/*.patch; do
	if git apply --check "$p" 2>/dev/null; then git apply "$p"; n=$((n + 1))
	elif git apply --reverse --check "$p" 2>/dev/null; then echo "already in PipeWire $VER: ${p##*/}"
	else echo "patch does not apply to PipeWire $VER: ${p##*/} — a newer one is needed" >&2; exit 1; fi
done
if [ "$n" = 0 ]; then
	echo "every patch is already in PipeWire $VER — the patched plugin is no longer needed"
	[ ! -e "$DROPIN" ] || { rm -f "$DROPIN"; systemctl --user daemon-reload; ! in_session || systemctl --user restart wireplumber; }
	exit 0
fi

echo "building libspa-bluez5.so for PipeWire $VER…"
rm -rf build
meson setup build --prefix=/usr --buildtype=release -Dauto_features=disabled -Dspa-plugins=enabled -Dbluez5=enabled \
	-Dbluez5-backend-hsp-native=enabled -Dbluez5-backend-hfp-native=enabled -Dbluez5-backend-ofono=enabled -Dbluez5-backend-hsphfpd=enabled \
	-Dbluez5-codec-lc3=enabled -Dbluez5-codec-opus=enabled -Dopus=enabled -Dlibusb=enabled -Ddbus=enabled -Dtests=disabled -Dexamples=disabled \
	-Dsession-managers='[]' >/dev/null
ninja -C build spa/plugins/bluez5/libspa-bluez5.so >/dev/null
install -Dm755 build/spa/plugins/bluez5/libspa-bluez5.so "$DEST/bluez5/libspa-bluez5.so"
echo "$VER" > "$DEST/version"
install -d "${DROPIN%/*}"
printf '# Patched bluez5 plugin for PipeWire %s (volmixer addons/install.sh): fixes the microphone\n# on headsets that send AT+BCC while opening the audio channel. Re-run the script after a\n# PipeWire upgrade. Rollback: delete this file, run systemctl --user daemon-reload && systemctl --user restart wireplumber.\n[Service]\nEnvironment=SPA_PLUGIN_DIR=%s:%s\n' \
	"$VER" "$DEST" "${SYSLIB%/bluez5/*}" > "$DROPIN"
systemctl --user daemon-reload
in_session || { echo "no graphical session — the plugin will be picked up on next login"; exit 0; }
systemctl --user restart wireplumber; sleep 4
grep -q "$DEST/bluez5/libspa-bluez5.so" "/proc/$(systemctl --user show wireplumber -p MainPID --value)/maps" \
	|| { rm -f "$DROPIN"; systemctl --user daemon-reload; systemctl --user restart wireplumber; echo "WirePlumber did not load the patched plugin — rolled back" >&2; exit 1; }
# After the restart a connected headset is left with the HFP profile only — reconnect it so A2DP comes back.
for m in $(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}'); do bluetoothctl --timeout 12 connect "$m" >/dev/null 2>&1 || true; done
echo "bluez5 patch for PipeWire $VER installed"

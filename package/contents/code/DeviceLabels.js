.pragma library

/*
	DeviceLabels — detects a device's connection type and derives a short label
	key for the mixer. Supports JACK (3.5 mm), USB, Bluetooth, HDMI and built-in
	devices.
*/

// Connection types.
var CONN_JACK = 'jack'
var CONN_USB = 'usb'
var CONN_BLUETOOTH = 'bluetooth'
var CONN_HDMI = 'hdmi'
var CONN_INTERNAL = 'internal'
var CONN_UNKNOWN = 'unknown'

// i18n keys; MixerItem receives one of these and asks i18n() to translate it.
var KEY_JACK_MIC = 'JACK_MIC'
var KEY_JACK_HEADSET = 'JACK_HEADSET'
var KEY_JACK_SPEAKER = 'JACK_SPEAKER'
var KEY_USB_HEADSET = 'USB_HEADSET'
var KEY_USB_MIC = 'USB_MIC'
var KEY_BLUETOOTH_HEADSET = 'BLUETOOTH_HEADSET'
var KEY_BLUETOOTH_MIC = 'BLUETOOTH_MIC'
var KEY_HDMI = 'HDMI'
var KEY_INTERNAL_MIC = 'INTERNAL_MIC'
var KEY_INTERNAL_SPEAKER = 'INTERNAL_SPEAKER'
var KEY_MIC = 'MIC'
var KEY_HEADSET = 'HEADSET'
var KEY_SPEAKER = 'SPEAKER'

function getPortDescription(po) {
	if (!po || !po.ports || po.activePortIndex < 0 || po.activePortIndex >= po.ports.length) return ''
	var port = po.ports[po.activePortIndex]
	return ((port && port.description) || '').toLowerCase()
}

function getPortName(po) {
	if (!po || !po.ports || po.activePortIndex < 0 || po.activePortIndex >= po.ports.length) return ''
	var port = po.ports[po.activePortIndex]
	return ((port && port.name) || '').toLowerCase()
}

function getDescription(po) {
	return ((po && po.description) || '').toLowerCase()
}

// Built-in digital microphone (Digital Microphone, dmic) is NOT a JACK device.
// "cAVS" is the name of an Intel platform and also appears on the jack
// microphone ("Raptor Lake cAVS Stereo Microphone"), so we don't treat it as a
// signal of a digital built-in.
function isBuiltInDigitalMic(po) {
	var portDesc = getPortDescription(po)
	var portName = getPortName(po)
	var desc = getDescription(po)
	if (portDesc.indexOf('digital') >= 0 || desc.indexOf('digital') >= 0) return true
	if (desc.indexOf('dmic') >= 0) return true
	if (portName.indexOf('dmic') >= 0 || portName.indexOf('differential') >= 0) return true
	return false
}

// Checks whether a device is plugged in via a 3.5 mm jack.
// Covers "Headphones Stereo Microphone", "Headset Mic", "analog-input-headset" etc.
function isJackDevice(po) {
	if (!po || !po.name) return false
	if (isBuiltInDigitalMic(po)) return false // Digital Microphone — built-in, not Jack.
	var name = ('' + po.name).toLowerCase()
	if (name.indexOf('usb-') >= 0 || name.indexOf('bluez_') === 0) return false
	var portDesc = getPortDescription(po)
	var portName = getPortName(po)
	var desc = getDescription(po)
	// Don't match on 'analog' — it also hits built-ins (analog-input-differential).
	// The Russian word 'гарнитура' is kept because PipeWire reports device
	// descriptions in the user's locale.
	var jackHints = ['headphones', 'headset', 'гарнитура', 'stereo microphone', 'line out', 'line in']
	for (var i = 0; i < jackHints.length; i++) {
		if (portDesc.indexOf(jackHints[i]) >= 0 || portName.indexOf(jackHints[i]) >= 0 || desc.indexOf(jackHints[i]) >= 0) return true
	}
	// analog-output-headphones, analog-input-headset
	if (portName.indexOf('headphones') >= 0 || portName.indexOf('headset') >= 0) return true
	return false
}

// Bluetooth device type: headset (over-ear/on-ear or headset+mic combo), tws
// (true wireless earbuds), compact (compact speaker), sub (speaker with
// subwoofer); '' — no answer yet (the applet shows a "?" and asks). The answer
// is stored in the btKinds setting, keyed on device.name, which is shared
// between the device's sink and source. The Bluetooth class (device.form_factor)
// is only a hint: for example, the Tronsmart Element T6 Plus advertises class
// 0x240404 "Wearable Headset" with a Handsfree microphone.
var BT_KINDS = ['headset', 'tws', 'compact', 'sub']
function cardName(po) { return (po && po.properties && po.properties['device.name']) || '' }
function guessBtKind(po) {
	var ff = (po && po.properties && po.properties['device.form_factor']) || ''
	if (['speaker', 'portable', 'hifi', 'car'].indexOf(ff) >= 0) return 'compact'
	if (['headphone', 'headset', 'hands-free'].indexOf(ff) >= 0) return 'headset'
	return ''
}
// `kinds` is the btKinds setting {card: {kind, name}}; `policy` is btNewDevice:
// ask | auto (by class) | headset.
function btKind(po, kinds, policy) {
	if (getConnectionType(po) !== CONN_BLUETOOTH) return ''
	var e = kinds && kinds[cardName(po)]
	if (e && BT_KINDS.indexOf(e.kind) >= 0) return e.kind
	if (policy === 'headset') return 'headset'
	if (policy === 'auto') return guessBtKind(po) || 'headset'
	return ''
}
function isBtSpeakerKind(kind) { return kind === 'compact' || kind === 'sub' }
// Icon by kind: over-ear headphones, earbuds, cylinder speaker, speaker-with-sub
// box; without an answer, the Bluetooth rune icon (MixerItem draws the "?" badge).
function btKindIcon(kind) {
	return { headset: 'headphones', tws: 'bluetooth', compact: 'btspeaker', sub: 'btsub' }[kind] || 'btrune'
}

// Device considered a "headset" by the auto-switching logic: Bluetooth or USB
// device, or a device whose description contains "headset" or "гарнитура" (as
// in the old fork). Output monitors (*.monitor) are not devices. For Bluetooth
// the btKind type further refines what counts as a headset.
function isHeadset(po) {
	if (!po || !po.name) return false
	var name = '' + po.name
	if (name.slice(-8) === '.monitor') return false
	var conn = getConnectionType(po)
	if (conn === CONN_BLUETOOTH || conn === CONN_USB) return true
	var desc = ('' + (po.description || '')).toLowerCase()
	// 'гарнитура' is kept because PipeWire reports device descriptions in the
	// user's locale.
	return desc.indexOf('headset') >= 0 || desc.indexOf('гарнитура') >= 0
}

// Browser recording stream — matched by the process binary name
// (application.process.binary). Chromium-based browsers also call the recording
// client "<Name> input", but so do Electron apps (Discord, Cursor), so the
// suffix alone is not a reliable signal.
var BROWSER_BINARIES = ['yandex_browser', 'chrome', 'google-chrome', 'chromium', 'chromium-browser', 'brave', 'vivaldi-bin', 'opera',
	'msedge', 'firefox', 'firefox-bin', 'firefox-esr', 'librewolf']
function isBrowserStream(po) {
	var props = (po && po.properties) || {}
	return BROWSER_BINARIES.indexOf(String(props['application.process.binary'] || '').toLowerCase()) >= 0
}

function getConnectionType(po) {
	if (!po || !po.name) return CONN_UNKNOWN
	var name = '' + po.name
	if (name.indexOf('bluez_') === 0 || name.indexOf('bluez_input.') === 0 || name.indexOf('bluez_output.') === 0) return CONN_BLUETOOTH
	if (name.indexOf('usb-') >= 0) return CONN_USB
	// PulseAudio: alsa_output...hdmi-stereo; PipeWire/UCM: ...HiFi__HDMI1__sink,
	// with description "HDMI / DisplayPort 1 Output".
	if (name.toLowerCase().indexOf('hdmi') >= 0 || getDescription(po).indexOf('hdmi') >= 0 || getDescription(po).indexOf('displayport') >= 0) return CONN_HDMI
	// Built-in speakers: Speaker port, not Headphones — Raptor Lake cAVS reports
	// "Speaker + Headphones" when playing to the speakers.
	if (name.indexOf('alsa_output.') === 0) {
		var portDesc = getPortDescription(po)
		if (portDesc.indexOf('speaker') >= 0 && portDesc.indexOf('headphones') < 0) return CONN_INTERNAL
	}
	if (isJackDevice(po)) return CONN_JACK
	if (name.indexOf('alsa_input.') === 0 || name.indexOf('alsa_output.') === 0) return CONN_INTERNAL
	return CONN_UNKNOWN
}

// Returns the short-label key, or null when MixerItem should fall back to its
// own logic.
function getShortLabelKey(po, mixerItemType) {
	if (!po || !po.name) return null
	var conn = getConnectionType(po)
	var name = ('' + po.name).toLowerCase()

	if (mixerItemType === 'Source') {
		if (conn === CONN_JACK) return KEY_JACK_MIC
		if (conn === CONN_USB && (name.indexOf('alsa_input.usb-') >= 0 || (po.properties && po.properties['device.form_factor'] === 'headset'))) return KEY_USB_MIC
		// Bluetooth: keep the device's own description.
		if (conn === CONN_BLUETOOTH) return null
		if (conn === CONN_INTERNAL) {
			var portDesc = getPortDescription(po)
			var desc = getDescription(po)
			if (portDesc.indexOf('digital') >= 0 || desc.indexOf('digital') >= 0) return KEY_INTERNAL_MIC
			if (portDesc.indexOf('headphones') >= 0 || portDesc.indexOf('headset') >= 0 || desc.indexOf('headphones') >= 0 || desc.indexOf('headset') >= 0) return KEY_JACK_MIC
		}
	}

	if (mixerItemType === 'Sink') {
		if (conn === CONN_JACK) return KEY_JACK_HEADSET
		if (conn === CONN_USB && (name.indexOf('alsa_output.usb-') >= 0 || (po.properties && po.properties['device.form_factor'] === 'headset'))) return KEY_USB_HEADSET
		// Bluetooth: keep the device's own description.
		if (conn === CONN_BLUETOOTH) return null
		if (conn === CONN_HDMI) return KEY_HDMI
		if (conn === CONN_INTERNAL) return KEY_INTERNAL_SPEAKER
	}

	return null
}

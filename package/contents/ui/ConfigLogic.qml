import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.volume
import "../code/DeviceLabels.js" as DeviceLabels

// "Logic" page: what to do when a headset is connected or disconnected (the actual behaviour
// lives in headsetLogic in main.qml).
KCM.SimpleKCM {
    id: page

    property alias cfg_headsetSwitchSink: headsetSwitchSink.checked
    property alias cfg_headsetSwitchSource: headsetSwitchSource.checked
    property alias cfg_headsetSetVolume: headsetSetVolume.checked
    property alias cfg_headsetVolumePercent: headsetVolumePercent.value
    property alias cfg_headsetPauseMedia: headsetPauseMedia.checked
    property string cfg_fallbackSink
    property string cfg_fallbackSource
    property string cfg_pinBrowserSource
    property alias cfg_speakerSwitchSink: speakerSwitchSink.checked
    property alias cfg_callSwitchProfile: callSwitchProfile.checked

    // Device lists: for "fall back to" — every non-headset; for pinning a stream — every
    // device (withHeadsets). The key is the PulseAudio name.
    // poRole: KRoleNames only works as an attached property of the model itself.
    SinkModel { id: cfgSinks; readonly property int poRole: KItemModels.KRoleNames.role("PulseObject") }
    SourceModel { id: cfgSources; readonly property int poRole: KItemModels.KRoleNames.role("PulseObject") }
    function deviceList(model, current, autoText, withHeadsets) {
        const list = [{ text: autoText, value: "" }]
        let found = current === ""
        for (let i = 0; i < model.count; ++i) {
            const po = model.data(model.index(i, 0), model.poRole)
            if (!po || (!withHeadsets && DeviceLabels.isHeadset(po)) || String(po.name).endsWith(".monitor")) continue
            list.push({ text: po.description, value: po.name })
            if (po.name === current) found = true
        }
        if (!found) list.push({ text: i18nc("common.disconnected", "%1 (currently disconnected)", current), value: current })
        return list
    }

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: headsetSwitchSink
            Kirigami.FormData.label: i18nc("logic.headset-connect.label", "When a headset is connected:")
            text: i18nc("logic.switch-sinks", "switch the speakers to it")
        }
        QQC2.CheckBox {
            id: headsetSwitchSource
            text: i18nc("logic.switch-source", "switch the microphone to it")
        }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.CheckBox { id: headsetSetVolume; text: i18nc("logic.set-volume", "set its volume") }
            QQC2.SpinBox { id: headsetVolumePercent; from: 0; to: 100; stepSize: 5; enabled: headsetSetVolume.checked; textFromValue: (v) => v + " %"; valueFromText: (t) => parseInt(t) }
        }
        QQC2.ComboBox {
            id: fallbackSink
            Kirigami.FormData.label: i18nc("logic.headset-disconnect-sink.label", "When the headset is removed, speakers:")
            textRole: "text"
            valueRole: "value"
            model: page.deviceList(cfgSinks, page.cfg_fallbackSink, i18nc("logic.fallback-sink-builtin", "Built-in (automatically)"))
            onActivated: page.cfg_fallbackSink = currentValue
            function sync() { currentIndex = Math.max(0, indexOfValue(page.cfg_fallbackSink)) }
            onModelChanged: sync()
            Component.onCompleted: sync()
        }
        QQC2.ComboBox {
            id: fallbackSource
            Kirigami.FormData.label: i18nc("logic.headset-disconnect-source.label", "When the headset is removed, microphone:")
            textRole: "text"
            valueRole: "value"
            model: page.deviceList(cfgSources, page.cfg_fallbackSource, i18nc("logic.fallback-source-builtin", "Built-in (automatically)"))
            onActivated: page.cfg_fallbackSource = currentValue
            function sync() { currentIndex = Math.max(0, indexOfValue(page.cfg_fallbackSource)) }
            onModelChanged: sync()
            Component.onCompleted: sync()
        }
        QQC2.CheckBox {
            id: headsetPauseMedia
            Kirigami.FormData.label: i18nc("logic.pause.label", "When the audio source changes:")
            text: i18nc("logic.pause.pause", "pause currently playing media")
        }
        QQC2.CheckBox {
            id: speakerSwitchSink
            Kirigami.FormData.label: i18nc("logic.speaker-connect.label", "When a speaker is connected:")
            text: i18nc("logic.switch-sinks", "switch the speakers to it")
        }
        QQC2.Label {
            text: i18nc("logic.speaker-tooltip", "A speaker only takes over the speakers; the applet does not touch its microphone or volume. What counts as a speaker vs. a headset is set on the Devices page; a device without an answer to “what is it” is left alone by automation.")
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        QQC2.CheckBox {
            id: callSwitchProfile
            Kirigami.FormData.label: i18nc("logic.call.label", "During a call, when a Bluetooth microphone is selected:")
            text: i18nc("logic.call.switch-profile", "switch the device into headset mode")
        }
        QQC2.Label {
            text: i18nc("logic.call.tooltip", "“Call” means there are active recording streams. If the device’s card is in music mode (A2DP, which has no microphone), it is switched to the best headset mode (mSBC, otherwise CVSD) and streams from the previous microphone are moved to the new one. When recording stops, WirePlumber restores music mode on its own. Outside of calls nothing changes — headset mode degrades sound quality.")
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        QQC2.ComboBox {
            id: pinBrowserSource
            Kirigami.FormData.label: i18nc("logic.pin-browser.label", "Pin the browser recording stream to:")
            textRole: "text"
            valueRole: "value"
            model: page.deviceList(cfgSources, page.cfg_pinBrowserSource, i18nc("logic.pin-browser.none", "Don’t pin"), true)
            onActivated: page.cfg_pinBrowserSource = currentValue
            function sync() { currentIndex = Math.max(0, indexOfValue(page.cfg_pinBrowserSource)) }
            onModelChanged: sync()
            Component.onCompleted: sync()
        }
        QQC2.Label {
            text: i18nc("logic.pin-browser.tooltip", "Browsers (Yandex, Chrome, Firefox, …) often keep a microphone recording stream open permanently — a voice assistant or a tab with permission — and drag it onto the headset: the headset drops into headset mode and never returns to music. A stream pinned to another microphone leaves the headset alone.")
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: i18nc("logic.footer-tooltip", "“Headset” here means a Bluetooth or USB device. Headphones plugged into a jack don’t add a device, they switch the port, so this logic does not apply to them.")
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}

/*
    SPDX-FileCopyrightText: 2014-2015 Harald Sitter <sitter@kde.org>
    SPDX-FileCopyrightText: 2026 AIKDE

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL

    Fork of the stock Plasma 6 volume applet (plasma-pa 6.6.5, applet/main.qml).
    Mechanics are untouched: models, menu, OSD, hotkeys, drag&drop. Only the look has changed:
    instead of the "Devices / Applications" tabs, four groups sit side by side with vertical
    sliders (Windows 7 style).
*/

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid

import org.kde.kcmutils as KCMUtils
import org.kde.config as KConfig

import org.kde.plasma.private.volume
import org.kde.plasma.private.mpris as Mpris
import org.kde.plasma.plasma5support as P5Support
import "../code/DeviceLabels.js" as DeviceLabels

PlasmoidItem {
    id: main

    GlobalConfig {
        id: config
    }

    property bool volumeFeedback: config.audioFeedback
    property bool globalMuteSinks: config.globalMuteSinks
    property bool globalMuteSources: config.globalMuteSources
    property string displayName: i18nc("plasmoid.display-name", "Volume")
    property QtObject draggedStream: null
    property string draggedStreamType: ""   // "sink-input" | "source-output"

    property bool showVirtualDevices: Plasmoid.configuration.showVirtualDevices
    // Bluetooth device types (the "what is it" answer): card name → {kind, name}.
    // Written both by the "?" menu in MixerItem and by the Devices page.
    readonly property var btKinds: { try { return JSON.parse(Plasmoid.configuration.btKinds || "{}") } catch (e) { return {} } }
    function btKindOf(po) { return DeviceLabels.btKind(po, btKinds, Plasmoid.configuration.btNewDevice) }
    // Answer from the "?" menu: store it and immediately run the connection logic for this
    // device, because the device is already connected.
    function setBtKind(po, kind) {
        const kinds = Object.assign({}, btKinds)
        kinds[DeviceLabels.cardName(po)] = { kind: kind, name: po.description }
        Plasmoid.configuration.btKinds = JSON.stringify(kinds)
        headsetLogic.applyKind(DeviceLabels.cardName(po))
    }
    readonly property int itemWidth: Plasmoid.configuration.itemWidth
    readonly property int sliderHeight: Plasmoid.configuration.sliderHeight

    readonly property bool inPanel: (Plasmoid.location === PlasmaCore.Types.TopEdge
        || Plasmoid.location === PlasmaCore.Types.RightEdge
        || Plasmoid.location === PlasmaCore.Types.BottomEdge
        || Plasmoid.location === PlasmaCore.Types.LeftEdge)
    readonly property bool compactInPanel: inPanel && !!compactRepresentationItem?.visible

    // DEFAULT_SINK_NAME in module-always-sink.c
    readonly property string dummyOutputName: "auto_null"
    readonly property bool contextIsReady: Context.state === Context.State.Ready
    readonly property string noDevicePlaceholderMessage: {
        if (!contextIsReady) {
            return i18nc("@label plasmoid.err.lost", "Connection to the sound service was lost")
        }
        return i18nc("plasmoid.err.no-devices", "No output or input devices found")
    }
    readonly property string noDeviceExplanation: {
        if (!contextIsReady && Context.autoConnecting) {
            return i18nc("@info plasmoid.err.reconnecting", "Reconnecting…")
        }
        return ""
    }

    switchHeight: Kirigami.Units.gridUnit * 8
    switchWidth: Kirigami.Units.gridUnit * 14

    Plasmoid.icon: controlSink && !isDummyOutput(controlSink) ? AudioIcon.forVolume(volumePercent(controlSink.volume), controlSink.muted, "")
                                                              : AudioIcon.forVolume(0, true, "")
    hideOnWindowDeactivate: !Plasmoid.configuration.pin
    toolTipMainText: {
        var sink = controlSink
        if (!sink || isDummyOutput(sink)) {
            return displayName;
        }

        if (sink.muted) {
            return i18nc("plasmoid.tooltip.muted", "Sound is muted");
        } else {
            return i18nc("plasmoid.tooltip.volume", "Volume %1%", volumePercent(sink.volume));
        }
    }
    toolTipSubText: {
        let lines = [];

        if (controlSink && paSinkFilterModel.count > 1 && !isDummyOutput(controlSink)) {
            lines.push(nodeName(controlSink))
        }

        if (paSinkFilterModel.count > 0) {
            lines.push(main.globalMuteSinks ? i18nc("plasmoid.tooltip.middle-unmute", "Middle click: unmute")
                                    : i18nc("plasmoid.tooltip.middle-mute", "Middle click: mute everything"));
            lines.push(i18nc("plasmoid.tooltip.wheel", "Scroll wheel: change volume"));
        } else {
            lines.push(main.noDevicePlaceholderMessage);
        }
        return lines.join("\n");
    }

    function nodeName(pulseObject) {
        if (pulseObject.description) {
            return pulseObject.description
        }

        if (pulseObject.name) {
            return pulseObject.name
        }

        return i18nc("plasmoid.err.no-device-name", "Device name not found")
    }

    function isDummyOutput(output) {
        return output && output.name === dummyOutputName;
    }

    function volumePercent(volume) {
        return Math.round(volume / PulseAudio.NormalVolume * 100.0);
    }

    function playFeedback(sinkIndex) {
        if (!volumeFeedback) {
            return;
        }
        if (sinkIndex == undefined) {
            if (!controlSink) {
                return;
            }
            sinkIndex = controlSink.index;
        }
        feedback.play(sinkIndex);
    }

    // Device driven by the panel icon and its scroll wheel: the default sink (checkmark in
    // the mixer). plasma-pa's PreferredDevice is "the first Running sink", so the default sink
    // only wins when it's actually playing — after a speaker connects, its node is Running and
    // the wheel ended up controlling the speaker instead of the ticked device. kded still
    // drives the volume hotkeys by plasma-pa's rules; those are unaffected.
    property var defaultSink: null
    readonly property var controlSink: defaultSink || PreferredDevice.sink
    function updateDefaultSink() { defaultSink = headsetLogic.find(paSinkModel, p => p.default) }
    Connections {
        target: paSinkModel
        function onDataChanged() { main.updateDefaultSink() }
        function onRowsInserted() { main.updateDefaultSink() }
        function onRowsRemoved() { main.updateDefaultSink() }
        function onModelReset() { main.updateDefaultSink() }
    }
    // Default microphone — needed by the call logic (callLogic); compared before writing so
    // we don't emit redundant `changed` signals.
    property var defaultSource: null
    function updateDefaultSource() { const d = headsetLogic.find(paSourceModel, p => p.default); if (d !== defaultSource) defaultSource = d }
    Connections {
        target: paSourceModel
        function onDataChanged() { main.updateDefaultSource() }
        function onRowsInserted() { main.updateDefaultSource() }
        function onRowsRemoved() { main.updateDefaultSource() }
        function onModelReset() { main.updateDefaultSource() }
    }
    // Wheel step mirrors kded (plasma-pa, audioshortcutsservice.cpp): step from the sound
    // settings, 150 % ceiling when "Raise maximum volume" is on, zero means mute, OSD via
    // plasmashell over D-Bus, plus a confirmation sound.
    function stepVolume(deltaPercent) {
        const sink = controlSink
        if (!sink || isDummyOutput(sink)) return
        const maxPercent = config.raiseMaximumVolume ? 150 : 100
        const percent = Math.max(0, Math.min(maxPercent, volumePercent(sink.volume) + deltaPercent))
        sink.muted = percent === 0
        sink.volume = Math.round(PulseAudio.NormalVolume * percent / 100)
        if (config.volumeOsd) osd.connectSource("qdbus6 org.kde.plasmashell /org/kde/osdService org.kde.osdService.volumeChanged " + percent + " " + maxPercent)
        playFeedback(sink.index)
    }
    P5Support.DataSource { id: osd; engine: "executable"; onNewData: (source) => disconnectSource(source) }

    // Output devices
    // poRole: the PulseObject role number — KRoleNames only works as an attached property
    // of the model itself.
    readonly property SinkModel paSinkModel: SinkModel { id: paSinkModel; readonly property int poRole: KItemModels.KRoleNames.role("PulseObject") }

    // Input devices
    readonly property SourceModel paSourceModel: SourceModel { id: paSourceModel; readonly property int poRole: KItemModels.KRoleNames.role("PulseObject") }

    // Confusingly, Sink Input is what PulseAudio calls streams that send audio to an output device
    readonly property SinkInputModel paSinkInputModel: SinkInputModel { id: paSinkInputModel }

    // Confusingly, Source Output is what PulseAudio calls streams that take audio from an input device
    readonly property SourceOutputModel paSourceOutputModel: SourceOutputModel { id: paSourceOutputModel; readonly property int poRole: KItemModels.KRoleNames.role("PulseObject") }

    // active output devices
    readonly property PulseObjectFilterModel paSinkFilterModel: PulseObjectFilterModel {
        id: paSinkFilterModel
        filterOutInactiveDevices: true
        filterVirtualDevices: !main.showVirtualDevices
        sourceModel: paSinkModel
    }

    // active input devices
    readonly property PulseObjectFilterModel paSourceFilterModel: PulseObjectFilterModel {
        id: paSourceFilterModel
        filterOutInactiveDevices: true
        filterVirtualDevices: !main.showVirtualDevices
        sourceModel: paSourceModel
    }

    // non-virtual streams going to output devices
    readonly property PulseObjectFilterModel paSinkInputFilterModel: PulseObjectFilterModel {
        id: paSinkInputFilterModel
        filters: [
            { role: "VirtualStream", value: false },
            { role: "Client", value: (client) => client.name !== "libcanberra" },
        ]
        sourceModel: paSinkInputModel
    }

    // Notification sounds: the volume for the "event" stream-restore role, same as the
    // "Sound" KCM.
    readonly property PulseObjectFilterModel paEventStreamModel: PulseObjectFilterModel {
        filters: [ { role: "Name", value: "sink-input-by-media-role:event" } ]
        sourceModel: StreamRestoreModel {}
    }

    // non-virtual streams coming from input devices
    readonly property PulseObjectFilterModel paSourceOutputFilterModel: PulseObjectFilterModel {
        id: paSourceOutputFilterModel
        filters: [ { role: "VirtualStream", value: false } ]
        sourceModel: paSourceOutputModel
    }

    readonly property CardModel paCardModel: CardModel {
        id: paCardModel
        readonly property int poRole: KItemModels.KRoleNames.role("PulseObject")

        function indexOfCardNumber(cardNumber) {
            const indexRole = KItemModels.KRoleNames.role("Index");
            for (let idx = 0; idx < count; ++idx) {
                if (data(index(idx, 0), indexRole) === cardNumber) {
                    return index(idx, 0);
                }
            }
            return index(-1, 0);
        }
    }

    // ---------- Logic: headsets and speakers ----------
    // A new row in the raw devices model = a connection. A headset (USB; Bluetooth with kind
    // headset/tws, see DeviceLabels.btKind): per the settings, make it the default device and
    // set its volume. A speaker (Bluetooth compact/sub): take over the speakers only, leave
    // the device's microphone and volume alone. A Bluetooth device without a "what is it"
    // answer is left entirely alone; answering through the "?" menu triggers the same logic
    // (applyKind). A device going away triggers a fall-back to the device named in the
    // settings (empty = built-in). Initial model population isn't a connection: the logic
    // only kicks in 2 s after the last new row.
    // ponytail: acts purely on device appear/disappear, with no retry timers from the old
    // fork; if PipeWire still isn't ready to accept the default after 0.8 s, no switch
    // happens.
    Item {
        id: headsetLogic
        property bool started: false
        property var pending: []
        // Initial model population: rows arrive in a burst, and each one defers the logic's
        // start by another 2 s. A fixed 3 s wasn't enough — after plasmashell restarts
        // PulseAudio connects a bit later, every device was counted as freshly connected and
        // the defaults drifted onto the last one.
        Timer { id: settle; interval: 2000; running: true; onTriggered: headsetLogic.started = true }
        function sawRows() { if (!started) settle.restart() }
        Timer {
            id: headsetDelay
            interval: 800
            onTriggered: { const fns = headsetLogic.pending; headsetLogic.pending = []; fns.forEach(f => f()) }
        }
        function later(fn) { pending.push(fn); headsetDelay.restart() }
        // Our own default-device changes are time-stamped so callLogic can tell them apart
        // from a user's selection.
        property double lastAuto: 0
        function setDefault(dev) { lastAuto = Date.now(); dev.default = true }
        // Safety net: when plasmashell is going down (restart, logout), devices disappear
        // from the model exactly as they would on a real disconnect, and the previous applet
        // copy could switch the defaults to the fallbacks within 800 ms — so the logic is
        // turned off on shutdown.
        Connections { target: Qt.application; function onAboutToQuit() { headsetLogic.started = false } }
        Component.onDestruction: started = false
        // WirePlumber 0.5 pauses players on its own when their device goes away
        // (linking.pause-playback, on by default) — turn it off with --save so that only our
        // "When the audio source changes" setting controls pausing.
        P5Support.DataSource {
            engine: "executable"
            onNewData: (source) => disconnectSource(source)
            Component.onCompleted: connectSource("wpctl settings --save linking.pause-playback false")
        }
        // MPRIS players (browsers, Elisa, …); the "container" role is the player itself.
        Mpris.Mpris2Model { id: mpris; readonly property int containerRole: KItemModels.KRoleNames.role("container") }
        // ponytail: every playing player is paused — MPRIS doesn't know which device a
        // player plays into. The multiplexer row duplicates the active player; a repeated
        // Pause is harmless.
        function pauseMedia() {
            if (!Plasmoid.configuration.headsetPauseMedia) return
            for (let i = 0; i < mpris.rowCount(); ++i) {
                const p = mpris.data(mpris.index(i, 0), mpris.containerRole)
                if (p && p.canPause && p.playbackStatus === Mpris.PlaybackStatus.Playing) p.Pause()
            }
        }
        function objectAt(model, row) { return model.data(model.index(row, 0), model.poRole) }
        function find(model, pred) {
            for (let i = 0; i < model.count; ++i) { const po = objectAt(model, i); if (po && pred(po)) return po }
            return null
        }
        function fallbackDevice(model, wantedName) {
            if (wantedName !== "") { const po = find(model, p => p.name === wantedName); if (po) return po }
            return find(model, p => !DeviceLabels.isHeadset(p) && !String(p.name).endsWith(".monitor")
                && DeviceLabels.getConnectionType(p) === DeviceLabels.CONN_INTERNAL)
        }
        // Device role: "headset" — full headset logic; "speaker" — speakers only, and only
        // if enabled; null — not ours (built-in, monitor, or Bluetooth without an answer).
        function roleOf(po, isSink) {
            if (!po || String(po.name).endsWith(".monitor")) return null
            if (DeviceLabels.getConnectionType(po) === DeviceLabels.CONN_BLUETOOTH) {
                const kind = main.btKindOf(po)
                if (kind === "") return null
                if (DeviceLabels.isBtSpeakerKind(kind)) return isSink && Plasmoid.configuration.speakerSwitchSink ? "speaker" : null
                return "headset"
            }
            return DeviceLabels.isHeadset(po) ? "headset" : null
        }
        function connected(model, first, last, isSink) {
            if (!started) return
            for (let row = first; row <= last; ++row) handle(model, objectAt(model, row), isSink)
        }
        function handle(model, po, isSink) {
            const role = roleOf(po, isSink)
            if (!role) return
            // Pause now: WirePlumber may switch audio to the device on its own without
            // waiting for us.
            if (isSink && (role === "speaker" || Plasmoid.configuration.headsetSwitchSink)) pauseMedia()
            const name = po.name
            later(() => {
                const dev = find(model, p => p.name === name)
                if (!dev) return
                if (role === "speaker") { setDefault(dev); return }
                if (isSink && Plasmoid.configuration.headsetSetVolume) {
                    dev.volume = Math.round(PulseAudio.NormalVolume * Plasmoid.configuration.headsetVolumePercent / 100)
                }
                if (isSink ? Plasmoid.configuration.headsetSwitchSink : Plasmoid.configuration.headsetSwitchSource) {
                    setDefault(dev)
                }
            })
        }
        // A "what is it" answer for an already connected device is treated as if the device
        // had just arrived.
        function applyKind(card) {
            [[paSinkModel, true], [paSourceModel, false]].forEach(([model, isSink]) => {
                const po = find(model, p => DeviceLabels.cardName(p) === card && !String(p.name).endsWith(".monitor"))
                if (po) handle(model, po, isSink)
            })
        }
        function disconnecting(model, first, last, isSink) {
            if (!started) return
            for (let row = first; row <= last; ++row) {
                const po = objectAt(model, row)
                // Falling back to the saved device only makes sense if the device that went
                // away was the current default.
                if (!roleOf(po, isSink) || !po.default) continue
                // Pause before switching: otherwise music would start playing on the
                // speakers.
                if (isSink) pauseMedia()
                later(() => {
                    const dev = fallbackDevice(model, isSink ? Plasmoid.configuration.fallbackSink : Plasmoid.configuration.fallbackSource)
                    if (dev && !dev.default) setDefault(dev)
                })
            }
        }
        Connections {
            target: paSinkModel
            function onRowsInserted(parent, first, last) { headsetLogic.sawRows(); headsetLogic.connected(paSinkModel, first, last, true) }
            function onRowsAboutToBeRemoved(parent, first, last) { headsetLogic.disconnecting(paSinkModel, first, last, true) }
        }
        Connections {
            target: paSourceModel
            function onRowsInserted(parent, first, last) { headsetLogic.sawRows(); headsetLogic.connected(paSourceModel, first, last, false) }
            function onRowsAboutToBeRemoved(parent, first, last) { headsetLogic.disconnecting(paSourceModel, first, last, false) }
        }
    }

    // ---------- Logic: browser recording stream ----------
    // A browser keeps a microphone recording stream open permanently (voice assistant, a tab
    // with permission) and, through its target.object, drags it onto the headset — then
    // WirePlumber puts the headset into HFP and refuses to come back to A2DP while the stream
    // is alive. The "Pin the browser recording stream" setting moves such streams to the
    // chosen microphone when the stream appears, when a device appears, and when the setting
    // changes. WirePlumber remembers that move per application on its own (restore.stream);
    // we repeat it in case the browser explicitly asks for the headset again.
    // ponytail: the browser is detected by its process name from the list in
    // DeviceLabels.isBrowserStream.
    Item {
        id: browserPin
        readonly property string sourceName: Plasmoid.configuration.pinBrowserSource
        function apply(stream) {
            if (sourceName === "" || !stream || !DeviceLabels.isBrowserStream(stream)) return
            const src = headsetLogic.find(paSourceModel, p => p.name === sourceName)
            if (src && stream.deviceIndex !== src.index) stream.deviceIndex = src.index
        }
        function applyAll() { for (let i = 0; i < paSourceOutputModel.count; ++i) apply(headsetLogic.objectAt(paSourceOutputModel, i)) }
        onSourceNameChanged: applyAll()
        Connections {
            target: paSourceOutputModel
            function onRowsInserted(parent, first, last) { for (let r = first; r <= last; ++r) browserPin.apply(headsetLogic.objectAt(paSourceOutputModel, r)) }
        }
        // A device appeared (including during initial model population) — streams might
        // have been waiting for exactly this one.
        Connections {
            target: paSourceModel
            function onRowsInserted(parent, first, last) { headsetLogic.later(() => browserPin.applyAll()) }
        }
    }

    // ---------- Logic: calls and microphone switching ----------
    // During a call (active recording streams exist), the user picks a microphone belonging to
    // a Bluetooth device whose card is in A2DP — the profile has no microphone, and
    // WirePlumber doesn't switch to HFP on its own (a stream won't link to such a source).
    // We switch the card to the best headset profile (by PipeWire priority:
    // LC3 > mSBC > CVSD) and move the streams that recorded from the previous default to the
    // new microphone — including those pinned to it: the user's choice outweighs the
    // auto-pin. WirePlumber returns the card to A2DP by itself once recording ends. Outside
    // a call (just music) — nothing happens: HFP degrades sound quality. Default-device
    // changes caused by the applet's own logic (headset connect) don't count.
    // ponytail: "a call" = any unpaused recording stream.
    Item {
        id: callLogic
        readonly property var source: main.defaultSource
        property var prevSource: null
        function activeRecordStreams() {
            const list = []
            for (let i = 0; i < paSourceOutputModel.count; ++i) {
                const s = headsetLogic.objectAt(paSourceOutputModel, i)
                if (s && !s.virtualStream && !s.corked) list.push(s)
            }
            return list
        }
        function cardOf(po) {
            const idx = paCardModel.indexOfCardNumber(po.cardIndex)
            return idx.valid ? paCardModel.data(idx, paCardModel.poRole) : null
        }
        // Index of the best available headset profile, or -1; -2 means the card is already
        // in such a profile.
        function bestHeadsetProfile(card) {
            const isHfp = p => p && String(p.name).startsWith("headset-head-unit")
            if (isHfp(card.profiles[card.activeProfileIndex])) return -2
            let best = -1
            for (let i = 0; i < card.profiles.length; ++i) {
                const p = card.profiles[i]
                if (!isHfp(p) || p.availability === Profile.Unavailable) continue
                if (best < 0 || p.priority > card.profiles[best].priority) best = i
            }
            return best
        }
        onSourceChanged: {
            const prev = prevSource
            prevSource = source
            if (!source || !Plasmoid.configuration.callSwitchProfile || Date.now() - headsetLogic.lastAuto < 1500) return
            if (DeviceLabels.getConnectionType(source) !== DeviceLabels.CONN_BLUETOOTH) return
            const streams = activeRecordStreams()
            if (streams.length === 0) return
            const card = cardOf(source)
            if (card) {
                const best = bestHeadsetProfile(card)
                if (best >= 0) card.activeProfileIndex = best
            }
            if (prev) streams.forEach(s => { if (s.deviceIndex === prev.index) s.deviceIndex = source.index })
        }
    }

    // Only exists because the default CompactRepresentation doesn't expose:
    // - scroll actions
    // - a middle-click action
    compactRepresentation: MouseArea {
        property int wheelDelta: 0
        property bool wasExpanded: false

        Layout.minimumWidth: height
        Layout.minimumHeight: width

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onPressed: mouse => {
            if (mouse.button == Qt.LeftButton) {
                wasExpanded = main.expanded;
            } else if (mouse.button == Qt.MiddleButton) {
                GlobalService.globalMuteSinks();
            }
        }
        onClicked: mouse => {
            if (mouse.button == Qt.LeftButton) {
                main.expanded = !wasExpanded;
            }
        }
        onWheel: wheel => {
            const delta = (wheel.inverted ? -1 : 1) * (wheel.angleDelta.y ? wheel.angleDelta.y : -wheel.angleDelta.x);
            if ((wheelDelta > 0 && delta < 0) || (wheelDelta < 0 && delta > 0)) {
                wheelDelta = 0;
            }
            wheelDelta += delta;

            // Magic number 120 for common "one click"; every click in one wheel event is
            // merged into a single step (one OSD, one sound). Not GlobalService: that one
            // nudges PreferredDevice through kded rather than the default device
            // (see stepVolume).
            const clicks = Math.trunc(wheelDelta / 120);
            wheelDelta -= clicks * 120;
            if (clicks !== 0) {
                main.stepVolume(clicks * ((wheel.modifiers & Qt.ShiftModifier) ? 1 : config.volumeStep));
            }
        }
        Kirigami.Icon {
            anchors.fill: parent
            source: plasmoid.icon
            active: parent.containsMouse
        }
    }

    VolumeFeedback {
        id: feedback
    }

    fullRepresentation: PlasmaExtras.Representation {
        id: fullRep

        // Content width plus the paddings of the Flickable and the Representation itself —
        // otherwise a few-pixel horizontal scrollbar shows up.
        readonly property real groupsWidth: groupsRow.implicitWidth + Kirigami.Units.smallSpacing * 2 + fullRep.leftPadding + fullRep.rightPadding + 2
        readonly property bool anyGroupVisible: recordingGroup.visible || appsGroup.visible || micsGroup.visible || speakersGroup.visible

        // The popup grows with the number of devices and applications (new items push it
        // left, with the groups pinned to the right edge). minimumWidth = preferredWidth, or
        // the popup won't re-lay-out when devices appear. Above ~70 grid units the horizontal
        // scrollbar kicks in.
        readonly property real wantedWidth: Math.max(main.switchWidth, Math.min(groupsWidth, Kirigami.Units.gridUnit * 70))
        Layout.minimumWidth: wantedWidth
        Layout.preferredWidth: wantedWidth
        // After the first close, AppletPopup (libplasma) saves the window size to the
        // config and stops reading preferredWidth, honouring only min/max — without
        // maximumWidth the popup grows but doesn't shrink when applications go away.
        Layout.maximumWidth: wantedWidth
        Layout.minimumHeight: main.switchHeight
        Layout.preferredHeight: main.sliderHeight + Kirigami.Units.gridUnit * 13

        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            rightPadding: -1

            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    level: 1
                    text: main.displayName
                    elide: Text.ElideRight
                }

                PC3.ToolButton {
                    id: actionsButton

                    visible: !(plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentDrawsPlasmoidHeading)

                    icon.name: "application-menu"
                    display: PC3.AbstractButton.IconOnly
                    checkable: true
                    checked: configMenu.status !== PlasmaExtras.Menu.Closed
                    onToggled: {
                        if (checked) {
                            configMenu.openRelative();
                        } else {
                            configMenu.close();
                        }
                    }
                    KeyNavigation.right: configureButton

                    text: i18nc("@action:button plasmoid.button.more", "More actions")
                    PC3.ToolTip {
                        text: parent.text
                    }
                }

                PlasmaExtras.Menu {
                    id: configMenu
                    visualParent: actionsButton
                    placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
                }

                Instantiator {
                    model: Plasmoid.contextualActions
                    delegate: PlasmaExtras.MenuItem {
                        id: menuItem
                        action: modelData
                    }
                    onObjectAdded: (index, object) => {
                        if (object.action.priority === PlasmaCore.Action.NormalPriority) {
                            configMenu.addMenuItem(object);
                        }
                    }
                }

                PC3.ToolButton {
                    id: configureButton
                    visible: !(plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentDrawsPlasmoidHeading)

                    icon.name: "configure"
                    onClicked: plasmoid.internalAction("configure").trigger()

                    Accessible.name: plasmoid.internalAction("configure").text
                    PC3.ToolTip {
                        text: plasmoid.internalAction("configure").text
                    }
                }

                PC3.ToolButton {
                    visible: main.compactInPanel && !(plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentDrawsPlasmoidHeading)

                    icon.name: "window-pin-symbolic"
                    text: i18nc("@action:button plasmoid.button.pin", "Keep open")
                    display: PC3.AbstractButton.IconOnly

                    checkable: true
                    checked: Plasmoid.configuration.pin
                    onToggled: Plasmoid.configuration.pin = checked

                    PC3.ToolTip.text: text
                    PC3.ToolTip.visible: hovered || activeFocus
                    PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }
        }

        contentItem: Item {
            id: contentRoot

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                contentWidth: groupsRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                PC3.ScrollBar.horizontal: PC3.ScrollBar { policy: PC3.ScrollBar.AsNeeded }

                // Same as Zren's original: right-to-left — speakers, microphones,
                // (our addition) notification sounds, applications, recording applications.
                RowLayout {
                    id: groupsRow
                    // Groups pinned to the right edge (the popup opens from the tray icon
                    // and grows leftwards), as in Zren's original.
                    x: Math.max(0, flick.width - implicitWidth)
                    // When the scrollbar is needed, keep it from overlapping the groups.
                    height: flick.height - (flick.PC3.ScrollBar.horizontal.visible ? flick.PC3.ScrollBar.horizontal.height : 0)
                    spacing: Kirigami.Units.smallSpacing

                    MixerGroup {
                        id: recordingGroup
                        title: i18nc("plasmoid.group.recording", "Recording")
                        type: "source-output"
                        model: paSourceOutputFilterModel
                        devicesModel: paSourceFilterModel
                    }
                    MixerGroup {
                        id: appsGroup
                        title: i18nc("plasmoid.group.applications", "Applications")
                        type: "sink-input"
                        model: paSinkInputFilterModel
                        devicesModel: paSinkFilterModel
                    }
                    MixerGroup {
                        title: i18nc("plasmoid.group.notifications", "Notifications")
                        type: "event"
                        model: paEventStreamModel
                    }
                    MixerGroup {
                        id: micsGroup
                        title: i18nc("plasmoid.group.microphones", "Microphones")
                        type: "source"
                        model: paSourceFilterModel
                    }
                    MixerGroup {
                        id: speakersGroup
                        title: i18nc("plasmoid.group.speakers", "Speakers")
                        type: "sink"
                        model: paSinkFilterModel
                    }
                }
            }

            Loader {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                active: visible
                visible: !fullRep.anyGroupVisible
                sourceComponent: PlasmaExtras.PlaceholderMessage {
                    iconName: "audio-volume-muted" + (Qt.application.layoutDirection === Qt.RightToLeft ? "-rtl" : "")
                    text: main.noDevicePlaceholderMessage
                    explanation: main.noDeviceExplanation
                    helpfulAction: Kirigami.Action {
                        text: i18nc("@action plasmoid.button.retry", "Retry")
                        icon.name: "view-refresh-symbolic"
                        onTriggered: Context.reconnectDaemon()
                        enabled: !Context.autoConnecting && !main.contextIsReady
                    }
                }
            }
        }

        footer: PlasmaExtras.PlasmoidHeading {
            id: footerToolbar

            readonly property int margins: Kirigami.Units.smallSpacing

            ColumnLayout {
                width: parent.width
                spacing: 0

                Kirigami.InlineMessage {
                    id: raiseMaxVolumeWarning

                    Layout.fillWidth: true
                    Layout.margins: footerToolbar.margins

                    showCloseButton: true
                    type: Kirigami.MessageType.Warning

                    text: xi18nc("@info plasmoid.boost.warning", "Prolonged use of this feature will damage the device’s speakers. Only turn it on briefly to make out a quiet recording.")
                }

                PC3.Switch {
                    id: raiseMaximumVolumeCheckbox
                    Layout.fillWidth: true
                    Layout.margins: footerToolbar.margins

                    checked: config.raiseMaximumVolume

                    text: i18nc("plasmoid.boost.enable", "Raise maximum volume")

                    onToggled: {
                        config.raiseMaximumVolume = checked;
                        config.save();
                        raiseMaxVolumeWarning.visible = checked;
                    }
                }
            }
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("plasmoid.action.mute-all-sinks", "Force-mute every playback device")
            icon.name: "audio-volume-muted" + (Qt.application.layoutDirection === Qt.RightToLeft ? "-rtl" : "");
            checkable: true
            checked: globalMuteSinks
            onTriggered: {
                GlobalService.globalMuteSinks();
            }
        },
        PlasmaCore.Action {
            text: i18nc("plasmoid.action.mute-all-sources", "Force-mute every input device")
            icon.name: "microphone-sensitivity-muted" + (Qt.application.layoutDirection === Qt.RightToLeft ? "-rtl" : "");
            checkable: true
            checked: globalMuteSources
            onTriggered: {
                GlobalService.globalMuteSources();
            }
        },
        PlasmaCore.Action {
            text: i18nc("plasmoid.action.show-virtual", "Show virtual devices")
            icon.name: "audio-card"
            checkable: true
            checked: plasmoid.configuration.showVirtualDevices
            onTriggered: Plasmoid.configuration.showVirtualDevices = !Plasmoid.configuration.showVirtualDevices
        },
        PlasmaCore.Action {
            // In the stock applet this action replaces "Configure"; here "Configure"
            // opens the view-settings page instead.
            text: i18nc("plasmoid.action.configure", "Configure audio devices…")
            icon.name: "configure"
            visible: KConfig.KAuthorized.authorizeControlModule("kcm_pulseaudio")
            onTriggered: KCMUtils.KCMLauncher.openSystemSettings("kcm_pulseaudio")
        }
    ]

    Component.onCompleted: {
        MicrophoneIndicator.init();
    }
}

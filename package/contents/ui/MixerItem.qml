/*
    SPDX-FileCopyrightText: 2014-2015 Harald Sitter <sitter@kde.org>
    SPDX-FileCopyrightText: 2019 Sefa Eyeoglu <contact@scrumplex.net>
    SPDX-FileCopyrightText: 2022 ivan (@ratijas) tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2026 AIKDE

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL

    One mixer item. Mechanics come from the stock applet's
    ListItemBase/DeviceListItem/StreamListItem (menu, drag&drop, keys, volume, default device,
    mute). The layout is a vertical column: icon, label, percentage, slider, mute button.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kitemmodels as KItemModels
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.volume
import org.kde.plasma.plasmoid

import "../code/DeviceLabels.js" as DeviceLabels

PC3.ItemDelegate {
    id: item

    required property var model
    // "event" — the Notification sounds row: the saved volume for the event role from
    // stream-restore (as in the "Sound" KCM); it behaves like a stream.
    property string /* "sink" | "sink-input" | "source" | "source-output" | "event" */ type
    property var devicesModel: null

    readonly property bool isStream: type === "sink-input" || type === "source-output" || type === "event"
    readonly property bool isDevice: type === "sink" || type === "source"
    readonly property bool isPlayback: type.startsWith("sink") || type === "event"
    readonly property var currentPort: isDevice && model.Ports && model.ActivePortIndex >= 0 ? model.Ports[model.ActivePortIndex] : null
    readonly property string deviceType: type === "sink" ? "Sink" : "Source"

    width: main.itemWidth
    // The default ItemDelegate padding eats ~16 px, which broke labels like "Built-in"
    // mid-word.
    leftPadding: Kirigami.Units.smallSpacing
    rightPadding: Kirigami.Units.smallSpacing
    topPadding: Kirigami.Units.smallSpacing
    bottomPadding: Kirigami.Units.smallSpacing

    highlighted: dropArea.containsDrag
    background.visible: highlighted
    opacity: (main.draggedStream && main.draggedStream.deviceIndex === item.model.Index) ? 0.3 : 1.0
    Accessible.name: label
    Accessible.description: percentText.text
    Accessible.onIncreaseAction: slider.increase()
    Accessible.onDecreaseAction: slider.decrease()
    Accessible.onToggleAction: isDevice ? setAsDefault() : toggleMuteItem()
    Keys.onSpacePressed: isDevice ? setAsDefault() : toggleMuteItem()

    ListView.delayRemove: clientIcon.Drag.active

    Keys.forwardTo: [slider]

    // ---------- Looks: icon and label ----------

    // Bluetooth device: the "what is it" answer comes from the settings. '' means no answer —
    // show the rune icon with a "?" badge and the type-picker menu.
    readonly property bool isBluetooth: item.isDevice && DeviceLabels.getConnectionType(model.PulseObject) === DeviceLabels.CONN_BLUETOOTH
    readonly property string btKind: item.isBluetooth ? main.btKindOf(model.PulseObject) : ""
    readonly property bool btUnknown: item.isBluetooth && item.btKind === ""

    // Device icon: filename inside contents/images/icons8 (silver <name>.png, from the
    // Icons8 "3D Fluency" set, re-tinted by mockups/volmixer-icons/make-icons.sh).
    readonly property string deviceIcon: {
        if (item.type === "event") {
            return "bell" // Notification sounds — silver bell in the device-icon slot.
        }
        if (item.isStream) {
            return ""
        }
        const conn = DeviceLabels.getConnectionType(model.PulseObject)
        if (conn === DeviceLabels.CONN_BLUETOOTH) {
            return DeviceLabels.btKindIcon(item.btKind)
        }
        if (type === "sink") {
            if (conn === DeviceLabels.CONN_USB || conn === DeviceLabels.CONN_JACK) {
                return "headphones"
            }
            return conn === DeviceLabels.CONN_HDMI ? "hdmi" : "speaker"
        }
        // Jack mic — hand-held microphone, USB — headset, built-in — studio microphone.
        if (conn === DeviceLabels.CONN_JACK) {
            return "jackmic"
        }
        return conn === DeviceLabels.CONN_USB ? "headphones" : "microphone"
    }

    // Stream icon = the application's icon.
    readonly property string iconSource: {
        if (!item.isStream) {
            return ""
        }
        if (model.IconName && model.IconName.length !== 0) {
            return model.IconName
        }
        const props = model.Client ? model.Client.properties : null
        const binary = props && props["application.process.binary"] ? String(props["application.process.binary"]).toLowerCase() : ""
        const iconMap = {
            "chrome": "google-chrome", "chromium": "google-chrome", "yandex_browser": "yandex-browser",
            "firefox": "firefox", "brave": "brave-browser", "vlc": "vlc", "spotify": "spotify", "code": "code"
        }
        if (iconMap[binary]) {
            return iconMap[binary]
        }
        return type === "source-output" ? "audio-input-microphone" : "audio-volume-high"
    }

    function shortLabel(key) {
        const labels = {
            "JACK_MIC": i18nc("mixer.label.jack-mic", "Microphone\n(jack)"),
            "JACK_HEADSET": i18nc("mixer.label.jack-headset", "Headphones\n(jack)"),
            "JACK_SPEAKER": i18nc("mixer.label.jack-speaker", "Speakers\n(jack)"),
            "USB_HEADSET": i18nc("mixer.label.usb-headset", "USB headset"),
            "USB_MIC": i18nc("mixer.label.usb-mic", "USB microphone"),
            "BLUETOOTH_HEADSET": i18nc("mixer.label.bt-headset", "Bluetooth headset"),
            "BLUETOOTH_MIC": i18nc("mixer.label.bt-mic", "Bluetooth microphone"),
            "HDMI": i18nc("mixer.label.hdmi", "HDMI"),
            "INTERNAL_MIC": i18nc("mixer.label.internal-mic", "Built-in microphone"),
            "INTERNAL_SPEAKER": i18nc("mixer.label.internal-speaker", "Built-in speaker"),
            "MIC": i18nc("mixer.label.mic", "Microphone"),
            "HEADSET": i18nc("mixer.label.headset", "Headset"),
            "SPEAKER": i18nc("mixer.label.speaker", "Speaker")
        }
        return labels[key] || ""
    }

    readonly property var customNames: { try { return JSON.parse(Plasmoid.configuration.deviceNames || "{}") } catch (e) { return {} } }
    readonly property string label: {
        if (item.type === "event") {
            return i18nc("mixer.label.notifications", "Notification sounds")
        }
        if (item.isStream) {
            // Same as the stock applet's StreamListItem.
            let parts = []
            if (model.Client && model.Client.name && model.Client.name != "pipewire-media-session") {
                parts.push(model.Client.name);
            } else if (model.Name) {
                parts.push(model.Name);
            }
            const mediaName = model.Properties["media.name"];
            if (mediaName && !/playback|audio|stream|alsa|pulse|pipewire/gi.test(mediaName)) {
                parts.push(mediaName);
            }
            return parts.length > 0 ? parts.join(" · ") : i18nc("mixer.stream-no-name", "Stream name not found")
        }
        // Custom label from the settings (PulseAudio name → label).
        const custom = item.customNames[model.Name]
        if (custom) {
            return custom
        }
        const key = DeviceLabels.getShortLabelKey(model.PulseObject, item.deviceType)
        if (key) {
            return shortLabel(key)
        }
        // Bluetooth and the rest: description without its parenthetical tail.
        let text = model.Description || model.Name || ""
        const bracket = text.indexOf(" (")
        return bracket > 0 ? text.substring(0, bracket) : text
    }

    // Full description in the tooltip; for a stream it also says where it plays.
    readonly property string fullName: {
        if (item.isDevice) {
            return model.Description || model.Name || ""
        }
        if (devicesModel && devicesModel.count > 0) {
            const indexRole = devicesModel.KItemModels.KRoleNames.role("Index");
            const descriptionRole = devicesModel.KItemModels.KRoleNames.role("Description");
            for (let i = 0; i < devicesModel.count; ++i) {
                const idx = devicesModel.index(i, 0);
                if (devicesModel.data(idx, indexRole) === model.DeviceIndex) {
                    return devicesModel.data(idx, descriptionRole);
                }
            }
        }
        return "";
    }

    PC3.ToolTip.text: fullName
    PC3.ToolTip.visible: fullName !== "" && hoverHandler.hovered && !contextMenu.visible
    PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
    HoverHandler { id: hoverHandler }

    // Default-device marker (defaultMark setting): corner — radio button above the icon,
    // badge — checkmark in the icon's corner, halo — icon halo, bottom — radio button in the
    // bottom row, left of the mute button.
    readonly property string defaultMark: Plasmoid.configuration.defaultMark
    // Show the "default" marker even for a single device in a group (the stock applet
    // hides it when there's nothing to pick between).
    readonly property bool canBeDefault: item.isDevice
    readonly property bool isDefault: item.model.PulseObject?.default ?? false

    // ---------- Layout ----------

    contentItem: ColumnLayout {
        id: column
        spacing: Kirigami.Units.smallSpacing

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.iconSizes.large

            // Device icon: silver, un-tinted; the accent colour from the settings marks
            // the default device.
            Item {
                id: deviceIconBox
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width
                visible: item.deviceIcon !== ""
                Rectangle { // Halo: an accent-coloured ring behind the default device's icon.
                    anchors.centerIn: parent
                    width: parent.width + Kirigami.Units.smallSpacing * 2
                    height: width
                    radius: width / 2
                    visible: item.defaultMark === "halo" && item.canBeDefault && item.isDefault
                    color: Qt.alpha(Plasmoid.configuration.iconAccentColor, 0.25)
                    border.width: 1.5
                    border.color: Qt.alpha(Plasmoid.configuration.iconAccentColor, 0.85)
                }
                Image {
                    anchors.fill: parent
                    source: item.deviceIcon !== "" ? Qt.resolvedUrl("../images/icons8/" + item.deviceIcon + ".png") : ""
                    sourceSize.width: 128
                    sourceSize.height: 128
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
                Rectangle { // Badge: checkmark in the icon's corner for the default device;
                            //        other devices get a pale circle on hover.
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -2
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    radius: width / 2
                    visible: item.defaultMark === "badge" && item.canBeDefault && (item.isDefault || hoverHandler.hovered)
                    color: item.isDefault ? Plasmoid.configuration.iconAccentColor : "transparent"
                    border.width: item.isDefault ? 0 : 1
                    border.color: Plasmoid.configuration.iconAccentColor
                    opacity: item.isDefault ? 1 : 0.5
                    Canvas { // Custom checkmark: the "checkmark" theme icon in Slot-Blue-Dark
                             //                  is a filled square and masks to a white one.
                        anchors.fill: parent
                        visible: item.isDefault
                        onPaint: {
                            const c = getContext("2d");
                            c.clearRect(0, 0, width, height);
                            c.strokeStyle = "white";
                            c.lineWidth = 2;
                            c.lineCap = "round";
                            c.lineJoin = "round";
                            c.beginPath();
                            c.moveTo(width * 0.28, height * 0.52);
                            c.lineTo(width * 0.44, height * 0.68);
                            c.lineTo(width * 0.73, height * 0.34);
                            c.stroke();
                        }
                    }
                }
            }

            Kirigami.Icon {
                id: clientIcon
                anchors.centerIn: parent
                implicitHeight: Kirigami.Units.iconSizes.large
                implicitWidth: implicitHeight
                source: item.isStream ? item.iconSource : ""
                visible: item.isStream && item.deviceIcon === ""
                active: dragMouseArea.containsMouse

                onSourceChanged: {
                    if (item.isStream && !valid && source !== "unknown") {
                        source = "unknown";
                    }
                }

                Drag.active: dragMouseArea.drag.active
                Drag.dragType: Drag.Automatic
                Drag.onDragStarted: {
                    main.draggedStream = item.model.PulseObject;
                    main.draggedStreamType = item.type;
                }
                Drag.onDragFinished: {
                    main.draggedStream = null;
                    main.draggedStreamType = "";
                }
            }

            // Paused stream (same as in the stock applet) — overlay on the icon; muted is
            // not marked here (the mute button already shows it). In "corner checkmark" mode
            // the bottom-right is occupied, so the emblem moves to the bottom-left.
            Kirigami.Icon {
                readonly property bool toLeft: item.defaultMark === "badge"
                anchors.right: toLeft ? undefined : parent.right
                anchors.left: toLeft ? parent.left : undefined
                anchors.bottom: parent.bottom
                anchors.rightMargin: Math.round((parent.width - Kirigami.Units.iconSizes.large) / 2)
                anchors.leftMargin: anchors.rightMargin
                implicitHeight: Kirigami.Units.iconSizes.small
                implicitWidth: implicitHeight
                source: item.isStream && item.model.Corked ? "emblem-pause" : ""
                visible: valid && source !== ""
            }

            Item {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width

                MouseArea {
                    id: dragMouseArea
                    anchors.fill: parent
                    cursorShape: item.isStream ? (pressed && pressedButtons === Qt.LeftButton ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    hoverEnabled: true
                    drag.target: item.isStream && item.devicesModel && item.devicesModel.count > 1 ? clientIcon : null
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            item.model.Muted = !item.model.Muted;
                        } else if (item.isDevice) {
                            item.setAsDefault();
                        } else if (contextMenu.hasContent) {
                            contextMenu.visualParent = clientIcon;
                            contextMenu.openRelative();
                        }
                    }
                    onPressed: mouse => {
                        if (mouse.button === Qt.LeftButton && item.isStream) {
                            clientIcon.grabToImage(result => clientIcon.Drag.imageSource = result.url);
                        }
                    }
                }
            }

            // Bluetooth with no "what is it" answer: a "?" badge in the icon's upper-right
            // corner (the lower-right is taken by the default-device checkmark). Declared
            // after the icon's click area so it sits on top; clicking it opens the four-type
            // picker menu.
            Rectangle {
                id: kindBadge
                visible: item.btUnknown
                anchors.right: deviceIconBox.right
                anchors.top: deviceIconBox.top
                anchors.margins: -3
                width: Kirigami.Units.iconSizes.small + 4
                height: width
                radius: width / 2
                color: kindBadgeArea.containsMouse ? "#ffb52e" : "#f0a020"
                border.width: 1.5
                border.color: Qt.darker(color, 1.8)
                PC3.Label {
                    anchors.centerIn: parent
                    text: "?"
                    color: "white"
                    font.bold: true
                    font.pixelSize: Math.round(parent.height * 0.72)
                }
                MouseArea {
                    id: kindBadgeArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: kindMenu.popup()
                    PC3.ToolTip.text: i18nc("mixer.menu.ask-tooltip", "What is this device? Click and choose")
                    PC3.ToolTip.visible: containsMouse
                    PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }
            PC3.Menu {
                id: kindMenu
                PC3.MenuItem { text: i18nc("mixer.menu.what-is", "%1 — what is it?", item.model.PulseObject ? item.model.PulseObject.description : ""); enabled: false }
                PC3.MenuSeparator {}
                PC3.MenuItem { text: i18nc("btkind.headset", "Headset / headphones"); icon.source: Qt.resolvedUrl("../images/icons8/headphones.png"); onTriggered: main.setBtKind(item.model.PulseObject, "headset") }
                PC3.MenuItem { text: i18nc("btkind.tws", "TWS earbuds"); icon.source: Qt.resolvedUrl("../images/icons8/bluetooth.png"); onTriggered: main.setBtKind(item.model.PulseObject, "tws") }
                PC3.MenuItem { text: i18nc("btkind.compact", "Compact speaker"); icon.source: Qt.resolvedUrl("../images/icons8/btspeaker.png"); onTriggered: main.setBtKind(item.model.PulseObject, "compact") }
                PC3.MenuItem { text: i18nc("btkind.sub", "Speaker with subwoofer"); icon.source: Qt.resolvedUrl("../images/icons8/btsub.png"); onTriggered: main.setBtKind(item.model.PulseObject, "sub") }
            }

            DefaultRadio { // corner: radio button above the icon (the default placement).
                anchors.left: parent.left
                anchors.top: parent.top
                visible: item.canBeDefault && ["badge", "halo", "bottom"].indexOf(item.defaultMark) === -1
                checked: item.isDefault
                onToggled: if (checked) item.setAsDefault()
            }
        }

        PC3.Label {
            id: nameLabel
            Layout.fillWidth: true
            // Always two lines, so the sliders of neighbouring items stay at the same height.
            Layout.preferredHeight: Math.ceil(fontMetrics.lineSpacing * 2)
            Layout.minimumHeight: Layout.preferredHeight
            text: item.label
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            // Font from the applet settings; empty family / size 0 means system font.
            font.family: Plasmoid.configuration.labelFontFamily !== "" ? Plasmoid.configuration.labelFontFamily : Kirigami.Theme.defaultFont.family
            font.pointSize: Plasmoid.configuration.labelFontSize > 0 ? Plasmoid.configuration.labelFontSize : Kirigami.Theme.defaultFont.pointSize
            font.bold: Plasmoid.configuration.labelFontBold
            FontMetrics { id: fontMetrics; font: nameLabel.font }
        }

        PC3.Label {
            id: percentText
            readonly property real value: item.model.PulseObject.volume > slider.to ? item.model.PulseObject.volume : slider.value
            readonly property real displayValue: Math.round(value / PulseAudio.NormalVolume * 100.0)
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: i18nc("mixer.volume-percent", "%1%", displayValue)
            textFormat: Text.PlainText
            visible: slider.visible
            // Keep this in sync with the copies in VolumeSlider.qml and plasma-workspace:OSDItem.qml
            color: {
                if (displayValue <= AudioIcon.HIGH_UPPER_BOUND) {
                    return Kirigami.Theme.textColor
                } else if (displayValue > AudioIcon.HIGH_UPPER_BOUND && displayValue <= AudioIcon.VERY_HIGH_UPPER_BOUND) {
                    return Kirigami.Theme.neutralTextColor
                } else {
                    return Kirigami.Theme.negativeTextColor
                }
            }
        }

        VerticalVolumeSlider {
            id: slider

            readonly property bool forceRaiseMaxVolume: raiseMaximumVolumeCheckbox.checked

            Layout.fillHeight: true
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.round(main.itemWidth * 0.7)
            from: PulseAudio.MinimalVolume
            to: forceRaiseMaxVolume || item.model.Volume >= PulseAudio.NormalVolume * 1.01 ? PulseAudio.MaximalVolume : PulseAudio.NormalVolume
            stepSize: PulseAudio.NormalVolume / 100.0
            property real myStepSize: PulseAudio.NormalVolume / 100.0 * config.volumeStep
            visible: item.model.HasVolume !== false // Devices always have volume but Streams don't necessarily
            enabled: item.model.VolumeWritable
            muted: item.model.Muted
            volumeObject: item.type === "event" ? null : item.model.PulseObject // StreamRestore isn't a VolumeObject and has no level.
            activeFocusOnTab: false
            Accessible.name: i18nc("mixer.a11y.volume", "Volume %1", item.label)
            Accessible.onPressAction: moved()

            value: to, item.model.Volume
            function increase() { value = value + myStepSize; moved() }
            function decrease() { value = value - myStepSize; moved() }
            Keys.onUpPressed: increase()
            Keys.onDownPressed: decrease()
            onMoved: {
                item.model.Volume = value;
                item.model.Muted = value === 0;
                Accessible.announce(percentText.text)
                // Wheel/keys: the handle isn't pressed, so onPressedChanged won't fire —
                // the confirmation sound is triggered here, once per burst of events.
                if (!pressed && item.type === "sink") {
                    wheelFeedback.restart()
                }
            }
            Timer { id: wheelFeedback; interval: 150; onTriggered: playFeedback(item.model.Index) }
            onPressedChanged: {
                if (!pressed) {
                    // Make sure to sync the volume once the button was released.
                    value = Qt.binding(() => item.model.Volume);
                    if (item.type === "sink") {
                        playFeedback(item.model.Index);
                    }
                }
            }
            onForceRaiseMaxVolumeChanged: {
                if (forceRaiseMaxVolume) {
                    toAnimation.from = PulseAudio.NormalVolume;
                    toAnimation.to = PulseAudio.MaximalVolume;
                } else {
                    toAnimation.from = PulseAudio.MaximalVolume;
                    toAnimation.to = PulseAudio.NormalVolume;
                }
                seqAnimation.restart();
            }

            function updateVolume() {
                if (!forceRaiseMaxVolume && item.model.Volume > PulseAudio.NormalVolume) {
                    item.model.Volume = PulseAudio.NormalVolume;
                }
            }

            SequentialAnimation {
                id: seqAnimation
                NumberAnimation {
                    id: toAnimation
                    target: slider
                    property: "to"
                    duration: Kirigami.Units.shortDuration
                    easing.type: Easing.InOutQuad
                }
                ScriptAction {
                    script: slider.updateVolume()
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing
            DefaultRadio { // bottom: radio button in the bottom row, left of the mute button.
                visible: item.defaultMark === "bottom" && item.canBeDefault
                checked: item.isDefault
                onToggled: if (checked) item.setAsDefault()
            }
            SmallToolButton {
                id: muteButton
                Layout.alignment: Qt.AlignHCenter
                icon.name: AudioIcon.forVolume(volumePercent(item.model.Volume), item.model.Muted, item.isPlayback ? "audio-volume" : "microphone-sensitivity")
                onClicked: toggleMuteItem()
                checked: item.model.Muted

                // Mute button style (muteStyle setting): theme — theme icon (legacy),
                // icons8 — volumetric icon from the device set (silver + accent; when muted,
                // dim with a red slash), led — dark button with an LED (accent = sound on,
                // red = muted).
                readonly property string muteStyle: Plasmoid.configuration.muteStyle
                readonly property bool muted: item.model.Muted
                contentItem: Item {
                    implicitWidth: muteButton.muteStyle === "led" ? ledBox.width : (muteButton.muteStyle === "icons8" ? Kirigami.Units.iconSizes.smallMedium : muteButton.iconSize)
                    implicitHeight: muteButton.muteStyle === "led" ? ledBox.height : implicitWidth

                    Kirigami.Icon { // theme
                        anchors.fill: parent
                        visible: muteButton.muteStyle !== "icons8" && muteButton.muteStyle !== "led"
                        source: muteButton.icon.name
                        active: muteButton.hovered
                    }

                    Item { // icons8
                        id: box3d
                        anchors.fill: parent
                        visible: muteButton.muteStyle === "icons8"
                        readonly property string file: item.isPlayback ? "sound" : "mic"
                        Image {
                            anchors.fill: parent
                            source: box3d.visible ? Qt.resolvedUrl("../images/icons8/" + box3d.file + ".png") : ""
                            sourceSize.width: 128
                            sourceSize.height: 128
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            opacity: muteButton.muted ? 0.45 : 1
                        }
                        Canvas { // Red "muted" slash.
                            anchors.fill: parent
                            visible: muteButton.muted
                            onPaint: {
                                const c = getContext("2d");
                                c.clearRect(0, 0, width, height);
                                c.strokeStyle = "#e23b47";
                                c.lineWidth = 2.4;
                                c.lineCap = "round";
                                c.beginPath();
                                c.moveTo(width * 0.18, height * 0.82);
                                c.lineTo(width * 0.82, height * 0.18);
                                c.stroke();
                            }
                        }
                    }

                    Rectangle { // led
                        id: ledBox
                        anchors.centerIn: parent
                        width: ledRow.implicitWidth + Kirigami.Units.smallSpacing * 3
                        height: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                        radius: 4
                        visible: muteButton.muteStyle === "led"
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#2d3135" }
                            GradientStop { position: 1; color: "#1e2124" }
                        }
                        border.width: 1
                        border.color: "#0d0e10"
                        Row {
                            id: ledRow
                            anchors.centerIn: parent
                            spacing: Kirigami.Units.smallSpacing + 1
                            Item {
                                id: led
                                width: 6
                                height: 6
                                anchors.verticalCenter: parent.verticalCenter
                                readonly property color ledColor: muteButton.muted ? "#e03b3b" : Plasmoid.configuration.iconAccentColor
                                // Blinking (ledBlink setting): muted — red blinks every half
                                // second; signal — brightness tracks the signal level (×3 so
                                // quiet sound is still visible), dim when silent.
                                readonly property string blink: Plasmoid.configuration.ledBlink
                                property bool blinkOn: true
                                opacity: blink === "muted" && muteButton.muted ? (blinkOn ? 1 : 0.15)
                                    : (blink === "signal" && !muteButton.muted ? 0.25 + 0.75 * Math.min(1, slider.volume * 3) : 1)
                                Timer {
                                    interval: 500
                                    repeat: true
                                    running: ledBox.visible && led.blink === "muted" && muteButton.muted
                                    onTriggered: led.blinkOn = !led.blinkOn
                                    onRunningChanged: led.blinkOn = true
                                }
                                Rectangle { // Glow.
                                    anchors.centerIn: parent
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: parent.ledColor
                                    opacity: 0.35
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 3
                                    color: parent.ledColor
                                }
                            }
                            Kirigami.Icon {
                                width: 14
                                height: 14
                                anchors.verticalCenter: parent.verticalCenter
                                source: AudioIcon.forVolume(volumePercent(item.model.Volume), false, item.isPlayback ? "audio-volume" : "microphone-sensitivity")
                                color: muteButton.muted ? "#6f7378" : "#dfe1e3"
                                isMask: true
                            }
                        }
                    }
                }

                text: item.model.Muted ? i18nc("@action:button mixer.button.unmute", "Unmute") : i18nc("@action:button mixer.button.mute", "Mute")
                Accessible.description: item.model.Muted ? i18nc("mixer.a11y.unmute-item", "Unmute: %1", item.label) : i18nc("mixer.a11y.mute-item", "Mute: %1", item.label)

                PC3.ToolTip {
                    text: parent.text
                    textFormat: Text.PlainText
                }
            }
        }
    }

    // ---------- Stock-applet mechanics ----------

    MouseArea {
        z: -1
        parent: item
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.RightButton
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton && contextMenu.hasContent) {
                contextMenu.visualParent = this;
                contextMenu.open(mouse.x, mouse.y);
            }
        }
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                item.model.Muted = !item.model.Muted;
            }
        }
    }

    // Streams are dragged onto a device in the same direction.
    DropArea {
        id: dropArea
        z: -1
        parent: item
        anchors.fill: parent
        enabled: item.isDevice && main.draggedStream
            && ((item.type === "sink" && main.draggedStreamType === "sink-input") || (item.type === "source" && main.draggedStreamType === "source-output"))
            && main.draggedStream.deviceIndex !== item.model.Index
        onDropped: drop => {
            main.draggedStream.deviceIndex = item.model.Index;
        }
    }

    ListItemMenu {
        id: contextMenu
        pulseObject: item.model.PulseObject
        cardModel: main.paCardModel
        itemType: {
            switch (item.type) {
            case "sink":
                return ListItemMenu.Sink;
            case "sink-input":
                return ListItemMenu.SinkInput;
            case "source":
                return ListItemMenu.Source;
            case "source-output":
                return ListItemMenu.SourceOutput;
            default:
                return ListItemMenu.None;
            }
        }
        sourceModel: item.isPlayback ? main.paSinkFilterModel : main.paSourceFilterModel
    }

    function setVolumeByPercent(targetPercent) {
        item.model.PulseObject.volume = Math.round(PulseAudio.NormalVolume * (targetPercent/100));
    }

    function setAsDefault(): void {
        if (isDevice) {
            model.PulseObject.default = true;
        }
    }

    function toggleMuteItem(): void {
        item.model.Muted = !item.model.Muted
    }

    Keys.onPressed: event => {
        const k = event.key;

        if (k === Qt.Key_M) {
            muteButton.clicked();
        } else if (k >= Qt.Key_0 && k <= Qt.Key_9) {
            setVolumeByPercent((k - Qt.Key_0) * 10);
        } else if (k === Qt.Key_Return) {
            setAsDefault();
        } else if (k === Qt.Key_Menu && contextMenu.hasContent) {
            contextMenu.visualParent = clientIcon;
            contextMenu.openRelative();
        } else {
            return; // don't accept the key press
        }
        event.accepted = true;
    }
}

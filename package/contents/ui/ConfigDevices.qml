import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.volume
import "../code/DeviceLabels.js" as DeviceLabels

// "Devices" page: what each Bluetooth device is (the type drives both the icon and the
// behaviour), device labels, and whether to show virtual devices.
KCM.SimpleKCM {
    id: page

    property string cfg_btKinds
    property string cfg_btNewDevice
    property string cfg_deviceNames
    property alias cfg_showVirtualDevices: showVirtualDevices.checked

    // poRole: KRoleNames only works as an attached property of the model itself.
    SinkModel { id: cfgSinks; readonly property int poRole: KItemModels.KRoleNames.role("PulseObject") }
    SourceModel { id: cfgSources; readonly property int poRole: KItemModels.KRoleNames.role("PulseObject") }

    // ---- Bluetooth device types: btKinds = {card name: {kind, name}} — the same shape
    //      the "?" menu in the mixer writes. ----
    readonly property var kindOptions: [
        { value: "", text: i18nc("btkind.ask-icon", "ask (shows a “?” icon)") },
        { value: "headset", text: i18nc("btkind.headset", "Headset / headphones") },
        { value: "tws", text: i18nc("btkind.tws", "TWS earbuds") },
        { value: "compact", text: i18nc("btkind.compact", "Compact speaker") },
        { value: "sub", text: i18nc("btkind.sub", "Speaker with subwoofer") },
    ]
    readonly property var newDeviceOptions: [
        { value: "ask", text: i18nc("btkind.ask-icon-infl", "ask (shows a “?” icon)") },
        { value: "auto", text: i18nc("btkind.by-class", "by Bluetooth class") },
        { value: "headset", text: i18nc("btkind.as-headset", "treat as a headset") },
    ]
    function btKinds() { try { return JSON.parse(cfg_btKinds || "{}") } catch (e) { return {} } }
    function setBtKind(card, kind, name) {
        const kinds = btKinds()
        if (kind === "") delete kinds[card]; else kinds[card] = { kind: kind, name: name }
        cfg_btKinds = JSON.stringify(kinds)
    }
    // "What is this" rows: currently connected Bluetooth outputs (one per card, monitors
    // excluded) plus saved answers for devices that are not connected right now — a snapshot
    // taken when the page is opened, so changing a type doesn't recreate the row. A Repeater
    // that recreates delegates inside a Layout crashed plasmashell on Qt 6.10 when a device
    // appeared while the dialog was open — hence Column/Row below rather than
    // ColumnLayout/RowLayout.
    property var initialKinds: ({})
    Component.onCompleted: initialKinds = btKinds()
    function btRows() {
        const rows = []
        for (let i = 0; i < cfgSinks.count; ++i) {
            const po = cfgSinks.data(cfgSinks.index(i, 0), cfgSinks.poRole)
            if (!po || DeviceLabels.getConnectionType(po) !== DeviceLabels.CONN_BLUETOOTH || String(po.name).endsWith(".monitor")) continue
            const card = DeviceLabels.cardName(po)
            if (card !== "" && !rows.some(r => r.card === card)) rows.push({ card: card, name: po.description })
        }
        for (const card in initialKinds) {
            if (!rows.some(r => r.card === card)) rows.push({ card: card, name: i18nc("common.disconnected", "%1 (currently disconnected)", initialKinds[card].name || card) })
        }
        return rows
    }

    // ---- Labels: PulseAudio name → label. An empty label removes the entry. ----
    function customNames() { try { return JSON.parse(cfg_deviceNames || "{}") } catch (e) { return {} } }
    function setCustomName(name, label) {
        const names = customNames()
        if (label.trim() === "") delete names[name]; else names[name] = label.trim()
        cfg_deviceNames = JSON.stringify(names)
    }
    function renameRows(model) {
        const rows = []
        for (let i = 0; i < model.count; ++i) {
            const po = model.data(model.index(i, 0), model.poRole)
            if (!po || String(po.name).endsWith(".monitor")) continue
            rows.push({ name: po.name, description: po.description })
        }
        return rows
    }

    Kirigami.FormLayout {
        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("devices.section.bt", "Bluetooth devices") }

        // One row per device, list inside the row (a Repeater placed directly in a FormLayout
        // appends new devices to the end of the form).
        Column {
            Kirigami.FormData.label: i18nc("devices.kind.label", "What is it:")
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: page.btRows()
                delegate: Row {
                    id: btRow
                    required property var modelData
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.ComboBox {
                        width: Kirigami.Units.gridUnit * 12
                        anchors.verticalCenter: parent.verticalCenter
                        textRole: "text"
                        valueRole: "value"
                        model: page.kindOptions
                        Component.onCompleted: currentIndex = Math.max(0, indexOfValue((page.btKinds()[btRow.modelData.card] || {}).kind || ""))
                        onActivated: page.setBtKind(btRow.modelData.card, currentValue, btRow.modelData.name)
                    }
                    QQC2.Label {
                        width: Kirigami.Units.gridUnit * 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: btRow.modelData.name
                        elide: Text.ElideRight
                    }
                }
            }
            QQC2.Label {
                visible: page.btRows().length === 0
                text: i18nc("devices.none", "No Bluetooth devices yet")
                color: Kirigami.Theme.disabledTextColor
            }
        }
        QQC2.ComboBox {
            id: newDevice
            Kirigami.FormData.label: i18nc("devices.new.label", "New device:")
            textRole: "text"
            valueRole: "value"
            model: page.newDeviceOptions
            onActivated: page.cfg_btNewDevice = currentValue
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_btNewDevice))
        }
        QQC2.Label {
            text: i18nc("devices.footer-tooltip", "The type sets the icon and the behaviour: headsets and TWS earbuds follow the headset logic, speakers only take over the speakers. Until an answer is given, the device shows a “?” icon in the mixer and automation leaves it alone. The Bluetooth class is unreliable: the Tronsmart Element T6 Plus reports itself as a headset with a microphone.")
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("devices.section.labels", "Device labels") }

        RenameList {
            Kirigami.FormData.label: i18nc("devices.labels.sinks", "Speakers:")
            rows: page.renameRows(cfgSinks)
        }
        RenameList {
            Kirigami.FormData.label: i18nc("devices.labels.sources", "Microphones:")
            rows: page.renameRows(cfgSources)
        }
        QQC2.Label {
            text: i18nc("devices.labels.footer", "The label is shown in place of the automatic one; the tooltip still shows the full device name.")
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showVirtualDevices
            text: i18nc("plasmoid.action.show-virtual", "Show virtual devices")
        }
    }

    // Column/Row, not the Layouts counterparts: see the note on btRows.
    component RenameList: Column {
        property var rows: []
        spacing: Kirigami.Units.smallSpacing
        Repeater {
            model: parent.rows
            delegate: Row {
                id: renameRow
                required property var modelData
                spacing: Kirigami.Units.smallSpacing
                QQC2.TextField {
                    id: renameField
                    width: Kirigami.Units.gridUnit * 12
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: i18nc("devices.label.placeholder", "as shown in the mixer")
                    text: page.customNames()[renameRow.modelData.name] || ""
                    onEditingFinished: page.setCustomName(renameRow.modelData.name, text)
                }
                QQC2.ToolButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon.name: "edit-clear"
                    enabled: renameField.text !== ""
                    onClicked: { renameField.text = ""; page.setCustomName(renameRow.modelData.name, "") }
                    QQC2.ToolTip.text: i18nc("devices.label.reset-tooltip", "Reset label")
                    QQC2.ToolTip.visible: hovered
                }
                QQC2.Label {
                    width: Kirigami.Units.gridUnit * 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: renameRow.modelData.description
                    color: Kirigami.Theme.disabledTextColor
                    elide: Text.ElideRight
                }
            }
        }
    }
}

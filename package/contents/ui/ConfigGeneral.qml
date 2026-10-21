import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.volume

KCM.SimpleKCM {
    id: page

    property alias cfg_itemWidth: itemWidth.value
    property alias cfg_sliderHeight: sliderHeight.value
    property string cfg_labelFontFamily
    property int cfg_labelFontSize
    property bool cfg_labelFontBold
    property string cfg_barStyle
    property string cfg_barShape
    property string cfg_handleOrientation
    property string cfg_signalScale
    property alias cfg_iconAccentColor: iconAccentColor.color
    property string cfg_defaultMark
    property string cfg_muteStyle
    property string cfg_ledBlink
    property alias cfg_useCustomColors: useCustomColors.checked
    property alias cfg_zoneColors: zoneColors.checked
    property alias cfg_zoneBySignal: zoneBySignal.checked
    property alias cfg_fillColor: fillColor.color
    property alias cfg_peakColor: peakColor.color
    property alias cfg_dimColor: dimColor.color
    property alias cfg_fillOpacity: fillOpacity.value
    property alias cfg_peakOpacity: peakOpacity.value
    property alias cfg_dimOpacity: dimOpacity.value

    readonly property font systemFont: Kirigami.Theme.defaultFont
    readonly property bool customFont: cfg_labelFontFamily !== "" || cfg_labelFontSize > 0 || cfg_labelFontBold
    readonly property font labelFont: Qt.font({
        family: cfg_labelFontFamily !== "" ? cfg_labelFontFamily : systemFont.family,
        pointSize: cfg_labelFontSize > 0 ? cfg_labelFontSize : systemFont.pointSize,
        bold: cfg_labelFontBold
    })

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: itemWidth
            Kirigami.FormData.label: i18nc("general.item-width", "Item width (px):")
            from: 60
            to: 300
            stepSize: 10
        }
        QQC2.SpinBox {
            id: sliderHeight
            Kirigami.FormData.label: i18nc("general.slider-height", "Slider height (px):")
            from: 100
            to: 600
            stepSize: 10
        }

        RowLayout {
            Kirigami.FormData.label: i18nc("general.font.label", "Label font:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: page.customFont
                    ? i18nc("general.font.summary", "%1, %2 pt%3", page.labelFont.family, page.labelFont.pointSize, page.cfg_labelFontBold ? i18nc("general.font.bold-suffix", ", bold") : "")
                    : i18nc("general.font.system-summary", "System (%1, %2 pt)", page.systemFont.family, page.systemFont.pointSize)
                font: page.labelFont
                elide: Text.ElideRight
                Layout.maximumWidth: Kirigami.Units.gridUnit * 18
            }
            QQC2.Button {
                text: i18nc("general.font.choose", "Choose…")
                icon.name: "font"
                onClicked: {
                    fontDialog.selectedFont = page.labelFont
                    fontDialog.open()
                }
            }
            QQC2.Button {
                text: i18nc("general.font.system", "System")
                icon.name: "edit-undo"
                enabled: page.customFont
                onClicked: {
                    page.cfg_labelFontFamily = ""
                    page.cfg_labelFontSize = 0
                    page.cfg_labelFontBold = false
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18nc("general.accent-color", "Accent colour:")
            spacing: Kirigami.Units.smallSpacing
            ColorPickButton { id: iconAccentColor; showAlphaChannel: false }
            QQC2.Label { text: i18nc("general.accent-color.hint", "marks the default device and lights the mute-button LED"); color: Kirigami.Theme.disabledTextColor }
        }
        QQC2.ComboBox {
            id: defaultMark
            Kirigami.FormData.label: i18nc("general.default-mark.label", "Default device:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18nc("general.default-mark.corner", "Radio button above the icon"), value: "corner" },
                { text: i18nc("general.default-mark.badge", "Checkmark in the icon’s corner"), value: "badge" },
                { text: i18nc("general.default-mark.halo", "Icon halo"), value: "halo" },
                { text: i18nc("general.default-mark.bottom", "Radio button at the bottom, next to the mute button"), value: "bottom" }
            ]
            onActivated: page.cfg_defaultMark = currentValue
            function sync() { currentIndex = Math.max(0, indexOfValue(page.cfg_defaultMark)) }
            Component.onCompleted: sync()
        }
        QQC2.ComboBox {
            id: muteStyle
            Kirigami.FormData.label: i18nc("general.mute-style.label", "Mute button:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18nc("general.mute-style.theme", "Theme icon"), value: "theme" },
                { text: i18nc("general.mute-style.icons8", "Volumetric icon, like the devices"), value: "icons8" },
                { text: i18nc("general.mute-style.led", "Button with an LED"), value: "led" }
            ]
            onActivated: page.cfg_muteStyle = currentValue
            function sync() { currentIndex = Math.max(0, indexOfValue(page.cfg_muteStyle)) }
            Component.onCompleted: sync()
        }
        QQC2.ComboBox {
            id: ledBlink
            Kirigami.FormData.label: i18nc("general.led-blink.label", "LED blinking:")
            enabled: page.cfg_muteStyle === "led"
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18nc("general.led-blink.off", "Don’t blink"), value: "off" },
                { text: i18nc("general.led-blink.muted", "Blink when muted"), value: "muted" },
                { text: i18nc("general.led-blink.signal", "Pulse with the signal"), value: "signal" }
            ]
            onActivated: page.cfg_ledBlink = currentValue
            function sync() { currentIndex = Math.max(0, indexOfValue(page.cfg_ledBlink)) }
            Component.onCompleted: sync()
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("general.section.bars", "Volume bars") }

        QQC2.ComboBox {
            id: barShape
            Kirigami.FormData.label: i18nc("general.bar-shape.label", "Shape:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18nc("general.bar-shape.wedge", "Wedge, handle on the left"), value: "wedge" },
                { text: i18nc("general.bar-shape.bar", "Narrow rectangle, handle in the centre"), value: "bar" },
                { text: i18nc("general.bar-shape.barleft", "Narrow rectangle, handle on the left"), value: "barleft" }
            ]
            onActivated: page.cfg_barShape = currentValue
            // Legacy barStyle=bar/barled values meant the "rectangle" shape.
            function sync() {
                const legacy = page.cfg_barStyle === "bar" || page.cfg_barStyle === "barled"
                currentIndex = Math.max(0, indexOfValue(page.cfg_barShape !== "" ? page.cfg_barShape : (legacy ? "bar" : "wedge")))
            }
            Component.onCompleted: sync()
        }
        QQC2.ComboBox {
            id: handleOrientation
            Kirigami.FormData.label: i18nc("general.handle.label", "Handle:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18nc("general.handle.horizontal", "Horizontal"), value: "horizontal" },
                { text: i18nc("general.handle.vertical", "Vertical"), value: "vertical" }
            ]
            onActivated: page.cfg_handleOrientation = currentValue
            function sync() { currentIndex = Math.max(0, indexOfValue(page.cfg_handleOrientation)) }
            Component.onCompleted: sync()
        }
        QQC2.ComboBox {
            id: barStyle
            Kirigami.FormData.label: i18nc("general.fill.label", "Fill:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18nc("general.fill.plain", "Plain"), value: "plain" },
                { text: i18nc("general.fill.glass", "Glass"), value: "glass" },
                { text: i18nc("general.fill.led", "LED meter"), value: "led" }
            ]
            onActivated: {
                page.cfg_barStyle = currentValue
                if (page.cfg_barShape === "") page.cfg_barShape = barShape.currentValue
            }
            function sync() {
                // Legacy "zones" was the plain fill with colour-by-zone.
                const s = page.cfg_barStyle === "bar" || page.cfg_barStyle === "zones" ? "plain" : (page.cfg_barStyle === "barled" ? "led" : page.cfg_barStyle)
                currentIndex = Math.max(0, indexOfValue(s))
            }
            Component.onCompleted: {
                if (page.cfg_barStyle === "zones") {
                    page.cfg_barStyle = "plain"
                    page.cfg_zoneColors = true
                }
                sync()
            }
        }
        QQC2.ComboBox {
            id: signalScale
            Kirigami.FormData.label: i18nc("general.signal-scale.label", "Signal-level scale:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18nc("general.signal-scale.linear", "Linear: peak as-is, speech ≈ 25 %"), value: "linear" },
                { text: i18nc("general.signal-scale.db", "In decibels, 60 dB: speech ≈ 80 %"), value: "db" }
            ]
            onActivated: page.cfg_signalScale = currentValue
            function sync() { currentIndex = Math.max(0, indexOfValue(page.cfg_signalScale)) }
            Component.onCompleted: sync()
        }
        Connections {
            target: page
            function onCfg_signalScaleChanged() { signalScale.sync() }
            function onCfg_handleOrientationChanged() { handleOrientation.sync() }
            function onCfg_barStyleChanged() { barStyle.sync(); barShape.sync() }
            function onCfg_barShapeChanged() { barShape.sync() }
            function onCfg_defaultMarkChanged() { defaultMark.sync() }
            function onCfg_muteStyleChanged() { muteStyle.sync() }
            function onCfg_ledBlinkChanged() { ledBlink.sync() }
        }

        QQC2.CheckBox {
            id: useCustomColors
            text: i18nc("general.custom-colors", "Custom colours (otherwise theme colours)")
        }
        QQC2.CheckBox {
            id: zoneColors
            text: i18nc("general.zone-colors", "Colour volume by level: green, yellow, red")
        }
        QQC2.CheckBox {
            id: zoneBySignal
            enabled: zoneColors.checked
            text: i18nc("general.zone-by-signal", "Fill tracks the signal: zone height and colour follow its level, no stream — empty")
        }
        RowLayout {
            Kirigami.FormData.label: i18nc("general.volume.label", "Volume:")
            spacing: Kirigami.Units.smallSpacing
            ColorPickButton { id: fillColor; enabled: useCustomColors.checked && !zoneColors.checked; showAlphaChannel: false }
            QQC2.Label { text: i18nc("general.opacity", "opacity") }
            QQC2.SpinBox { id: fillOpacity; from: 10; to: 100; stepSize: 5; textFromValue: (v) => v + " %"; valueFromText: (t) => parseInt(t) }
        }
        RowLayout {
            Kirigami.FormData.label: i18nc("general.signal.label", "Signal level:")
            spacing: Kirigami.Units.smallSpacing
            ColorPickButton { id: peakColor; enabled: useCustomColors.checked; showAlphaChannel: false }
            QQC2.Label { text: i18nc("general.opacity", "opacity") }
            QQC2.SpinBox { id: peakOpacity; from: 10; to: 100; stepSize: 5; textFromValue: (v) => v + " %"; valueFromText: (t) => parseInt(t) }
        }
        RowLayout {
            Kirigami.FormData.label: i18nc("general.dim.label", "Unfilled part:")
            spacing: Kirigami.Units.smallSpacing
            ColorPickButton { id: dimColor; enabled: useCustomColors.checked; showAlphaChannel: false }
            QQC2.Label { text: i18nc("general.opacity", "opacity") }
            QQC2.SpinBox { id: dimOpacity; from: 5; to: 100; stepSize: 5; textFromValue: (v) => v + " %"; valueFromText: (t) => parseInt(t) }
        }

    }

    Dialogs.FontDialog {
        id: fontDialog
        title: i18nc("general.font.dialog-title", "Font for device and application labels")
        onAccepted: {
            page.cfg_labelFontFamily = selectedFont.family
            page.cfg_labelFontSize = Math.round(selectedFont.pointSize)
            page.cfg_labelFontBold = selectedFont.bold
        }
    }
}

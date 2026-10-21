/*
    Color-picker button: looks and behaves like KQuickControls.ColorButton (same color and
    showAlphaChannel properties), but the dialog comes from Qt.labs.platform so plasmashell
    (which is a QApplication) opens the widget-based QColorDialog, with its colour square and
    the palette of basic colours.
    ponytail: ColorButton uses QtQuick.Dialogs, and on Qt 6.10 in plasmashell its saturation/
    lightness square doesn't paint (comes up blank) and the basic palette is missing.
    Qt.labs.platform is marked deprecated — if it goes away, switch back to ColorButton.
*/

import QtQuick
import QtQuick.Controls as QQC2
import Qt.labs.platform as Platform

QQC2.Button {
    id: root

    property color color
    property bool showAlphaChannel: true

    implicitWidth: 48 // same as ColorButton: 40 + 4-px margins on both sides

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        color: root.enabled ? root.color : disabledPalette.button
        SystemPalette {
            id: disabledPalette
            colorGroup: SystemPalette.Disabled
        }
    }

    Platform.ColorDialog {
        id: dialog
        options: root.showAlphaChannel ? Platform.ColorDialog.ShowAlphaChannel : 0
        onAccepted: root.color = dialog.color
    }

    onClicked: {
        dialog.currentColor = root.color
        dialog.open()
    }
}

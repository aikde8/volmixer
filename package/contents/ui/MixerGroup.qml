/*
    SPDX-FileCopyrightText: 2026 AIKDE
    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL

    Mixer group: theme frame, title, and a horizontal list of items of a single type.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras

Item {
    id: group

    property string title
    property string /* "sink" | "sink-input" | "source" | "source-output" | "event" */ type
    property alias model: view.model
    property alias view: view
    // For streams: model of devices in the same direction (used for "playing on" tooltip and drag/drop)
    property var devicesModel: null

    visible: view.count > 0
    Layout.fillHeight: true
    implicitWidth: view.contentWidth + frame.margins.left + frame.margins.right

    KSvg.FrameSvgItem {
        id: frame
        anchors.fill: parent
        imagePath: "widgets/frame"
        prefix: "plain"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: frame.margins.left
        anchors.rightMargin: frame.margins.right
        anchors.topMargin: frame.margins.top
        anchors.bottomMargin: frame.margins.bottom
        spacing: Kirigami.Units.smallSpacing

        PlasmaExtras.Heading {
            Layout.fillWidth: true
            level: 4
            text: group.title
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        ListView {
            id: view
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            interactive: false
            spacing: 0
            keyNavigationEnabled: true
            currentIndex: -1
            Accessible.name: group.title
            Accessible.role: Accessible.List

            delegate: MixerItem {
                height: ListView.view.height
                type: group.type
                devicesModel: group.devicesModel
                focus: ListView.isCurrentItem
            }

            highlight: PlasmaExtras.Highlight {
                visible: view.activeFocus
            }
            highlightMoveDuration: Kirigami.Units.shortDuration

        }
    }
}

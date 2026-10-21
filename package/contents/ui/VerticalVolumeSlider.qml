/*
    SPDX-FileCopyrightText: 2014-2015 Harald Sitter <sitter@kde.org>
    SPDX-FileCopyrightText: 2019 Sefa Eyeoglu <contact@scrumplex.net>
    SPDX-FileCopyrightText: 2022 ivan (@ratijas) tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2026 AIKDE

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL

    Vertical volume slider. Mechanics come from the stock applet's VolumeSlider (VolumeMonitor
    for the signal level, wheel handling, limit-change animation). The look is a Windows 7
    style wedge: narrow at the bottom, wide at the top; fill tracks the volume, a lighter band
    tracks the current signal level, anything above 100 % uses the warning colour.
    The handle is an SVG shipped in the package.
*/
import QtQuick

import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.private.volume

PC3.Slider {
    id: control

    property VolumeObject volumeObject

    // When muted, the whole slider will appear slightly faded, but remain functional and interactive.
    property bool muted: false

    // Current (monitored) volume, 0..1. Animated; do not update too fast.
    property real volume: meter.volume

    readonly property bool overNormal: value > PulseAudio.NormalVolume
    readonly property int handleWidth: 28
    readonly property int handleHeight: 28

    orientation: Qt.Vertical
    implicitWidth: Kirigami.Units.gridUnit * 3
    implicitHeight: Kirigami.Units.gridUnit * 10

    VolumeMonitor {
        id: meter
        target: control.visible ? control.volumeObject : null
    }

    Behavior on volume {
        NumberAnimation  {
            duration: Kirigami.Units.shortDuration
            easing.type: Easing.OutQuad
        }
    }

    // When a maximum volume limit is raised/lower, animate the change.
    Behavior on to {
        NumberAnimation {
            duration: Kirigami.Units.shortDuration
            easing.type: Easing.InOutQuad
        }
    }

    opacity: muted ? 0.5 : 1
    // Prevents the groove from showing through the handle
    layer.enabled: opacity < 1

    wheelEnabled: false
    // `wheelEnabled: true` doesn't work: we can't both respect stepsize on scroll and allow fine-tuning on drag.
    WheelHandler {
        orientation: Qt.Vertical | Qt.Horizontal
        property int wheelDelta: 0
        acceptedButtons: Qt.NoButton
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: wheel => {
            const lastValue = control.value
            const delta = (wheel.angleDelta.y || -wheel.angleDelta.x) * (wheel.inverted ? -1 : 1)
            wheelDelta += delta;
            while (wheelDelta >= 120) {
                wheelDelta -= 120;
                control.increase();
            }
            while (wheelDelta <= -120) {
                wheelDelta += 120;
                control.decrease();
            }
            if (lastValue !== control.value) {
                control.moved();
            }
        }
    }

    background: Canvas {
        id: wedge

        // Same geometry as the original Win7 Mixer: the handle rail is on the left, with a
        // right-angled triangle extending to the right — vertical leg along the rail, hypotenuse
        // on the right, widest at the top (100 %).
        readonly property real trackX: control.handleWidth / 2
        readonly property real trackTop: control.topPadding + control.handleHeight / 2
        readonly property real trackHeight: Math.max(1, control.availableHeight - control.handleHeight)
        readonly property real wedgeWidth: Math.max(8, control.availableWidth - trackX - 6)
        // Fill: plain, glass, led (segmented); shape: wedge, bar (narrow rectangle with handle
        // in the middle), barleft (narrow rectangle with handle on the left). Zone colours
        // (zoneColors) are a separate flag and combine with any fill. The legacy barStyle values
        // bar/barled/zones are migrated here.
        readonly property string cfgStyle: Plasmoid.configuration.barStyle || "plain"
        readonly property string cfgShape: Plasmoid.configuration.barShape || ""
        readonly property string barShape: cfgShape !== "" ? cfgShape : ((cfgStyle === "bar" || cfgStyle === "barled") ? "bar" : "wedge")
        readonly property string barStyle: (cfgStyle === "bar" || cfgStyle === "zones") ? "plain" : (cfgStyle === "barled" ? "led" : cfgStyle)
        readonly property bool zoneColors: Plasmoid.configuration.zoneColors || cfgStyle === "zones"
        // Zone-by-signal mode: the fill IS the signal (height tracks the level, no stream =
        // empty), colour depends on signal strength — on the linear scale up to 0.5 green, up to
        // 0.8 yellow, above red; in decibels: up to −12 dB, up to −3 dB, above.
        readonly property bool zoneBySignal: zoneColors && Plasmoid.configuration.zoneBySignal
        readonly property real signalRatio: signalLevel
        readonly property color zoneSignalColor: signalRatio >= (dbScale ? 0.95 : 0.8) ? Kirigami.Theme.negativeTextColor
            : (signalRatio >= (dbScale ? 0.8 : 0.5) ? Qt.rgba(0.89, 0.78, 0.29, 1) : Kirigami.Theme.positiveTextColor)
        // Colours come from the applet settings (custom or theme) with opacity in percent; the
        // fill above 100 % uses the theme's warning colour.
        readonly property bool customColors: Plasmoid.configuration.useCustomColors
        readonly property color baseDim: customColors ? Plasmoid.configuration.dimColor : Kirigami.Theme.textColor
        readonly property color baseFill: control.overNormal ? Kirigami.Theme.negativeTextColor
                                        : (customColors ? Plasmoid.configuration.fillColor : Kirigami.Theme.highlightColor)
        readonly property color basePeak: control.overNormal ? Qt.lighter(Kirigami.Theme.negativeTextColor, 1.45)
                                        : (customColors ? Plasmoid.configuration.peakColor : Qt.lighter(Kirigami.Theme.highlightColor, 1.45))
        readonly property real dimAlpha: Plasmoid.configuration.dimOpacity / 100 * (control.enabled ? 1 : 0.5)
        readonly property real fillAlpha: Plasmoid.configuration.fillOpacity / 100
        readonly property real peakAlpha: Plasmoid.configuration.peakOpacity / 100
        readonly property color dimColor: Qt.rgba(baseDim.r, baseDim.g, baseDim.b, dimAlpha)
        readonly property color fillColor: Qt.rgba(baseFill.r, baseFill.g, baseFill.b, fillAlpha)
        readonly property color peakColor: Qt.rgba(basePeak.r, basePeak.g, basePeak.b, peakAlpha)
        readonly property real levelFraction: 1 - control.visualPosition
        // Signal level 0..1: either the meter's linear peak or in decibels (60 dB range:
        // 0.25 = −12 dB → 0.8).
        readonly property bool dbScale: Plasmoid.configuration.signalScale === "db"
        readonly property real signalLevel: !meter.available || control.volume <= 0 ? 0
            : (dbScale ? Math.max(0, Math.min(1, 1 + 20 * Math.log10(control.volume) / 60)) : Math.min(1, control.volume))
        readonly property real peakFraction: Math.min(levelFraction, signalLevel * levelFraction)

        x: control.leftPadding
        y: 0
        width: control.availableWidth
        height: control.height

        onLevelFractionChanged: requestPaint()
        onPeakFractionChanged: requestPaint()
        onFillColorChanged: requestPaint()
        onDimColorChanged: requestPaint()
        onPeakColorChanged: requestPaint()
        onBarStyleChanged: requestPaint()
        onBarShapeChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

        // Narrow rectangle instead of the wedge: half the width, with the whole group
        // (handle + bar) centred below the icon.
        readonly property bool rectShape: barShape !== "wedge"
        readonly property real barWidth: Math.round(wedgeWidth * 0.65)
        readonly property real cx: control.availableWidth / 2
        readonly property real groupWidth: barShape === "barleft" ? control.handleWidth + 2 + barWidth : Math.max(control.handleWidth, barWidth)
        readonly property real handleX: !rectShape ? 0 : (barShape === "barleft" ? Math.round(cx - groupWidth / 2) : Math.round(cx - control.handleWidth / 2))
        readonly property real barLeft: barShape === "barleft" ? handleX + control.handleWidth + 2 : Math.round(cx - barWidth / 2)
        readonly property real barRight: barLeft + barWidth

        // Shape cropped from the bottom to the given fraction: either a wedge (rail-bottom →
        // rail-level → hypotenuse-at-level) or a barWidth-wide rectangle centred on the rail
        // (and on the handle).
        function wedgePath(ctx, fraction) {
            const bottom = trackTop + trackHeight
            const h = trackHeight * fraction
            ctx.beginPath()
            if (rectShape) {
                ctx.rect(barLeft, bottom - h, barWidth, h)
                return
            }
            ctx.moveTo(trackX, bottom)
            ctx.lineTo(trackX, bottom - h)
            ctx.lineTo(trackX + wedgeWidth * fraction, bottom - h)
            ctx.closePath()
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const glass = barStyle === "glass", led = barStyle === "led", zones = zoneColors
            const white = Qt.rgba(1, 1, 1, 1)
            const bottom = trackTop + trackHeight

            // Unfilled part.
            ctx.fillStyle = glass ? rgba(white, Math.min(0.3, dimAlpha * 0.35)) : dimColor
            wedgePath(ctx, 1)
            ctx.fill()
            if (glass) {
                ctx.strokeStyle = rgba(white, 0.3); ctx.lineWidth = 1
                wedgePath(ctx, 1); ctx.stroke()
            }

            // Fill: tracks the volume, except in "zone-by-signal" mode where it tracks the signal
            // level (no stream → empty).
            const fillFraction = zoneBySignal ? peakFraction : levelFraction
            if (fillFraction > 0) {
                if (zones) {
                    // VU-meter-style colouring by level: theme negative at the top,
                    // neutral/warning in the middle, positive at the bottom. Slightly more
                    // transparent under glass, like the normal fill.
                    const a = glass ? fillAlpha * 0.75 : fillAlpha
                    if (zoneBySignal) {
                        ctx.fillStyle = rgba(zoneSignalColor, a)
                    } else {
                        const g = ctx.createLinearGradient(0, trackTop, 0, bottom)
                        g.addColorStop(0, rgba(Kirigami.Theme.negativeTextColor, a))
                        g.addColorStop(0.3, rgba(Kirigami.Theme.neutralTextColor, a))
                        g.addColorStop(0.55, rgba(Qt.rgba(0.89, 0.78, 0.29, 1), a))
                        g.addColorStop(1, rgba(Kirigami.Theme.positiveTextColor, a))
                        ctx.fillStyle = g
                    }
                } else {
                    ctx.fillStyle = glass ? rgba(baseFill, fillAlpha * 0.75) : fillColor
                }
                wedgePath(ctx, fillFraction)
                ctx.fill()
            }

            // Signal level drawn on top of the fill (in zone-by-signal mode the fill already
            // shows it).
            if (peakFraction > 0 && !zoneBySignal) {
                ctx.fillStyle = (glass || zones) ? rgba(white, Math.min(0.45, peakAlpha * 0.45)) : peakColor
                wedgePath(ctx, peakFraction)
                ctx.fill()
            }

            // Glass: highlight along the rail.
            if (glass) {
                ctx.fillStyle = rgba(white, 0.14)
                ctx.beginPath()
                ctx.moveTo(trackX + 2, bottom - 4)
                ctx.lineTo(trackX + 2, trackTop + 6)
                ctx.lineTo(trackX + 10, trackTop + 6)
                ctx.closePath()
                ctx.fill()
            }

            // Rectangle: concave shading — dark edges on the left, top and right, with a light
            // highlight on the right.
            if (rectShape) {
                // Dark edges left and right with a wide transition, shadow at the top,
                // light highlight on the right and bottom.
                const gx = ctx.createLinearGradient(barLeft, 0, barRight, 0)
                gx.addColorStop(0, "rgba(0,0,0,0.7)"); gx.addColorStop(0.4, "rgba(0,0,0,0)")
                gx.addColorStop(0.7, "rgba(0,0,0,0)"); gx.addColorStop(1, "rgba(0,0,0,0.55)")
                ctx.fillStyle = gx
                ctx.fillRect(barLeft, trackTop, barWidth, trackHeight)
                const gy = ctx.createLinearGradient(0, trackTop, 0, trackTop + 16)
                gy.addColorStop(0, "rgba(0,0,0,0.7)"); gy.addColorStop(1, "rgba(0,0,0,0)")
                ctx.fillStyle = gy
                ctx.fillRect(barLeft, trackTop, barWidth, 16)
                const gb = ctx.createLinearGradient(0, bottom - 6, 0, bottom)
                gb.addColorStop(0, "rgba(255,255,255,0)"); gb.addColorStop(1, "rgba(255,255,255,0.22)")
                ctx.fillStyle = gb
                ctx.fillRect(barLeft, bottom - 6, barWidth, 6)
                ctx.fillStyle = "rgba(255,255,255,0.28)"
                ctx.fillRect(barRight - 1.5, trackTop, 1.5, trackHeight)
                ctx.fillStyle = "rgba(0,0,0,0.5)"
                ctx.fillRect(barLeft, trackTop, 1, trackHeight)
            }

            // LEDs: transparent slits every 10 px cut the shape into segments.
            if (led) {
                for (let y = trackTop + 8; y < bottom - 2; y += 10) {
                    ctx.clearRect(rectShape ? barLeft - 2 : trackX - 2, y, rectShape ? barWidth + 4 : wedgeWidth + 12, 2.5)
                }
            }

            // Handle rail (drawn after the slits so it stays continuous): wedge uses the left
            // edge; "handle on the left" variant has its own rail with ticks under the handle;
            // for a centre-handle rectangle no rail is needed.
            const steps = control.to > PulseAudio.NormalVolume ? 15 : 10
            const railX = barShape === "barleft" ? handleX + control.handleWidth / 2 : trackX
            if (!rectShape || barShape === "barleft") {
                ctx.strokeStyle = dimColor
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.moveTo(railX, trackTop)
                ctx.lineTo(railX, bottom)
                ctx.stroke()
            }
            if (barShape === "barleft") {
                ctx.lineWidth = 1
                for (let i = 1; i < steps; ++i) {
                    const yy = Math.round(trackTop + trackHeight * (1 - i / steps)) + 0.5
                    const half = i % 5 === 0 ? 6 : 3
                    ctx.beginPath()
                    ctx.moveTo(railX - half, yy)
                    ctx.lineTo(railX + half, yy)
                    ctx.stroke()
                }
                return
            }

            // Tick marks along the hypotenuse or the right edge: 0..100 % every 10 %, or up to
            // 150 % when the limit is raised; 50/100/150 % are drawn longer.
            ctx.lineWidth = 1
            for (let i = 1; i < steps; ++i) {
                const f = i / steps
                const yy = Math.round(trackTop + trackHeight * (1 - f)) + 0.5
                const xx = rectShape ? barRight : trackX + wedgeWidth * f
                ctx.beginPath()
                ctx.moveTo(xx + 2, yy)
                ctx.lineTo(xx + 2 + (i % 5 === 0 ? 6 : 3), yy)
                ctx.stroke()
            }
        }
    }

    handle: Image {
        source: Qt.resolvedUrl("../images/vertical-volume-slider.svg")
        sourceSize.width: control.handleWidth
        sourceSize.height: control.handleHeight
        width: control.handleWidth
        height: control.handleHeight
        fillMode: Image.Stretch
        smooth: true
        opacity: control.enabled ? 1 : 0.5
        // "Handle" setting: when vertical, use the same image rotated about its centre (the
        // handle is a 28×28 square, so its placement is unchanged).
        rotation: Plasmoid.configuration.handleOrientation === "vertical" ? 90 : 0
        // Wedge: handle at the left edge, centred on the rail. Rectangle: centred on the bar
        // or placed to its left.
        x: control.leftPadding + wedge.handleX
        y: control.topPadding + Math.round(control.visualPosition * (control.availableHeight - height))
    }
}

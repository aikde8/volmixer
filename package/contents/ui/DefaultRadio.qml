import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// "Default device" radio button: shared visual for the corner (above the icon) and bottom
// (in the bottom row) placements.
// ponytail: kept as its own file rather than a Component+Loader — inside a Loader the name
// `item` resolves to Loader.item, not to the MixerItem.
PC3.RadioButton {
    Accessible.ignored: true
    activeFocusOnTab: false
    PC3.ToolTip.text: checked ? i18nc("mixer.default-radio.on", "Default device") : i18nc("mixer.default-radio.off", "Set as default device")
    PC3.ToolTip.visible: hovered
    PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
}

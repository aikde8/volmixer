import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18nc("tab.view", "View")
        icon: "preferences-desktop-color"
        source: "ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18nc("tab.devices", "Devices")
        icon: "audio-headset"
        source: "ConfigDevices.qml"
    }
    ConfigCategory {
        name: i18nc("tab.logic", "Logic")
        icon: "flow-branch"
        source: "ConfigLogic.qml"
    }
}

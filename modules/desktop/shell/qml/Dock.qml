// Dock: pinned apps on a translucent panel. Icons grow under the pointer;
// a dot marks apps that are running.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "theme.js" as Theme

PanelWindow {
    id: dock

    // Desktop entry ids, left to right.
    readonly property var pinned: [
        "firefox",
        "org.kde.dolphin",
        "org.kde.konsole",
        "steam",
        "systemsettings",
    ]
    readonly property real hoverScale: 1.25

    anchors.bottom: true
    // Room above the panel for the enlarged icon; only the panel takes input
    // and reserves space.
    implicitWidth: apps.implicitWidth + 2 * Theme.dockPadding
    implicitHeight: Theme.dockIcon * hoverScale + Theme.dockPadding * 2 + Theme.dockMargin
    exclusiveZone: panel.height + Theme.dockMargin
    mask: Region { item: panel }
    color: "transparent"
    WlrLayershell.namespace: "anka-dock"

    Rectangle {
        id: panel
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: Theme.dockMargin
        }
        height: Theme.dockIcon + 2 * Theme.dockPadding
        radius: Theme.dockRadius
        color: Theme.glass
        border.color: Theme.hairline
        border.width: 1
    }

    Row {
        id: apps
        anchors {
            horizontalCenter: panel.horizontalCenter
            bottom: panel.bottom
            bottomMargin: Theme.dockPadding
        }
        spacing: 10

        Repeater {
            model: dock.pinned

            Item {
                id: slot
                required property string modelData
                readonly property var entry: DesktopEntries.byId(modelData)
                readonly property bool running: ToplevelManager.toplevels.values
                                                .some(t => t.appId === slot.modelData)

                visible: entry !== null
                width: Theme.dockIcon
                height: Theme.dockIcon

                Image {
                    anchors.fill: parent
                    source: slot.entry ? Quickshell.iconPath(slot.entry.icon) : ""
                    sourceSize: Qt.size(Theme.dockIcon * 2, Theme.dockIcon * 2)
                    transformOrigin: Item.Bottom
                    scale: hover.containsMouse ? dock.hoverScale : 1.0

                    Behavior on scale {
                        NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic }
                    }
                }

                Rectangle {
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        top: parent.bottom
                        topMargin: 3
                    }
                    width: 4
                    height: 4
                    radius: 2
                    color: Theme.text
                    visible: slot.running
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (slot.entry) slot.entry.execute()
                }
            }
        }
    }
}

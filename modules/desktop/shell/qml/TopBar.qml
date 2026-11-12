// Top bar: ANKA logo, workspaces and the active window on the left,
// date and time on the right.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "theme.js" as Theme

PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: "transparent"
    WlrLayershell.namespace: "anka-bar"

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.glass

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 1
            color: Theme.hairline
        }
    }

    Row {
        anchors {
            left: parent.left
            leftMargin: 14
            verticalCenter: parent.verticalCenter
        }
        spacing: 16

        Image {
            anchors.verticalCenter: parent.verticalCenter
            source: "logo.svg"
            sourceSize: Qt.size(18, 18)
        }

        // Workspaces 1–5: dots, the current one stretches into a pill.
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: 5

                Rectangle {
                    id: dot
                    required property int index
                    readonly property int workspace: index + 1
                    readonly property bool current: Hyprland.focusedWorkspace !== null
                                                    && Hyprland.focusedWorkspace.id === workspace

                    width: current ? 18 : 7
                    height: 7
                    radius: height / 2
                    color: current ? Theme.text : Theme.textDim

                    Behavior on width {
                        NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        ColorAnimation { duration: Theme.fast }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hyprland.dispatch("workspace " + dot.workspace)
                    }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, bar.width * 0.4)
            elide: Text.ElideRight
            text: ToplevelManager.activeToplevel ? ToplevelManager.activeToplevel.title : ""
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.barFontSize
            font.weight: Font.DemiBold
        }
    }

    Text {
        anchors {
            right: parent.right
            rightMargin: 16
            verticalCenter: parent.verticalCenter
        }
        text: Qt.locale().toString(clock.date, "ddd d MMM   HH:mm")
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.barFontSize
        font.weight: Font.Medium
    }
}

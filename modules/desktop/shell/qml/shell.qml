// ANKA Shell — entry point, started by Hyprland: quickshell -p shell.qml
// One wallpaper, top bar and dock per screen.
import QtQuick
import Quickshell

ShellRoot {
    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            Wallpaper { screen: perScreen.modelData }
            TopBar { screen: perScreen.modelData }
            Dock { screen: perScreen.modelData }
        }
    }
}

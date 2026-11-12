// The desktop background. The 4K ANKA wallpaper is decoded at screen size
// (sourceSize) to keep memory low.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "theme.js" as Theme

PanelWindow {
    id: root

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "anka-wallpaper"
    color: Theme.desktop

    Image {
        readonly property string path: Quickshell.env("ANKA_WALLPAPER") || ""

        anchors.fill: parent
        source: path !== "" ? "file://" + path : ""
        sourceSize: Qt.size(root.width, root.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }
}

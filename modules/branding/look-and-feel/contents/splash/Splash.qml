// ANKA splash, shown while the desktop starts: the logo and a thin progress
// bar on black, in the same place as on the boot screen.
import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: root
    color: "black"

    property int stage   // set by ksplash, 1 … 6

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        // Same places as the boot splash (../../../plymouth/anka.plymouth)
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round((parent.height - height) * 0.45)
            source: "images/anka.svg"
            sourceSize.width: 128
            sourceSize.height: 128
        }

        Rectangle {
            width: 160
            height: 4
            radius: 2
            color: "#333333"
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round((parent.height - height) * 0.62)

            Rectangle {
                width: parent.width * Math.min(root.stage, 6) / 6
                height: parent.height
                radius: parent.radius
                color: "#f5f5f7"
                Behavior on width {
                    NumberAnimation { duration: Kirigami.Units.longDuration * 2; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    OpacityAnimator {
        target: content
        from: 0
        to: 1
        duration: Kirigami.Units.longDuration * 2
        easing.type: Easing.InOutQuad
        running: true
    }
}

// A window's actions: the main one filled with the accent colour, the
// others (primary: false) in the button colour, both the same size.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

QQC2.Button {
    id: button

    property bool primary: true

    implicitWidth: Math.max(Kirigami.Units.gridUnit * 6, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(Kirigami.Units.gridUnit * 2, implicitContentHeight + topPadding + bottomPadding)
    leftPadding: Kirigami.Units.gridUnit
    rightPadding: Kirigami.Units.gridUnit

    Kirigami.Theme.colorSet: Kirigami.Theme.Button
    Kirigami.Theme.inherit: false

    contentItem: QQC2.Label {
        text: button.text
        color: button.primary ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
        font.weight: button.primary ? Font.DemiBold : Font.Normal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        readonly property color base: button.primary ? Kirigami.Theme.highlightColor : Kirigami.Theme.backgroundColor
        radius: Kirigami.Units.cornerRadius
        color: button.down ? Qt.darker(base, 1.15) : button.hovered ? Qt.lighter(base, 1.1) : base
        border.width: button.visualFocus ? 2 : 0
        border.color: Kirigami.Theme.focusColor
    }
}

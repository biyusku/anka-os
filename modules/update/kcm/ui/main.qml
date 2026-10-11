// System Settings › ANKA Updates: the version, one line of status, one
// main action. The log and going back to the previous version are one
// click further away.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

KCMUtils.SimpleKCM {
    id: root

    function t(tr, en) { return Qt.locale().name.startsWith("tr") ? tr : en }

    property bool showDetails: false

    implicitWidth: Kirigami.Units.gridUnit * 32
    implicitHeight: Kirigami.Units.gridUnit * 26

    // The window's main action: filled with the accent colour.
    component ActionButton: QQC2.Button {
        id: button
        property bool primary: true

        implicitWidth: Math.max(Kirigami.Units.gridUnit * 8, implicitContentWidth + leftPadding + rightPadding)
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

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Item { implicitHeight: Kirigami.Units.gridUnit * 2 }

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Kirigami.Units.iconSizes.huge * 1.5
            implicitHeight: Kirigami.Units.iconSizes.huge * 1.5
            source: "anka"
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            horizontalAlignment: Text.AlignHCenter
            text: kcm.currentVersion.length > 0 ? "ANKA OS " + kcm.currentVersion : "ANKA OS"
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.8
            font.weight: Font.DemiBold
        }

        QQC2.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
            text: {
                if (kcm.updating)               return root.t("Güncelleniyor… Bu sırada bilgisayarını kullanabilirsin.",
                                                              "Updating… You can keep using your computer.")
                if (kcm.checking)               return root.t("Güncellemeler denetleniyor…", "Checking for updates…")
                if (kcm.statusError.length > 0) return kcm.statusError
                if (kcm.updateAvailable)        return root.t("ANKA %1 hazır.", "ANKA %1 is available.").arg(kcm.availableVersion)
                return root.t("ANKA güncel.", "ANKA is up to date.")
            }
            color: kcm.statusError.length > 0 && !kcm.updating && !kcm.checking
                   ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
        }

        QQC2.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: kcm.updating || kcm.checking
            running: visible
        }

        // ── The one thing to do now ─────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            ActionButton {
                visible: kcm.updateAvailable && !kcm.updating && !kcm.checking
                text: root.t("Şimdi Güncelle", "Update Now")
                onClicked: kcm.startUpdate()
            }
            ActionButton {
                primary: false
                visible: kcm.updating
                text: root.t("Durdur", "Stop")
                onClicked: kcm.cancelUpdate()
            }
            ActionButton {
                primary: false
                visible: !kcm.updateAvailable && !kcm.updating && !kcm.checking
                text: root.t("Yeniden Denetle", "Check Again")
                onClicked: kcm.checkForUpdates()
            }
        }

        // ── One click further: what's new, the log, the previous version ─
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.smallSpacing

            QQC2.ToolButton {
                visible: kcm.updateAvailable && kcm.releaseNotesUrl.length > 0
                text: root.t("Yenilikler", "What's New")
                onClicked: Qt.openUrlExternally(kcm.releaseNotesUrl)
            }
            QQC2.ToolButton {
                text: root.showDetails ? root.t("Ayrıntıları Gizle", "Hide Details") : root.t("Ayrıntılar", "Details")
                checkable: true
                checked: root.showDetails
                onToggled: {
                    root.showDetails = checked
                    if (checked) kcm.readLog()
                }
            }
            QQC2.ToolButton {
                enabled: !kcm.updating
                text: root.t("Önceki Sürüme Dön…", "Go Back to the Previous Version…")
                onClicked: rollbackDialog.open()
            }
        }

        QQC2.TextArea {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 12
            visible: root.showDetails
            readOnly: true
            wrapMode: TextEdit.Wrap
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: kcm.updateLog.length > 0 ? kcm.updateLog : root.t("Henüz güncelleme yapılmadı.", "No updates yet.")
        }
    }

    Kirigami.PromptDialog {
        id: rollbackDialog
        title: root.t("Önceki sürüme dönülsün mü?", "Go back to the previous version?")
        subtitle: root.t("ANKA, son güncellemeden önceki haline döner. Dosyaların etkilenmez.",
                         "ANKA returns to how it was before the last update. Your files are not affected.")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: kcm.rollback()
    }
}

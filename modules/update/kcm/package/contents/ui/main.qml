import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami
import org.kde.kcmutils as KCMUtils

KCMUtils.SimpleKCM {
    id: root

    implicitWidth:  Kirigami.Units.gridUnit * 36
    implicitHeight: Kirigami.Units.gridUnit * 28

    // ── Header ────────────────────────────────────────────────────────────────
    header: ColumnLayout {
        spacing: 0

        Kirigami.InlineMessage {
            id: updateBanner
            Layout.fillWidth: true
            visible: kcm.updateAvailable && !kcm.updating
            type: Kirigami.MessageType.Positive
            text: qsTr("Kiwimi OS %1 sürümü mevcut.").arg(kcm.availableVersion)

            actions: [
                Kirigami.Action {
                    text: qsTr("Şimdi Güncelle")
                    icon.name: "system-software-update"
                    onTriggered: kcm.startUpdate()
                },
                Kirigami.Action {
                    text: qsTr("Değişiklik Notları")
                    icon.name: "internet-web-browser"
                    onTriggered: Qt.openUrlExternally(
                        "https://github.com/kiwimi-os/kiwimi/releases/tag/v" + kcm.availableVersion
                    )
                }
            ]
        }
    }

    // ── Body ──────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        // Current version card
        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.Label {
                Kirigami.FormData.label: qsTr("Yüklü Sürüm:")
                text: kcm.currentVersion
                font.bold: true
            }

            QQC2.Label {
                Kirigami.FormData.label: qsTr("Durum:")
                text: {
                    if (kcm.updating)        return qsTr("Güncelleniyor…")
                    if (kcm.updateAvailable) return qsTr("Güncelleme mevcut: %1").arg(kcm.availableVersion)
                    return qsTr("Sistem güncel")
                }
                color: {
                    if (kcm.updating)        return Kirigami.Theme.neutralTextColor
                    if (kcm.updateAvailable) return Kirigami.Theme.positiveTextColor
                    return Kirigami.Theme.textColor
                }
            }
        }

        // Progress indicator (only visible while updating)
        ColumnLayout {
            Layout.fillWidth: true
            visible: kcm.updating
            spacing: Kirigami.Units.smallSpacing

            QQC2.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: kcm.updating
            }

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Güncelleme uygulanıyor, lütfen bekleyin…")
                wrapMode: Text.WordWrap
            }
        }

        // Log output (visible while updating OR after readLog)
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: kcm.updateLog.length > 0

            QQC2.TextArea {
                readOnly: true
                wrapMode: TextEdit.Wrap
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: kcm.updateLog
                background: Rectangle {
                    color: Kirigami.Theme.alternateBackgroundColor
                    radius: Kirigami.Units.smallSpacing
                }
            }
        }

        // "System is up to date" placeholder
        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            visible: !kcm.updateAvailable && !kcm.updating && kcm.updateLog.length === 0
            icon.name: "security-high"
            text: qsTr("Sistem Güncel")
            explanation: qsTr("Kiwimi OS %1 en son sürüm.").arg(kcm.currentVersion)
        }

        // ── Action buttons ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: qsTr("Güncellemeleri Kontrol Et")
                icon.name: "view-refresh"
                enabled: !kcm.updating
                onClicked: kcm.checkForUpdates()
            }

            QQC2.Button {
                text: qsTr("Güncelle")
                icon.name: "system-software-update"
                visible: kcm.updateAvailable && !kcm.updating
                highlighted: true
                onClicked: kcm.startUpdate()
            }

            QQC2.Button {
                text: qsTr("İptal")
                icon.name: "dialog-cancel"
                visible: kcm.updating
                onClicked: kcm.cancelUpdate()
            }

            QQC2.Button {
                text: qsTr("Güncellemeleri Göster")
                icon.name: "document-preview"
                enabled: !kcm.updating
                onClicked: kcm.readLog()
            }

            Item { Layout.fillWidth: true }

            // Rollback — always visible
            QQC2.Button {
                text: qsTr("Önceki Sürüme Dön")
                icon.name: "edit-undo"
                enabled: !kcm.updating
                onClicked: rollbackDialog.open()
            }
        }
    }

    // ── Rollback confirmation dialog ─────────────────────────────────────────
    Kirigami.PromptDialog {
        id: rollbackDialog
        title: qsTr("Rollback Onayı")
        subtitle: qsTr(
            "Sistemi bir önceki NixOS nesline geri almak istiyor musunuz? " +
            "Bu işlem mevcut oturumu kapatabilir."
        )
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: kcm.rollback()
    }
}
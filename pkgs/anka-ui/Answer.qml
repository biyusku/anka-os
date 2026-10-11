// ANKA AI's answer to a question asked from KRunner (Alt+Space, "ai …").
// The answer is set by main.cpp when it has arrived on stdin.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.ApplicationWindow {
    id: window

    required property bool turkish
    required property string question
    property string answer
    property bool finished: false

    function t(tr, en) { return turkish ? tr : en }

    title: "ANKA AI"
    width: Kirigami.Units.gridUnit * 32
    height: Kirigami.Units.gridUnit * 24
    minimumWidth: Kirigami.Units.gridUnit * 20
    minimumHeight: Kirigami.Units.gridUnit * 12
    visible: true
    color: Kirigami.Theme.backgroundColor

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.largeSpacing

        // The question
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignTop
                implicitWidth: Kirigami.Units.iconSizes.medium
                implicitHeight: Kirigami.Units.iconSizes.medium
                source: "anka-ai"
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: window.question
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                font.weight: Font.DemiBold
            }
        }

        // Thinking…
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !window.finished

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Kirigami.Units.largeSpacing

                QQC2.BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    running: !window.finished
                }
                QQC2.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: window.t("Düşünüyor…", "Thinking…")
                    color: Kirigami.Theme.disabledTextColor
                }
            }
        }

        // The answer (Markdown, selectable)
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: window.finished

            QQC2.TextArea {
                id: answerText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.MarkdownText
                text: window.answer.length > 0 ? window.answer : window.t("Yanıt alınamadı.", "No answer.")
                leftPadding: 0
                rightPadding: 0
                background: null
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }

        RowLayout {
            Layout.fillWidth: true

            ActionButton {
                primary: false
                visible: window.finished && window.answer.length > 0
                text: window.t("Kopyala", "Copy")
                onClicked: {
                    answerText.selectAll()
                    answerText.copy()
                    answerText.deselect()
                }
            }
            Item { Layout.fillWidth: true }
            ActionButton {
                text: window.t("Tamam", "Done")
                onClicked: window.close()
            }
        }
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: window.close()
    }
}

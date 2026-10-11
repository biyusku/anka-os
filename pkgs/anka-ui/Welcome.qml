// First-login welcome: a few quiet pages in one window.
// Exits with 10 (AI assistant on), 11 (off) or 0 (not asked).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.ApplicationWindow {
    id: window

    required property bool turkish
    required property bool hasAi
    required property bool hasSteam
    required property bool hasBottles

    property int aiChoice: 0
    function t(tr, en) { return turkish ? tr : en }

    function next() {
        if (pages.currentIndex < pages.count - 1) {
            pages.currentIndex += 1
        } else {
            Qt.exit(aiChoice)
        }
    }

    title: "ANKA OS"
    width: Kirigami.Units.gridUnit * 36
    height: Kirigami.Units.gridUnit * 27
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    visible: true
    color: Kirigami.Theme.backgroundColor
    onClosing: Qt.exit(aiChoice)

    // One page: big icon, title, a line of text, optional extra content.
    component Step: Item {
        id: step
        property string icon
        property string heading
        property string text
        default property alias extra: extraColumn.data

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 24)
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                visible: step.icon.length > 0
                implicitWidth: Kirigami.Units.iconSizes.enormous
                implicitHeight: Kirigami.Units.iconSizes.enormous
                source: step.icon
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.largeSpacing
                text: step.heading
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2.2
                font.weight: Font.DemiBold
            }
            QQC2.Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: step.text
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
            }
            ColumnLayout {
                id: extraColumn
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing
            }
        }
    }

    // One line on the last page: icon, what, where.
    component Tip: RowLayout {
        id: tip
        property string icon
        property string fallback: "applications-other"
        property string what
        property string where
        spacing: Kirigami.Units.largeSpacing
        Layout.fillWidth: true

        Kirigami.Icon {
            implicitWidth: Kirigami.Units.iconSizes.large
            implicitHeight: Kirigami.Units.iconSizes.large
            source: tip.icon
            fallback: tip.fallback
        }
        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            QQC2.Label {
                text: tip.what
                font.weight: Font.DemiBold
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: tip.where
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.WordWrap
            }
        }
    }

    QQC2.SwipeView {
        id: pages
        anchors.fill: parent
        anchors.bottomMargin: footerBar.height
        interactive: false
        clip: true

        Component.onCompleted: if (!window.hasAi) removeItem(aiPage)

        Step {
            icon: "anka"
            heading: window.t("Hoş geldin", "Welcome")
            text: window.t("ANKA OS kullanıma hazır.", "ANKA OS is ready.")
        }

        Step {
            id: aiPage
            icon: "anka-ai"
            heading: "ANKA AI"
            text: window.t("Sorularını yanıtlayan asistan. Tamamen bu bilgisayarda çalışır, internete veri göndermez. İlk soruda yaklaşık 5\u00a0GB indirir.",
                           "An assistant that answers your questions. It runs entirely on this computer and sends nothing to the internet. It downloads about 5\u00a0GB on the first question.")
        }

        Step {
            heading: window.t("Hazırsın", "You're all set")

            Tip {
                icon: "plasmadiscover"
                what: window.t("Uygulamalar", "Apps")
                where: "Discover"
            }
            Tip {
                visible: window.hasSteam
                icon: "steam"
                fallback: "applications-games"
                what: window.t("Oyunlar", "Games")
                where: window.t("Steam — Windows oyunları da çalışır", "Steam — Windows games work too")
            }
            Tip {
                visible: window.hasBottles
                icon: "com.usebottles.bottles"
                fallback: "wine"
                what: window.t("Windows programları", "Windows programs")
                where: "Bottles"
            }
            Tip {
                icon: "system-software-update"
                what: window.t("Güncellemeler", "Updates")
                where: window.t("Sistem Ayarları › ANKA Updates", "System Settings › ANKA Updates")
            }
            Tip {
                visible: window.hasAi && window.aiChoice !== 11
                icon: "anka-ai"
                what: "ANKA AI"
                where: window.t("Alt+Boşluk, sonra  ai sorun", "Alt+Space, then  ai your question")
            }
        }
    }

    // Page dots on the left, the buttons on the right.
    RowLayout {
        id: footerBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: Kirigami.Units.gridUnit
        }
        spacing: Kirigami.Units.smallSpacing

        Row {
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: pages.count
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: index === pages.currentIndex ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                    opacity: index === pages.currentIndex ? 1 : 0.4
                }
            }
        }

        Item { Layout.fillWidth: true }

        ActionButton {
            primary: false
            visible: pages.currentItem === aiPage
            text: window.t("Şimdi Değil", "Not Now")
            onClicked: {
                window.aiChoice = 11
                window.next()
            }
        }
        ActionButton {
            id: primary
            text: pages.currentItem === aiPage ? window.t("Aç", "Turn On")
                : pages.currentIndex === pages.count - 1 ? window.t("Başla", "Get Started")
                : window.t("Devam", "Continue")
            onClicked: {
                if (pages.currentItem === aiPage) {
                    window.aiChoice = 10
                }
                window.next()
            }
        }
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        onActivated: primary.clicked()
    }
}

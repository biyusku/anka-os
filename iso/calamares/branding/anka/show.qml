// ANKA OS — shown while ANKA installs (Calamares slideshow API 2).
// One idea per slide, a few words each; colours follow the system.
import QtQuick 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    // The language picked on the first page of the installer
    function t(tr, en) { return Qt.locale().name.indexOf("tr") === 0 ? tr : en }

    SystemPalette { id: palette; colorGroup: SystemPalette.Active }

    Rectangle {
        anchors.fill: parent
        color: palette.window
        z: -1
    }

    Timer {
        interval: 12000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    component AnkaSlide: Slide {
        property string heading
        property string body

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.8, 560)
            spacing: 16

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "logo.svg"
                sourceSize.width: 96
                sourceSize.height: 96
            }
            Item { width: 1; height: 8 }
            Text {
                width: parent.width
                text: heading
                color: palette.windowText
                font.pixelSize: 28
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: body
                color: palette.windowText
                opacity: 0.6
                font.pixelSize: 16
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    AnkaSlide {
        heading: presentation.t("ANKA kuruluyor", "Installing ANKA")
        body: presentation.t("Birkaç dakika sürer. Bitince bilgisayarını yeniden başlatman yeterli.",
                             "This takes a few minutes. When it's done, just restart your computer.")
    }
    AnkaSlide {
        heading: presentation.t("Oyunlar hazır", "Ready for games")
        body: presentation.t("Steam ve Proton ile Windows oyunları da çalışır.",
                             "With Steam and Proton, Windows games work too.")
    }
    AnkaSlide {
        heading: presentation.t("Hızlı ve hafif", "Fast and light")
        body: presentation.t("Eski bilgisayarlarda bile akıcı çalışacak şekilde ayarlandı.",
                             "Tuned to stay smooth even on older computers.")
    }
    AnkaSlide {
        heading: presentation.t("Gönül rahatlığıyla güncelle", "Update without worry")
        body: presentation.t("Bir güncelleme beğenmezsen Sistem Ayarları › ANKA Updates'ten önceki sürüme dön.",
                             "Don't like an update? Go back to the previous version in System Settings › ANKA Updates.")
    }
}

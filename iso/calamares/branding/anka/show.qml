// ANKA OS — slides shown while ANKA installs (Calamares slideshow API 2)
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Timer {
        interval: 15000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    component AnkaSlide: Slide {
        property string title
        property string body
        property string subtitle

        Image {
            id: logo
            source: "logo.svg"
            width: 120; height: 120
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: heading.top
            anchors.bottomMargin: 24
        }
        Text {
            id: heading
            anchors.centerIn: parent
            text: title
            font.pixelSize: 30
            font.weight: Font.DemiBold
            color: "#c0392b"
            width: presentation.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
        Text {
            id: bodyText
            anchors.top: heading.bottom
            anchors.topMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            text: body
            font.pixelSize: 16
            width: presentation.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
        Text {
            anchors.top: bodyText.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            text: subtitle
            font.pixelSize: 13
            color: "#888888"
            width: presentation.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    AnkaSlide {
        title: "ANKA OS'e hoş geldin"
        body: "Eski bir laptop, yeni bir hayat. Kurulum birkaç dakika sürecek."
        subtitle: "Welcome to ANKA OS — this will take a few minutes."
    }
    AnkaSlide {
        title: "Windows oyunları ve uygulamaları"
        body: "Steam, Proton ve Bottles hazır gelir. Oyununu kur ve oyna."
        subtitle: "Steam, Proton and Bottles are included."
    }
    AnkaSlide {
        title: "Hafif ve hızlı"
        body: "CachyOS çekirdeği, zram ve akıllı bellek yönetimi eski donanımda bile akıcı bir deneyim sunar."
        subtitle: "Tuned to stay fast on older hardware."
    }
    AnkaSlide {
        title: "Bozulmayan sistem"
        body: "Her güncelleme ayrı bir sürüm olarak saklanır. Bir şey ters giderse açılışta önceki sürümü seç."
        subtitle: "Every update can be rolled back from the boot menu."
    }
}

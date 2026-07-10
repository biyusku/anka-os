{ config, lib, pkgs, ... }:
let cfg = config.anka.firstrun;
in {
  options.anka.firstrun = {
    enable = lib.mkEnableOption "ANKA first-run setup wizard";
  };

  config = lib.mkIf cfg.enable {
    # First-run wizard systemd user servisi
    systemd.user.services.anka-firstrun = {
      description = "ANKA First Run Setup Wizard";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScript "anka-firstrun" ''
          # Eğer daha önce çalıştıysa atla
          if [ -f "$HOME/.config/anka/.firstrun-done" ]; then
            exit 0
          fi

          # First-run wizard'ı başlat
          ${pkgs.anka-firstrun or pkgs.bash}/bin/anka-firstrun-wizard

          # Tamamlandı olarak işaretle
          mkdir -p "$HOME/.config/anka"
          touch "$HOME/.config/anka/.firstrun-done"
        ''}";
        RemainAfterExit = true;
      };
    };

    # First-run wizard paketi (placeholder — gerçek UI Phase 5'te)
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "anka-firstrun-wizard" ''
        #!/usr/bin/env bash
        # ANKA First Run Wizard
        # Bu wizard ilk açılışta çalışır, 3 soru sorar

        DIALOG=${pkgs.kdialog}/bin/kdialog

        # Hoş geldin
        $DIALOG --title "ANKA'ye Hoş Geldin" \
          --msgbox "Merhaba!\n\nANKA OS'a hoş geldin.\nSana 3 kısa soru soracağım.\nBu 1 dakika sürer." \
          2>/dev/null || true

        # Soru 1: Kullanım amacı
        MODE=$($DIALOG --title "Nasıl kullanacaksın?" \
          --radiolist "Birincil kullanım alanını seç:" \
          gaming "Oyun oynama" on \
          work "İş / Üretkenlik" off \
          both "Her ikisi de" off \
          2>/dev/null) || MODE="gaming"

        # Soru 2: Steam
        if $DIALOG --title "Steam" \
          --yesno "Steam kurulsun mu?\n(Epic, GOG için Heroic zaten kurulu)" \
          2>/dev/null; then
          INSTALL_STEAM=1
        fi

        # Soru 3: AI Asistan
        if $DIALOG --title "ANKA AI" \
          --yesno "ANKA AI asistanı etkinleştirilsin mi?\n(İlk sorularında yardımcı olur)" \
          2>/dev/null; then
          ENABLE_AI=1
        fi

        # Seçimleri uygula
        if [ "$INSTALL_STEAM" = "1" ]; then
          flatpak install -y flathub com.valvesoftware.Steam 2>/dev/null || true
        fi

        if [ "$ENABLE_AI" = "1" ]; then
          systemctl --user enable --now anka-ai-daemon 2>/dev/null || true
        fi

        # Bitti
        $DIALOG --title "Hazır!" \
          --msgbox "ANKA hazır!\n\nİyi eğlenceler." \
          2>/dev/null || true
      '')
    ];
  };
}
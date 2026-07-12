{ pkgs, lib, ... }:

let
  kcm-anka-update = pkgs.stdenv.mkDerivation {
    pname = "kcm-anka-update";
    version = "0.1.0";

    src = ./.;

    nativeBuildInputs = with pkgs; [
      cmake
      extra-cmake-modules
      kdePackages.wrapQtAppsHook
    ];

    buildInputs = with pkgs; [
      qt6.qtbase
      qt6.qtdeclarative
      kdePackages.kcmutils
      kdePackages.ki18n
      kdePackages.kcoreaddons
      kdePackages.kirigami
    ];

    meta = {
      description = "ANKA OS KDE System Settings update panel";
      license = lib.licenses.gpl2Plus;
      platforms = lib.platforms.linux;
    };
  };
in
{
  environment.systemPackages = [ kcm-anka-update ];
}
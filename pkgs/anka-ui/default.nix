# anka-ui — ANKA's own small windows: the first-login welcome and ANKA AI
# answers (see main.cpp). Used by modules/installer and modules/ai.
{ lib, stdenv, cmake, qt6, kdePackages }:

stdenv.mkDerivation {
  pname = "anka-ui";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ cmake qt6.wrapQtAppsHook ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtsvg                         # SVG icons
    kdePackages.kirigami
    kdePackages.qqc2-desktop-style    # native-looking controls
    kdePackages.plasma-integration    # system colours, fonts and icons outside Plasma too
  ];

  meta = {
    description = "ANKA OS welcome and AI answer windows";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "anka-ui";
  };
}

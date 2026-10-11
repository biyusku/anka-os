# ANKA OS — System Settings › ANKA Updates (built by ../default.nix)
{ lib, stdenv, cmake, kdePackages, qt6 }:

stdenv.mkDerivation {
  pname = "kcm-anka-update";
  version = "0.2.0";

  src = ./.;

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
    kdePackages.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    kdePackages.kcmutils
    kdePackages.ki18n
    kdePackages.kcoreaddons
    kdePackages.kirigami
  ];

  # A plugin, not an application: nothing to wrap.
  dontWrapQtApps = true;

  meta = {
    description = "ANKA OS KDE System Settings update panel";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}

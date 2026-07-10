cmake_minimum_required(VERSION 3.20)
project(kcm_kiwimi_update)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Extra CMake Modules ───────────────────────────────────────────────────────
find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

# ── Qt6 ───────────────────────────────────────────────────────────────────────
find_package(Qt6 REQUIRED COMPONENTS Core Quick Network)

# ── KF6 ───────────────────────────────────────────────────────────────────────
find_package(KF6 REQUIRED COMPONENTS
    CoreAddons
    I18n
    KCMUtils
)

# ── KCM target ────────────────────────────────────────────────────────────────
kcmutils_add_qml_kcm(kcm_kiwimi_update
    SOURCES kcm_kiwimi_update.cpp
)

target_link_libraries(kcm_kiwimi_update PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::Network
    KF6::CoreAddons
    KF6::I18n
    KF6::KCMUtils
)

# ── QML package ───────────────────────────────────────────────────────────────
install(
    DIRECTORY package
    DESTINATION ${KDE_INSTALL_QMLDIR}/org/kde/plasma/kiwimi
)

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)
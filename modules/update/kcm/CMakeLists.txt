cmake_minimum_required(VERSION 3.20)
project(kcm_anka_update)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Extra CMake Modules ───────────────────────────────────────────────────────
# A version is required: without it KDECMakeSettings skips the output
# directories that kcoreaddons_add_plugin needs.
find_package(ECM 6.0.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

# ── Qt6 ───────────────────────────────────────────────────────────────────────
find_package(Qt6 REQUIRED COMPONENTS Core Quick)

# ── KF6 ───────────────────────────────────────────────────────────────────────
find_package(KF6 REQUIRED COMPONENTS
    CoreAddons
    I18n
    KCMUtils
)

# ── KCM target (QML from ui/ is compiled in as resources) ─────────────────────
kcmutils_add_qml_kcm(kcm_anka_update
    SOURCES kcm_anka_update.cpp
)

target_link_libraries(kcm_anka_update PRIVATE
    Qt6::Core
    Qt6::Quick
    KF6::CoreAddons
    KF6::I18n
    KF6::KCMUtils
)

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)
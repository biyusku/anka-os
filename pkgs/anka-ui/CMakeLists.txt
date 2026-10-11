cmake_minimum_required(VERSION 3.21)
project(anka-ui LANGUAGES CXX)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 Widgets)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(anka-ui main.cpp)

# The windows (Welcome, Answer) are compiled into the binary.
qt_add_qml_module(anka-ui
    URI org.anka.ui
    VERSION 1.0
    QML_FILES Welcome.qml Answer.qml ActionButton.qml
)

# QApplication: the KDE controls style (org.kde.desktop) draws with QStyle.
target_link_libraries(anka-ui PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)

install(TARGETS anka-ui RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

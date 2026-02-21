cmake_minimum_required(VERSION 3.21)

project(immutable-auditor LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)

qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

qt_add_executable(immutable-auditor
  src/main.cpp
  src/AuditorData.cpp
)

qt_add_qml_module(immutable-auditor
  URI ImmutableAuditor
  VERSION 1.0
  QML_FILES
    qml/Main.qml
)

target_link_libraries(immutable-auditor
  PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2
)

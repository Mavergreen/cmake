cmake_minimum_required(VERSION 3.16)
set(CMAKE_OSX_DEPLOYMENT_TARGET 10.9 CACHE STRING "")
set(CMAKE_OSX_ARCHITECTURES x86_64 CACHE STRING "")
project(CMakeUpdater LANGUAGES OBJC)
find_package(MavericksShipyard REQUIRED)
include(Mavericks)
include(MavericksSparkle)
if(NOT PKG_VERSION MATCHES "-mavericks\\.[0-9]+$")
  message(FATAL_ERROR "PKG_VERSION must be the pkg's <upstream>-mavericks.N (got '${PKG_VERSION}'); build/build-updater.sh passes it")
endif()
# spec: updater/ICON-CREDIT.txt -- the generic icon on purpose, with the reason and the exit
mavericks_add_updater_app(
  PRODUCT cmake
  PRODUCT_NAME "Mavericks CMake"
  VERSION "${PKG_VERSION}"
  LOG_PREFIX "MavCMakeUpdater"
  CONFIRM_TITLE "Mavericks CMake updated"
  CONFIRM_BODY "CMake for Mavericks in /usr/local/mavergreen/cmake was updated."
  ALLOW_GENERIC
)

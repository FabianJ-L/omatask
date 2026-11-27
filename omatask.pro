QT += core gui qml quick quickcontrols2 network

CONFIG += c++17 release qtquickcompiler
TARGET = omatask
TEMPLATE = app

HEADERS += \
    src/gpuclients.h \
    src/processmodel.h \
    src/procparse.h \
    src/services.h \
    src/sysmonitor.h \
    src/theme.h \
    src/translator.h

SOURCES += \
    src/main.cpp \
    src/gpuclients.cpp \
    src/processmodel.cpp \
    src/procparse.cpp \
    src/services.cpp \
    src/sysmonitor.cpp \
    src/theme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc

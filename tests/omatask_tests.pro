QT += core gui quick testlib network
CONFIG += c++17 testcase qtquickcompiler
TARGET = omatask_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += ../src/gpuclients.h ../src/processmodel.h ../src/procparse.h ../src/services.h ../src/sysmonitor.h \
           ../src/theme.h ../src/translator.h
SOURCES += omatask_tests.cpp ../src/gpuclients.cpp ../src/processmodel.cpp ../src/procparse.cpp ../src/services.cpp \
           ../src/sysmonitor.cpp ../src/theme.cpp ../src/translator.cpp
RESOURCES += ../src/resources.qrc

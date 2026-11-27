// OmaTask — a task manager for Omarchy: see what uses the CPU, memory, GPUs,
// disks, network and battery, end what misbehaves, and decide what starts
// with the session.

#include <QCommandLineParser>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

#include "processmodel.h"
#include "services.h"
#include "sysmonitor.h"
#include "theme.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("omatask");
    app.setApplicationDisplayName("OmaTask");
    app.setApplicationVersion("0.1.0");

    // Matches the window to omatask.desktop, so the compositor (Wayland
    // app_id) and the launcher pick up the installed icon.
    app.setDesktopFileName("omatask");
    app.setWindowIcon(QIcon::fromTheme("omatask"));

    QQuickStyle::setStyle("Material");

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    QCommandLineParser parser;
    parser.setApplicationDescription(QCoreApplication::translate("main", "A task manager for Omarchy."));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.process(app);

    Theme theme;
    SysMonitor monitor;
    ProcessModel processes(&monitor);
    processes.refresh();
    Services services;

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    QObject::connect(&translator, &Translator::changed, &monitor, &SysMonitor::sampleNow);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("monitor", &monitor);
    engine.rootContext()->setContextProperty("processes", &processes);
    engine.rootContext()->setContextProperty("services", &services);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}

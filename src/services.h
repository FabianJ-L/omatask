#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <functional>

// systemd services (user or system) and everything that starts with the
// session: Hyprland's exec-once lines, XDG autostart entries and enabled
// user units. Only units can be switched on and off here; the others live in
// config files OmaTask never edits, so they are shown with where they come from.
class Services : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool system READ system WRITE setSystem NOTIFY changed)
    Q_PROPERTY(QVariantList units READ units NOTIFY changed)
    Q_PROPERTY(QVariantList startup READ startup NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY changed)

public:
    explicit Services(const QString &homeDir = {}, QObject *parent = nullptr);

    bool system() const { return m_system; }
    void setSystem(bool system);
    QVariantList units() const;
    QVariantList startup() const { return m_startup; }
    bool busy() const { return m_running > 0; }
    QString error() const { return m_error; }
    QString filter() const { return m_filter; }
    void setFilter(const QString &filter);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void refreshStartup();
    // start, stop, restart, enable, disable
    Q_INVOKABLE void act(const QString &unit, const QString &verb, bool system);
    Q_INVOKABLE void clearError();

    // Merges list-units with list-unit-files, exposed for tests.
    static QVariantList merge(const QList<QVariantMap> &units, const QList<QVariantMap> &files);
    static QVariantList hyprAutostart(const QString &homeDir, const QString &omarchyPath);

signals:
    void changed();

private:
    void run(const QStringList &args, std::function<void(const QByteArray &)> done);
    void setError(const QString &error);

    QString m_home;
    bool m_system = false;
    QVariantList m_units, m_startup;
    QList<QVariantMap> m_rawUnits, m_rawFiles;
    int m_running = 0;
    QString m_error;
    QString m_filter;
};

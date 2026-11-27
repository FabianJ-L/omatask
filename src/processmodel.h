#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QSet>

#include "procparse.h"

class SysMonitor;

// The process list, grouped like Windows' Task Manager: apps first, then
// background processes, then other users' (system) processes. Each app
// gathers the processes it started under one expandable row. The rows are a
// flat list (sections, groups, children) so a plain ListView can show them,
// and updates move rows rather than resetting, so selection and scrolling
// survive every refresh.
class ProcessModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(QString sortColumn READ sortColumn WRITE setSortColumn NOTIFY viewChanged)
    Q_PROPERTY(bool descending READ descending WRITE setDescending NOTIFY viewChanged)
    Q_PROPERTY(bool grouped READ grouped WRITE setGrouped NOTIFY viewChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY viewChanged)
    Q_PROPERTY(int processCount READ processCount NOTIFY refreshed)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    enum Kind { Section = 0, Group, Process };
    enum Role {
        KindRole = Qt::UserRole + 1, KeyRole, NameRole, CommandRole, PidRole, CpuRole, CpuTextRole, MemRole,
        MemTextRole, DiskRole, DiskTextRole, GpuRole, GpuTextRole, StatusRole, UserRole, DepthRole,
        ExpandableRole, ExpandedRole, CountRole, SectionRole
    };

    struct Proc {
        int pid = 0, ppid = 0;
        uint uid = 0;
        QString comm, name, cmd, user, exe;
        QChar state;
        int nice = 0, threads = 0;
        quint64 ticks = 0, startTicks = 0, mem = 0, ioBytes = 0;
        double cpu = 0, disk = 0, gpu = 0;
        bool kernel = false;
    };

    explicit ProcessModel(SysMonitor *monitor, const QString &procRoot = "/proc", QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString sortColumn() const { return m_sortColumn; }
    void setSortColumn(const QString &column);
    bool descending() const { return m_descending; }
    void setDescending(bool descending);
    bool grouped() const { return m_grouped; }
    void setGrouped(bool grouped);
    QString filter() const { return m_filter; }
    void setFilter(const QString &filter);
    int processCount() const { return int(m_procs.size()); }
    QString error() const { return m_error; }

    Q_INVOKABLE void toggle(const QString &key);
    Q_INVOKABLE int rowOf(const QString &key) const;
    Q_INVOKABLE QVariantMap details(const QString &key) const;
    // Signals every process the row stands for: a group ends the whole app.
    Q_INVOKABLE bool endTask(const QString &key, bool force);
    Q_INVOKABLE bool suspend(const QString &key, bool stop);
    Q_INVOKABLE bool setPriority(const QString &key, int nice);
    Q_INVOKABLE void clearError();
    Q_INVOKABLE void refresh();

    // Exposed for tests: the app a process belongs to and which section.
    static int groupRoot(int pid, const QHash<int, Proc> &procs);
    static bool isSessionRoot(const Proc &p);

signals:
    void viewChanged();
    void refreshed();
    void errorChanged();

private:
    struct Row {
        Kind kind = Process;
        QString key;
        QString name, cmd, status, user;
        int pid = 0, depth = 0, count = 1, section = 0;
        double cpu = 0, disk = 0, gpu = 0;
        quint64 mem = 0;
        bool expandable = false, expanded = false;
    };

    void scan();
    void rebuild();
    QList<int> pidsFor(const QString &key) const;
    void setError(const QString &error);
    QString appName(const Proc &p) const;
    void loadDesktopEntries();
    bool lessThan(const Row &a, const Row &b) const;

    SysMonitor *m_monitor;
    QString m_root;
    QHash<int, Proc> m_procs;
    QList<Row> m_rows;
    QSet<QString> m_expanded;
    QHash<QString, QString> m_desktopNames;   // lowercase exec/wmclass -> Name
    QHash<uint, QString> m_users;
    QString m_sortColumn = "name";
    bool m_descending = false;
    bool m_grouped = true;
    QString m_filter;
    QString m_error;
    uint m_myUid;
    long m_clockTicks;
};

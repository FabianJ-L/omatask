#include "processmodel.h"

#include "sysmonitor.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QProcess>
#include <functional>
#include <QStandardPaths>
#include <cerrno>
#include <csignal>
#include <pwd.h>
#include <sys/resource.h>
#include <unistd.h>

static QString readText(const QString &path) {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

ProcessModel::ProcessModel(SysMonitor *monitor, const QString &procRoot, QObject *parent)
    : QAbstractListModel(parent), m_monitor(monitor), m_root(procRoot), m_myUid(getuid()),
      m_clockTicks(sysconf(_SC_CLK_TCK)) {
    loadDesktopEntries();
    if (m_monitor)
        connect(m_monitor, &SysMonitor::sampled, this, [this] {
            if (m_monitor->activePage() == SysMonitor::ProcessesPage)
                refresh();
        });
}

void ProcessModel::refresh() {
    scan();
    rebuild();
    emit refreshed();
}

// Maps what a process is called to the name its .desktop file gives the app,
// so a group reads "Chromium" or "Ghostty" rather than a binary name.
void ProcessModel::loadDesktopEntries() {
    const QString language = QLocale().name().section('_', 0, 0);
    QStringList dirs = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    dirs << "/var/lib/flatpak/exports/share/applications";
    for (const auto &dir : dirs) {
        for (const auto &file : QDir(dir).entryInfoList({"*.desktop"}, QDir::Files)) {
            const QString text = readText(file.filePath());
            QString name, localized, exec, wmClass;
            bool inEntry = false, hidden = false;
            for (const auto &line : text.split('\n')) {
                if (line.startsWith('[')) {
                    inEntry = line.trimmed() == "[Desktop Entry]";
                    continue;
                }
                if (!inEntry)
                    continue;
                if (line.startsWith("Name="))
                    name = line.mid(5).trimmed();
                else if (line.startsWith("Name[" + language + "]="))
                    localized = line.section('=', 1).trimmed();
                else if (line.startsWith("Exec="))
                    exec = line.mid(5).trimmed();
                else if (line.startsWith("StartupWMClass="))
                    wmClass = line.mid(15).trimmed().toLower();
                else if (line.startsWith("Hidden=true"))
                    hidden = true;
            }
            if (hidden || name.isEmpty())
                continue;
            const QString display = localized.isEmpty() ? name : localized;
            // Skip wrappers like env, uwsm-app and flatpak run to reach the program.
            QStringList tokens = exec.split(' ', Qt::SkipEmptyParts);
            static const QSet<QString> wrappers{"env", "uwsm", "uwsm-app", "app", "--", "flatpak", "run", "sh", "-c", "bash"};
            QString program;
            for (const auto &token : tokens) {
                const QString base = QFileInfo(token).fileName();
                if (wrappers.contains(base) || token.startsWith('-') || token.contains('='))
                    continue;
                program = base.toLower();
                break;
            }
            for (const auto &key : {program, wmClass, file.completeBaseName().toLower()})
                if (!key.isEmpty() && !m_desktopNames.contains(key))
                    m_desktopNames.insert(key, display);
        }
    }
}

QString ProcessModel::appName(const Proc &p) const {
    // comm is cut to 15 characters, so the executable and arguments help too.
    const QStringList args = p.cmd.split(' ', Qt::SkipEmptyParts);
    QStringList candidates{p.comm.toLower(), QFileInfo(p.exe).fileName().toLower()};
    for (int i = 0; i < qMin(3, int(args.size())); ++i) {
        const QString base = QFileInfo(args[i]).fileName().toLower();
        candidates << base << QFileInfo(base).completeBaseName();
    }
    for (const auto &c : candidates)
        if (!c.isEmpty() && m_desktopNames.contains(c))
            return m_desktopNames.value(c);
    return {};
}

bool ProcessModel::isSessionRoot(const Proc &p) {
    static const QSet<QString> roots{"systemd", "Hyprland", "hyprland", "uwsm", "start-hyprland", "sddm",
                                     "sddm-helper", "login", "greetd", "agetty", "init", "kthreadd", "elephant",
                                     "walker", "dbus-daemon", "dbus-broker"};
    return p.pid == 1 || roots.contains(p.comm);
}

int ProcessModel::groupRoot(int pid, const QHash<int, Proc> &procs) {
    int current = pid;
    for (int guard = 0; guard < 64; ++guard) {
        const auto it = procs.constFind(current);
        if (it == procs.cend() || isSessionRoot(*it))
            return current;
        const auto parent = procs.constFind(it->ppid);
        // An app ends where its parent is the session itself, or belongs to
        // someone else (a root daemon that started a user helper, say).
        if (parent == procs.cend() || isSessionRoot(*parent) || parent->uid != it->uid)
            return current;
        current = it->ppid;
    }
    return current;
}

void ProcessModel::scan() {
    QHash<int, Proc> procs;
    const double dt = m_monitor ? m_monitor->lastIntervalSeconds() : 1.0;
    const int cores = m_monitor ? m_monitor->coreCount() : 1;
    const auto gpu = m_monitor ? m_monitor->gpuClients().usage() : QHash<int, GpuClients::Usage>();

    for (const auto &entry : QDir(m_root).entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        bool ok = false;
        const int pid = entry.toInt(&ok);
        if (!ok)
            continue;
        const QString dir = m_root + '/' + entry;
        ProcParse::PidStat st;
        if (!ProcParse::pidStat(readText(dir + "/stat"), &st))
            continue;
        Proc p;
        const auto old = m_procs.constFind(pid);
        // A reused pid is a new process: compare start times.
        const bool known = old != m_procs.cend() && old->startTicks == st.startTicks;
        p.pid = pid;
        p.ppid = st.ppid;
        p.comm = st.comm;
        p.state = st.state;
        p.nice = st.nice;
        p.threads = st.threads;
        p.ticks = st.ticks;
        p.startTicks = st.startTicks;
        p.kernel = pid == 2 || st.ppid == 2;
        const auto status = ProcParse::pidStatus(readText(dir + "/status"));
        p.uid = status.uid;
        p.mem = status.rssAnon ? status.rssAnon : status.rss;
        const auto io = ProcParse::pidIo(readText(dir + "/io"));
        p.ioBytes = io.readBytes + io.writeBytes;
        if (known) {
            p.cmd = old->cmd;
            p.exe = old->exe;
            p.name = old->name;
            p.cpu = qBound(0.0, double(p.ticks - qMin(p.ticks, old->ticks)) / (dt * m_clockTicks * cores) * 100.0, 100.0);
            p.disk = double(p.ioBytes - qMin(p.ioBytes, old->ioBytes)) / dt;
        } else {
            QFile f(dir + "/cmdline");
            if (f.open(QIODevice::ReadOnly))
                p.cmd = ProcParse::cmdline(f.readAll());
            p.exe = QFile::symLinkTarget(dir + "/exe");
            // The kernel cuts comm to 15 characters; the full name is usually
            // argv[0], or the script a shell runs ("bash /usr/bin/omarchy-…").
            p.name = p.comm;
            const QStringList args = p.cmd.split(' ', Qt::SkipEmptyParts);
            for (int i = 0; i < qMin(3, int(args.size())); ++i) {
                const QString base = QFileInfo(args[i]).fileName();
                if (base.size() > p.comm.size() && base.startsWith(p.comm)) {
                    p.name = base;
                    break;
                }
            }
            if (p.kernel)
                p.name = p.comm;
        }
        if (gpu.contains(pid))
            p.gpu = gpu.value(pid).percent;
        if (!m_users.contains(p.uid)) {
            const passwd *pw = getpwuid(p.uid);
            m_users.insert(p.uid, pw ? QString::fromLocal8Bit(pw->pw_name) : QString::number(p.uid));
        }
        p.user = m_users.value(p.uid);
        procs.insert(pid, p);
    }
    m_procs = procs;
}

static QString statusText(QChar state) {
    switch (state.toLatin1()) {
    case 'R': return ProcessModel::tr("Running");
    case 'S': return ProcessModel::tr("Sleeping");
    case 'I': return ProcessModel::tr("Idle");
    case 'D': return ProcessModel::tr("Waiting for disk");
    case 'Z': return ProcessModel::tr("Zombie");
    case 'T': case 't': return ProcessModel::tr("Suspended");
    default: return QString(state);
    }
}

bool ProcessModel::lessThan(const Row &a, const Row &b) const {
    auto cmp = [&](auto x, auto y) { return m_descending ? y < x : x < y; };
    if (m_sortColumn == "cpu" && a.cpu != b.cpu) return cmp(a.cpu, b.cpu);
    if (m_sortColumn == "mem" && a.mem != b.mem) return cmp(a.mem, b.mem);
    if (m_sortColumn == "disk" && a.disk != b.disk) return cmp(a.disk, b.disk);
    if (m_sortColumn == "gpu" && a.gpu != b.gpu) return cmp(a.gpu, b.gpu);
    if (m_sortColumn == "pid" && a.pid != b.pid) return cmp(a.pid, b.pid);
    if (m_sortColumn == "user" && a.user != b.user) return cmp(a.user, b.user);
    const int byName = QString::compare(a.name, b.name, Qt::CaseInsensitive);
    if (byName != 0)
        return m_sortColumn == "name" ? cmp(byName, 0) : byName < 0;
    return a.pid < b.pid;
}

void ProcessModel::rebuild() {
    QList<Row> rows;
    auto processRow = [&](const Proc &p, int depth) {
        Row r;
        r.kind = Process;
        r.key = "p:" + QString::number(p.pid);
        r.name = p.name;
        r.cmd = p.cmd.isEmpty() ? '[' + p.comm + ']' : p.cmd;
        r.pid = p.pid;
        r.cpu = p.cpu;
        r.mem = p.mem;
        r.disk = p.disk;
        r.gpu = p.gpu;
        r.user = p.user;
        r.status = statusText(p.state);
        r.depth = depth;
        return r;
    };

    const QString filter = m_filter.trimmed();
    if (!m_grouped || !filter.isEmpty()) {
        for (const auto &p : std::as_const(m_procs)) {
            if (!filter.isEmpty() && !p.name.contains(filter, Qt::CaseInsensitive) &&
                !p.cmd.contains(filter, Qt::CaseInsensitive) && QString::number(p.pid) != filter &&
                p.user.compare(filter, Qt::CaseInsensitive) != 0)
                continue;
            rows.append(processRow(p, 0));
        }
        std::sort(rows.begin(), rows.end(), [this](const Row &a, const Row &b) { return lessThan(a, b); });
    } else {
        // Group every process under the app that started it.
        QHash<int, QList<int>> groups;
        QList<int> kernel;
        for (const auto &p : std::as_const(m_procs)) {
            if (p.kernel)
                kernel.append(p.pid);
            else
                groups[groupRoot(p.pid, m_procs)].append(p.pid);
        }
        QList<Row> sections[3];
        auto makeGroup = [&](const QString &key, const QString &name, const QList<int> &members, int section) {
            Row g;
            g.kind = Group;
            g.key = key;
            g.name = name;
            g.section = section;
            g.count = int(members.size());
            g.expandable = members.size() > 1;
            g.expanded = g.expandable && m_expanded.contains(key);
            bool allStopped = true;
            for (int pid : members) {
                const auto &p = m_procs[pid];
                g.cpu += p.cpu;
                g.mem += p.mem;
                g.disk += p.disk;
                g.gpu += p.gpu;
                allStopped = allStopped && (p.state == 'T' || p.state == 't');
            }
            g.cpu = qMin(g.cpu, 100.0);
            g.gpu = qMin(g.gpu, 100.0);
            return std::make_pair(g, allStopped);
        };
        for (auto it = groups.cbegin(); it != groups.cend(); ++it) {
            const auto &root = m_procs[it.key()];
            const QString app = appName(root);
            const int section = root.uid != m_myUid ? 2 : app.isEmpty() ? 1 : 0;
            auto [g, stopped] = makeGroup("g:" + QString::number(root.pid), app.isEmpty() ? root.name : app, it.value(), section);
            g.pid = root.pid;
            g.user = root.user;
            g.cmd = root.cmd;
            g.status = stopped ? tr("Suspended") : QString();
            if (!g.expandable)
                g.status = statusText(root.state);
            sections[section].append(g);
        }
        if (!kernel.isEmpty()) {
            auto [g, stopped] = makeGroup("g:kernel", tr("Linux kernel threads"), kernel, 2);
            Q_UNUSED(stopped);
            g.user = "root";
            g.pid = 2;
            sections[2].append(g);
        }
        const QString titles[3] = {tr("Apps"), tr("Background processes"), tr("System processes")};
        for (int s = 0; s < 3; ++s) {
            if (sections[s].isEmpty())
                continue;
            auto &list = sections[s];
            std::sort(list.begin(), list.end(), [this](const Row &a, const Row &b) { return lessThan(a, b); });
            Row header;
            header.kind = Section;
            header.key = "s:" + QString::number(s);
            header.name = titles[s];
            header.count = int(list.size());
            header.section = s;
            rows.append(header);
            for (const auto &g : list) {
                rows.append(g);
                if (!g.expanded)
                    continue;
                QList<Row> children;
                const QList<int> members = g.key == "g:kernel" ? kernel : groups.value(g.pid);
                for (int pid : members)
                    children.append(processRow(m_procs[pid], 1));
                std::sort(children.begin(), children.end(), [this](const Row &a, const Row &b) { return lessThan(a, b); });
                rows.append(children);
            }
        }
    }

    // Bring the old rows to the new order with removes, moves and inserts,
    // so the view keeps its selection and scroll position.
    QHash<QString, int> wanted;
    for (int i = 0; i < rows.size(); ++i)
        wanted.insert(rows[i].key, i);
    for (int i = int(m_rows.size()) - 1; i >= 0; --i) {
        if (wanted.contains(m_rows[i].key))
            continue;
        int first = i;
        while (first > 0 && !wanted.contains(m_rows[first - 1].key))
            --first;
        beginRemoveRows({}, first, i);
        m_rows.remove(first, i - first + 1);
        endRemoveRows();
        i = first;
    }
    // What remains is a subset of the new rows; order it like them.
    QSet<QString> present;
    for (const auto &r : std::as_const(m_rows))
        present.insert(r.key);
    QList<QString> order;
    for (const auto &r : rows)
        if (present.contains(r.key))
            order.append(r.key);
    for (int i = 0; i < order.size(); ++i) {
        if (m_rows[i].key == order[i])
            continue;
        int from = i + 1;
        while (from < m_rows.size() && m_rows[from].key != order[i])
            ++from;
        beginMoveRows({}, from, from, {}, i);
        m_rows.move(from, i);
        endMoveRows();
    }
    for (int i = 0; i < rows.size(); ++i) {
        if (i < m_rows.size() && m_rows[i].key == rows[i].key) {
            m_rows[i] = rows[i];
            continue;
        }
        beginInsertRows({}, i, i);
        m_rows.insert(i, rows[i]);
        endInsertRows();
    }
    if (!m_rows.isEmpty())
        emit dataChanged(index(0), index(int(m_rows.size()) - 1));
}

int ProcessModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant ProcessModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const Row &r = m_rows[index.row()];
    const QLocale locale;
    switch (role) {
    case KindRole: return r.kind;
    case KeyRole: return r.key;
    case NameRole: return r.name;
    case CommandRole: return r.cmd;
    case PidRole: return r.pid;
    case CpuRole: return r.cpu;
    case CpuTextRole: return r.kind == Section ? QString() : locale.toString(r.cpu, 'f', 1) + " %";
    case MemRole: return double(r.mem);
    case MemTextRole: return r.kind == Section ? QString() : ProcParse::bytes(r.mem);
    case DiskRole: return r.disk;
    case DiskTextRole: return r.kind == Section ? QString() : r.disk < 1 ? QString("0 B/s") : ProcParse::rate(r.disk);
    case GpuRole: return r.gpu;
    case GpuTextRole: return r.kind == Section ? QString() : locale.toString(r.gpu, 'f', 0) + " %";
    case StatusRole: return r.status;
    case UserRole: return r.user;
    case DepthRole: return r.depth;
    case ExpandableRole: return r.expandable;
    case ExpandedRole: return r.expanded;
    case CountRole: return r.count;
    case SectionRole: return r.section;
    }
    return {};
}

QHash<int, QByteArray> ProcessModel::roleNames() const {
    return {{KindRole, "kind"}, {KeyRole, "key"}, {NameRole, "name"}, {CommandRole, "command"}, {PidRole, "pid"},
            {CpuRole, "cpu"}, {CpuTextRole, "cpuText"}, {MemRole, "mem"}, {MemTextRole, "memText"},
            {DiskRole, "disk"}, {DiskTextRole, "diskText"}, {GpuRole, "gpu"}, {GpuTextRole, "gpuText"},
            {StatusRole, "status"}, {UserRole, "user"}, {DepthRole, "depth"}, {ExpandableRole, "expandable"},
            {ExpandedRole, "expanded"}, {CountRole, "count"}, {SectionRole, "section"}};
}

void ProcessModel::setSortColumn(const QString &column) {
    if (column == m_sortColumn)
        return;
    m_sortColumn = column;
    // Numbers read best biggest first, names alphabetically.
    m_descending = column != "name" && column != "pid" && column != "user";
    emit viewChanged();
    rebuild();
}

void ProcessModel::setDescending(bool descending) {
    if (descending == m_descending)
        return;
    m_descending = descending;
    emit viewChanged();
    rebuild();
}

void ProcessModel::setGrouped(bool grouped) {
    if (grouped == m_grouped)
        return;
    m_grouped = grouped;
    emit viewChanged();
    rebuild();
}

void ProcessModel::setFilter(const QString &filter) {
    if (filter == m_filter)
        return;
    m_filter = filter;
    emit viewChanged();
    rebuild();
}

void ProcessModel::toggle(const QString &key) {
    if (!key.startsWith("g:"))
        return;
    if (m_expanded.contains(key))
        m_expanded.remove(key);
    else
        m_expanded.insert(key);
    rebuild();
}

int ProcessModel::rowOf(const QString &key) const {
    for (int i = 0; i < m_rows.size(); ++i)
        if (m_rows[i].key == key)
            return i;
    return -1;
}

QList<int> ProcessModel::pidsFor(const QString &key) const {
    QList<int> pids;
    if (key.startsWith("p:"))
        pids.append(key.mid(2).toInt());
    else if (key.startsWith("g:") && key != "g:kernel") {
        const int root = key.mid(2).toInt();
        for (const auto &p : m_procs)
            if (!p.kernel && groupRoot(p.pid, m_procs) == root)
                pids.append(p.pid);
        // The app's own process last, so its children cannot be restarted by it.
        pids.removeAll(root);
        pids.append(root);
    }
    return pids;
}

QVariantMap ProcessModel::details(const QString &key) const {
    QVariantMap d;
    const int row = rowOf(key);
    if (row < 0 || m_rows[row].kind == Section)
        return d;
    const Row &r = m_rows[row];
    const int pid = r.pid;
    const auto p = m_procs.value(pid);
    const QLocale locale;
    d["name"] = r.name;
    d["pid"] = pid;
    d["isGroup"] = r.kind == Group && r.expandable;
    d["count"] = r.count;
    d["command"] = p.cmd.isEmpty() ? '[' + p.comm + ']' : p.cmd;
    d["exe"] = p.exe;
    d["user"] = p.user;
    d["threads"] = p.threads;
    d["nice"] = p.nice;
    d["ppid"] = p.ppid;
    d["suspended"] = p.state == 'T' || p.state == 't';
    d["kernel"] = p.kernel || key == "g:kernel";
    d["mine"] = p.uid == m_myUid;
    // Ending these logs the user out or takes the system down.
    d["critical"] = pid == 1 || pid == int(getpid()) || p.comm == "Hyprland" || p.comm == "systemd" ||
                    p.comm == "uwsm" || p.comm == "start-hyprland";
    const double boot = ProcParse::bootTime(readText(m_root + "/stat"));
    if (boot > 0 && m_clockTicks > 0) {
        const auto started = QDateTime::fromSecsSinceEpoch(qint64(boot + double(p.startTicks) / m_clockTicks));
        d["started"] = locale.toString(started, QLocale::ShortFormat);
    }
    return d;
}

void ProcessModel::setError(const QString &error) {
    if (error == m_error)
        return;
    m_error = error;
    emit errorChanged();
}

void ProcessModel::clearError() {
    setError({});
}

// Runs a privileged command through polkit, which asks for the password in
// Omarchy's own dialog, like Windows asks before touching admin processes.
static void runElevated(ProcessModel *model, const QStringList &args, const std::function<void(const QString &)> &fail) {
    const QString pkexec = QStandardPaths::findExecutable("pkexec");
    if (pkexec.isEmpty()) {
        fail(ProcessModel::tr("This process belongs to another user, and pkexec is not installed to ask for permission."));
        return;
    }
    auto *proc = new QProcess(model);
    QObject::connect(proc, &QProcess::finished, model, [proc, fail, model](int code, QProcess::ExitStatus) {
        // 126: the user dismissed the password dialog; 127: not authorized.
        if (code == 126 || code == 127)
            fail(ProcessModel::tr("Permission was not granted."));
        else if (code != 0)
            fail(QString::fromUtf8(proc->readAllStandardError()).trimmed());
        proc->deleteLater();
        QMetaObject::invokeMethod(model, "refresh", Qt::QueuedConnection);
    });
    proc->start(pkexec, args);
}

bool ProcessModel::endTask(const QString &key, bool force) {
    const auto pids = pidsFor(key);
    if (pids.isEmpty())
        return false;
    const int sig = force ? SIGKILL : SIGTERM;
    QStringList denied;
    for (int pid : pids) {
        if (pid == int(getpid()))
            continue;
        if (::kill(pid, sig) != 0 && errno == EPERM)
            denied << QString::number(pid);
    }
    if (!denied.isEmpty())
        runElevated(this, QStringList{"kill", force ? "-KILL" : "-TERM"} + denied,
                    [this](const QString &e) { setError(e); });
    QMetaObject::invokeMethod(this, "refresh", Qt::QueuedConnection);
    return denied.isEmpty();
}

bool ProcessModel::suspend(const QString &key, bool stop) {
    const auto pids = pidsFor(key);
    QStringList denied;
    for (int pid : pids)
        if (pid != int(getpid()) && ::kill(pid, stop ? SIGSTOP : SIGCONT) != 0 && errno == EPERM)
            denied << QString::number(pid);
    if (!denied.isEmpty())
        runElevated(this, QStringList{"kill", stop ? "-STOP" : "-CONT"} + denied, [this](const QString &e) { setError(e); });
    QMetaObject::invokeMethod(this, "refresh", Qt::QueuedConnection);
    return denied.isEmpty();
}

bool ProcessModel::setPriority(const QString &key, int nice) {
    const auto pids = pidsFor(key);
    QStringList denied;
    for (int pid : pids)
        if (setpriority(PRIO_PROCESS, id_t(pid), nice) != 0 && (errno == EACCES || errno == EPERM))
            denied << QString::number(pid);
    // Raising a priority (a lower nice value) always needs root on Linux.
    if (!denied.isEmpty())
        runElevated(this, QStringList{"renice", "-n", QString::number(nice), "-p"} + denied,
                    [this](const QString &e) { setError(e); });
    QMetaObject::invokeMethod(this, "refresh", Qt::QueuedConnection);
    return denied.isEmpty();
}

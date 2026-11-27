#include "gpuclients.h"

#include "procparse.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <time.h>
#include <unistd.h>

static qint64 monotonicNs() {
    timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return qint64(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
}

static QString readText(const QString &path) {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

GpuClients::GpuClients(const QString &procRoot) : m_root(procRoot) {}

void GpuClients::scan(bool full) {
    const qint64 now = monotonicNs();
    const qint64 elapsed = m_lastScanNs ? now - m_lastScanNs : 0;
    m_lastScanNs = now;
    const int self = int(getpid());

    if (full) {
        m_fds.clear();
        m_nvidiaPids.clear();
        const auto pids = QDir(m_root).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const auto &name : pids) {
            bool ok = false;
            const int pid = name.toInt(&ok);
            if (!ok || pid == self)
                continue;
            const QString fdDir = m_root + '/' + name + "/fd";
            QList<Fd> fds;
            bool nvidia = false;
            // Unreadable for other users' processes; those are simply skipped.
            for (const auto &fdName : QDir(fdDir).entryList(QDir::Files | QDir::System | QDir::NoDotAndDotDot)) {
                const QString target = QFile::symLinkTarget(fdDir + '/' + fdName);
                if (target.startsWith("/dev/dri/"))
                    fds.append({fdName.toInt(), true});
                else if (target.startsWith("/dev/nvidia") && target != "/dev/nvidia-uvm-tools")
                    nvidia = true;
            }
            if (!fds.isEmpty())
                m_fds.insert(pid, fds);
            if (nvidia)
                m_nvidiaPids.insert(pid);
        }
    }

    QHash<int, Usage> usage;
    QHash<QString, quint64> engine;
    QSet<QString> seen;
    int nvidiaUsers = 0;
    for (auto it = m_fds.begin(); it != m_fds.end();) {
        const int pid = it.key();
        if (!QFileInfo::exists(m_root + '/' + QString::number(pid))) {
            it = m_fds.erase(it);
            continue;
        }
        Usage u;
        for (const auto &fd : it.value()) {
            const auto client = ProcParse::drmFdinfo(readText(QString("%1/%2/fdinfo/%3").arg(m_root).arg(pid).arg(fd.fd)));
            if (!client.valid)
                continue;
            // Several descriptors, even in several processes, can share one
            // client; count each client once.
            const QString key = client.pdev + '/' + QString::number(client.clientId);
            if (seen.contains(key))
                continue;
            seen.insert(key);
            engine.insert(key, client.engineNs);
            const quint64 before = m_lastEngine.value(key, client.engineNs);
            if (elapsed > 0 && client.engineNs >= before)
                u.percent += double(client.engineNs - before) / double(elapsed) * 100.0;
            u.vram += client.vramBytes;
            if (u.pdev.isEmpty() || client.engineNs > 0)
                u.pdev = client.pdev;
        }
        u.percent = qBound(0.0, u.percent, 100.0);
        if (!u.pdev.isEmpty())
            usage.insert(pid, u);
        ++it;
    }
    for (int pid : std::as_const(m_nvidiaPids)) {
        const QString comm = readText(QString("%1/%2/comm").arg(m_root).arg(pid)).trimmed();
        // The compositor keeps the device open even while the card sleeps,
        // so it says nothing about whether an app needs the dGPU.
        static const QSet<QString> idleHolders{"nvidia-smi", "nvidia-persiste", "nvidia-powerd", "Hyprland",
                                               "Xwayland", "omatask"};
        if (!comm.isEmpty() && !idleHolders.contains(comm))
            ++nvidiaUsers;
    }
    m_nvidiaUsers = nvidiaUsers;
    m_lastEngine = engine;
    m_usage = usage;
}

QHash<QString, double> GpuClients::busyByDevice() const {
    QHash<QString, double> busy;
    for (const auto &u : m_usage)
        busy[u.pdev] = qMin(100.0, busy.value(u.pdev) + u.percent);
    return busy;
}

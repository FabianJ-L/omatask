#pragma once

#include <QHash>
#include <QSet>
#include <QString>

// Finds which processes use which GPU by reading the DRM fdinfo files the
// kernel keeps for every open render node. Unlike asking nvidia-smi, this
// never wakes a sleeping discrete GPU, so it is safe to run every second.
class GpuClients {
public:
    struct Usage {
        double percent = 0;
        quint64 vram = 0;
        QString pdev;
    };

    explicit GpuClients(const QString &procRoot = "/proc");

    // A full scan walks every process's file descriptors; a quick one only
    // rereads the processes already known to hold a GPU open.
    void scan(bool full);

    const QHash<int, Usage> &usage() const { return m_usage; }
    // Processes other than OmaTask and nvidia-smi holding an NVIDIA device
    // open. When there are none, the dGPU is idle and must be left asleep.
    bool nvidiaInUse() const { return m_nvidiaUsers > 0; }
    // Summed busy share per PCI device, from the fdinfo engine counters.
    QHash<QString, double> busyByDevice() const;

private:
    struct Fd {
        int fd;
        bool drm;
    };
    QString m_root;
    QHash<int, QList<Fd>> m_fds;
    QHash<QString, quint64> m_lastEngine;   // "pdev/client" -> ns
    qint64 m_lastScanNs = 0;
    QHash<int, Usage> m_usage;
    int m_nvidiaUsers = 0;
    QSet<int> m_nvidiaPids;
};

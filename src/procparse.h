#pragma once

#include <QHash>
#include <QList>
#include <QString>
#include <QStringList>
#include <QVariantMap>

// Pure parsers for the kernel's text interfaces and the tools OmaTask asks.
// They take the text rather than a path, so tests can feed them fixtures.
namespace ProcParse {

struct CpuTimes {
    quint64 busy = 0;
    quint64 total = 0;
};

// The first entry is the whole machine ("cpu"), then one per logical core.
QList<CpuTimes> cpuTimes(const QString &stat);
double usage(const CpuTimes &before, const CpuTimes &after);
quint64 bootTime(const QString &stat);

// Values in bytes, keyed like /proc/meminfo ("MemTotal", "MemAvailable").
QHash<QString, quint64> meminfo(const QString &text);

struct DiskCounters {
    quint64 readBytes = 0;
    quint64 writeBytes = 0;
    quint64 busyMs = 0;
};
// Whole disks only: partitions, loop, ram and zram devices are left out.
QHash<QString, DiskCounters> diskstats(const QString &text);
bool isWholeDisk(const QString &name);

struct NetCounters {
    quint64 rxBytes = 0;
    quint64 txBytes = 0;
};
// Physical-looking interfaces only: lo, docker, veth and bridges are left out.
QHash<QString, NetCounters> netdev(const QString &text);

struct PidStat {
    int pid = 0;
    int ppid = 0;
    QString comm;
    QChar state;
    quint64 ticks = 0;   // utime + stime
    quint64 startTicks = 0;
    int nice = 0;
    int threads = 0;
};
bool pidStat(const QByteArray &text, PidStat *out);

// The fields OmaTask reads from /proc/<pid>/status.
struct PidStatus {
    uint uid = 0;
    quint64 rssAnon = 0;   // bytes, the private memory Windows calls "working set (private)"
    quint64 rss = 0;
};
PidStatus pidStatus(const QByteArray &text);

struct PidIo {
    quint64 readBytes = 0;
    quint64 writeBytes = 0;
};
PidIo pidIo(const QByteArray &text);

// Reads a small /proc or /sys file with plain POSIX calls. The process list
// reads three of these per process every second, and QFile's overhead
// there costs more than the reading itself.
QByteArray readSmall(const char *path);

// One DRM client from /proc/<pid>/fdinfo/<fd>.
struct DrmClient {
    QString pdev;
    quint64 clientId = 0;
    quint64 engineNs = 0;   // the busiest engine's cumulative time
    quint64 vramBytes = 0;
    bool valid = false;
};
DrmClient drmFdinfo(const QString &text);

struct NvidiaGpu {
    QString name;
    double utilization = -1;
    double memoryUsedMiB = -1;
    double memoryTotalMiB = -1;
    double temperature = -1;
    double power = -1;
    bool valid = false;
};
// nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw
//            --format=csv,noheader,nounits
NvidiaGpu nvidiaSmi(const QString &csv);

// Battery values from a power_supply uevent file, normalized to watts and
// watt-hours whether the battery reports energy or charge.
struct Battery {
    QString name;
    QString status;
    QString model;
    double percent = -1;
    double powerW = -1;
    double energyNowWh = -1;
    double energyFullWh = -1;
    double energyDesignWh = -1;
    int cycles = -1;
    bool valid = false;
};
Battery battery(const QString &uevent);

// The command a process was started with; arguments are NUL-separated.
QString cmdline(const QByteArray &raw);

// systemctl list-units / list-unit-files --output=json.
QList<QVariantMap> systemctlJson(const QByteArray &json);

// Every exec-once / exec line in a Hyprland config, with sourced files
// resolved by the caller (this sees one file's text at a time).
QStringList hyprExecOnce(const QString &text);
// Commands a Lua Hyprland config starts with the session:
// o.launch_on_start("x"), o.exec_on_start("x") and, in autostart files
// (includeExecCmd), hl.exec_cmd("x") or hl.exec_cmd(o.launch("x")).
QStringList hyprLuaStartup(const QString &text, bool includeExecCmd);
QStringList hyprSources(const QString &text, const QString &homeDir, const QString &baseDir);

// Human-readable sizes and rates in the current QLocale.
QString bytes(double value);
QString rate(double bytesPerSecond);

}

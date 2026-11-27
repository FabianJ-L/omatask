#include "procparse.h"

#include <QCoreApplication>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QRegularExpression>

namespace ProcParse {

QList<CpuTimes> cpuTimes(const QString &stat) {
    QList<CpuTimes> result;
    for (const auto &line : stat.split('\n')) {
        if (!line.startsWith("cpu"))
            continue;
        const auto parts = line.split(' ', Qt::SkipEmptyParts);
        if (parts.size() < 5)
            continue;
        // user nice system idle iowait irq softirq steal; guest time is
        // already counted in user, so it is left out to avoid counting twice.
        quint64 values[8] = {};
        for (int i = 0; i < 8 && i + 1 < parts.size(); ++i)
            values[i] = parts[i + 1].toULongLong();
        CpuTimes t;
        const quint64 idle = values[3] + values[4];
        for (quint64 v : values)
            t.total += v;
        t.busy = t.total - idle;
        result.append(t);
    }
    return result;
}

double usage(const CpuTimes &before, const CpuTimes &after) {
    if (after.total <= before.total)
        return 0;
    const double total = double(after.total - before.total);
    const double busy = after.busy >= before.busy ? double(after.busy - before.busy) : 0;
    return qBound(0.0, busy / total * 100.0, 100.0);
}

quint64 bootTime(const QString &stat) {
    static const QRegularExpression re("^btime\\s+(\\d+)", QRegularExpression::MultilineOption);
    return re.match(stat).captured(1).toULongLong();
}

QHash<QString, quint64> meminfo(const QString &text) {
    QHash<QString, quint64> values;
    for (const auto &line : text.split('\n')) {
        const int colon = line.indexOf(':');
        if (colon < 0)
            continue;
        const auto parts = line.mid(colon + 1).split(' ', Qt::SkipEmptyParts);
        if (parts.isEmpty())
            continue;
        quint64 v = parts[0].toULongLong();
        if (parts.size() > 1 && parts[1] == "kB")
            v *= 1024;
        values.insert(line.left(colon), v);
    }
    return values;
}

bool isWholeDisk(const QString &name) {
    static const QRegularExpression skip("^(loop|ram|zram|dm-|sr|fd|md)");
    static const QRegularExpression nvme("^nvme\\d+n\\d+$");
    static const QRegularExpression mmc("^mmcblk\\d+$");
    static const QRegularExpression sd("^(sd|vd|hd|xvd)[a-z]+$");
    if (skip.match(name).hasMatch())
        return false;
    return nvme.match(name).hasMatch() || mmc.match(name).hasMatch() || sd.match(name).hasMatch();
}

QHash<QString, DiskCounters> diskstats(const QString &text) {
    QHash<QString, DiskCounters> result;
    for (const auto &line : text.split('\n')) {
        const auto parts = line.split(' ', Qt::SkipEmptyParts);
        if (parts.size() < 14 || !isWholeDisk(parts[2]))
            continue;
        // Sectors are always 512 bytes in this interface, whatever the disk uses.
        DiskCounters c;
        c.readBytes = parts[5].toULongLong() * 512;
        c.writeBytes = parts[9].toULongLong() * 512;
        c.busyMs = parts[12].toULongLong();
        result.insert(parts[2], c);
    }
    return result;
}

QHash<QString, NetCounters> netdev(const QString &text) {
    QHash<QString, NetCounters> result;
    static const QRegularExpression skip("^(lo|docker|veth|br-|virbr|tun|tap|vnet|tailscale|wg)");
    for (const auto &line : text.split('\n')) {
        const int colon = line.indexOf(':');
        if (colon < 0)
            continue;
        const QString name = line.left(colon).trimmed();
        if (name.isEmpty() || skip.match(name).hasMatch())
            continue;
        const auto parts = line.mid(colon + 1).split(' ', Qt::SkipEmptyParts);
        if (parts.size() < 9)
            continue;
        result.insert(name, {parts[0].toULongLong(), parts[8].toULongLong()});
    }
    return result;
}

bool pidStat(const QString &text, PidStat *out) {
    // The name sits in parentheses and may itself contain spaces or ')'.
    const int open = text.indexOf('('), close = text.lastIndexOf(')');
    if (open < 0 || close < open)
        return false;
    out->pid = text.left(open).trimmed().toInt();
    out->comm = text.mid(open + 1, close - open - 1);
    const auto f = text.mid(close + 2).split(' ', Qt::SkipEmptyParts);
    // f[0] is field 3 (state) of proc_pid_stat(5).
    if (f.size() < 20)
        return false;
    out->state = f[0].isEmpty() ? QChar('?') : f[0][0];
    out->ppid = f[1].toInt();
    out->ticks = f[11].toULongLong() + f[12].toULongLong();
    out->nice = f[16].toInt();
    out->threads = f[17].toInt();
    out->startTicks = f[19].toULongLong();
    return true;
}

PidStatus pidStatus(const QString &text) {
    PidStatus s;
    for (const auto &line : text.split('\n')) {
        if (line.startsWith("Uid:"))
            s.uid = line.mid(4).split('\t', Qt::SkipEmptyParts).value(0).trimmed().toUInt();
        else if (line.startsWith("RssAnon:"))
            s.rssAnon = line.mid(8).trimmed().split(' ').value(0).toULongLong() * 1024;
        else if (line.startsWith("VmRSS:"))
            s.rss = line.mid(6).trimmed().split(' ').value(0).toULongLong() * 1024;
    }
    return s;
}

PidIo pidIo(const QString &text) {
    PidIo io;
    for (const auto &line : text.split('\n')) {
        if (line.startsWith("read_bytes:"))
            io.readBytes = line.mid(11).trimmed().toULongLong();
        else if (line.startsWith("write_bytes:"))
            io.writeBytes = line.mid(12).trimmed().toULongLong();
    }
    return io;
}

DrmClient drmFdinfo(const QString &text) {
    DrmClient c;
    for (const auto &line : text.split('\n')) {
        const int colon = line.indexOf(':');
        if (colon < 0)
            continue;
        const QString key = line.left(colon);
        const QString value = line.mid(colon + 1).trimmed();
        if (key == "drm-pdev")
            c.pdev = value;
        else if (key == "drm-client-id") {
            c.clientId = value.toULongLong();
            c.valid = true;
        } else if (key.startsWith("drm-engine-") && !key.startsWith("drm-engine-capacity"))
            c.engineNs = qMax(c.engineNs, value.split(' ').value(0).toULongLong());
        else if (key == "drm-memory-vram" || key == "drm-resident-vram") {
            const auto parts = value.split(' ', Qt::SkipEmptyParts);
            quint64 v = parts.value(0).toULongLong();
            const QString unit = parts.value(1);
            if (unit == "KiB") v *= 1024;
            else if (unit == "MiB") v *= 1024 * 1024;
            else if (unit == "GiB") v *= 1024ull * 1024 * 1024;
            c.vramBytes = qMax(c.vramBytes, v);
        }
    }
    return c;
}

NvidiaGpu nvidiaSmi(const QString &csv) {
    NvidiaGpu g;
    const QString line = csv.split('\n', Qt::SkipEmptyParts).value(0);
    const auto f = line.split(',');
    if (f.size() < 6)
        return g;
    auto num = [](const QString &s) {
        bool ok = false;
        const double v = s.trimmed().toDouble(&ok);
        return ok ? v : -1.0;
    };
    g.name = f[0].trimmed();
    g.utilization = num(f[1]);
    g.memoryUsedMiB = num(f[2]);
    g.memoryTotalMiB = num(f[3]);
    g.temperature = num(f[4]);
    g.power = num(f[5]);
    g.valid = !g.name.isEmpty();
    return g;
}

Battery battery(const QString &uevent) {
    QHash<QString, QString> v;
    for (const auto &line : uevent.split('\n')) {
        const int eq = line.indexOf('=');
        if (eq > 0)
            v.insert(line.left(eq).mid(QStringLiteral("POWER_SUPPLY_").size()), line.mid(eq + 1).trimmed());
    }
    Battery b;
    if (v.value("TYPE") != "Battery" || v.value("PRESENT", "1") == "0")
        return b;
    b.valid = true;
    b.name = v.value("NAME");
    b.status = v.value("STATUS");
    b.model = (v.value("MANUFACTURER") + ' ' + v.value("MODEL_NAME")).trimmed();
    b.percent = v.contains("CAPACITY") ? v.value("CAPACITY").toDouble() : -1;
    b.cycles = v.contains("CYCLE_COUNT") ? v.value("CYCLE_COUNT").toInt() : -1;
    const double voltage = v.value("VOLTAGE_NOW").toDouble() / 1e6;
    const double designVoltage = v.contains("VOLTAGE_MIN_DESIGN") ? v.value("VOLTAGE_MIN_DESIGN").toDouble() / 1e6 : voltage;
    // Batteries report either energy (µWh, µW) or charge (µAh, µA); charge
    // times voltage gives energy, so both end up in watts and watt-hours.
    if (v.contains("ENERGY_NOW")) {
        b.energyNowWh = v.value("ENERGY_NOW").toDouble() / 1e6;
        b.energyFullWh = v.value("ENERGY_FULL").toDouble() / 1e6;
        b.energyDesignWh = v.value("ENERGY_FULL_DESIGN").toDouble() / 1e6;
    } else if (v.contains("CHARGE_NOW")) {
        b.energyNowWh = v.value("CHARGE_NOW").toDouble() / 1e6 * designVoltage;
        b.energyFullWh = v.value("CHARGE_FULL").toDouble() / 1e6 * designVoltage;
        b.energyDesignWh = v.value("CHARGE_FULL_DESIGN").toDouble() / 1e6 * designVoltage;
    }
    if (v.contains("POWER_NOW"))
        b.powerW = v.value("POWER_NOW").toDouble() / 1e6;
    else if (v.contains("CURRENT_NOW"))
        b.powerW = v.value("CURRENT_NOW").toDouble() / 1e6 * voltage;
    return b;
}

QString cmdline(const QByteArray &raw) {
    QByteArray copy = raw;
    while (copy.endsWith('\0'))
        copy.chop(1);
    copy.replace('\0', ' ');
    return QString::fromUtf8(copy);
}

QList<QVariantMap> systemctlJson(const QByteArray &json) {
    QList<QVariantMap> result;
    for (const auto &value : QJsonDocument::fromJson(json).array())
        result.append(value.toObject().toVariantMap());
    return result;
}

static QString stripComment(const QString &line) {
    const int hash = line.indexOf('#');
    return (hash >= 0 ? line.left(hash) : line).trimmed();
}

QStringList hyprExecOnce(const QString &text) {
    QStringList commands;
    static const QRegularExpression re("^exec-once\\s*=\\s*(.+)$");
    for (const auto &raw : text.split('\n')) {
        const auto match = re.match(stripComment(raw));
        if (match.hasMatch())
            commands.append(match.captured(1).trimmed());
    }
    return commands;
}

QStringList hyprLuaStartup(const QString &text, bool includeExecCmd) {
    QStringList commands;
    static const QRegularExpression hooks(R"re(\bo\.(?:launch|exec)_on_start\(\s*(["'])(.*?)\1)re");
    static const QRegularExpression exec(R"re(\bhl\.exec_cmd\(\s*(?:o\.launch\(\s*)?(["'])(.*?)\1)re");
    for (const auto &raw : text.split('\n')) {
        const QString line = raw.trimmed();
        if (line.startsWith("--"))
            continue;
        auto match = hooks.match(line);
        if (!match.hasMatch() && includeExecCmd)
            match = exec.match(line);
        if (match.hasMatch())
            commands.append(match.captured(2));
    }
    return commands;
}

QStringList hyprSources(const QString &text, const QString &homeDir, const QString &baseDir) {
    QStringList files;
    static const QRegularExpression re("^source\\s*=\\s*(.+)$");
    for (const auto &raw : text.split('\n')) {
        const auto match = re.match(stripComment(raw));
        if (!match.hasMatch())
            continue;
        QString path = match.captured(1).trimmed();
        if (path.startsWith("~/"))
            path = homeDir + path.mid(1);
        else if (path.startsWith("$HOME/"))
            path = homeDir + path.mid(5);
        else if (!path.startsWith('/'))
            path = baseDir + '/' + path;
        files.append(QDir::cleanPath(path));
    }
    return files;
}

QString bytes(double value) {
    const QLocale locale;
    const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    int unit = 0;
    while (value >= 1000 && unit < 4) {
        value /= 1024;
        ++unit;
    }
    const int decimals = unit == 0 ? 0 : value < 10 ? 1 : 0;
    return locale.toString(value, 'f', decimals) + ' ' + units[unit];
}

QString rate(double bytesPerSecond) {
    return bytes(bytesPerSecond) + "/s";
}

}

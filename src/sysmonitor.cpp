#include "sysmonitor.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QLocale>
#include <QNetworkInterface>
#include <QSet>
#include <QStandardPaths>
#include <sys/statvfs.h>
#include <time.h>

using namespace ProcParse;

static qint64 nowNs() {
    timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return qint64(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
}

static QString percentText(double v) {
    return QLocale().toString(v, 'f', 0) + " %";
}

SysMonitor::SysMonitor(const QString &procRoot, const QString &sysRoot, QObject *parent)
    : QObject(parent), m_proc(procRoot), m_sys(sysRoot), m_gpu(procRoot) {
    // The model name and core count do not change while running.
    int cores = 0;
    QSet<QString> coreIds;
    QString physical;
    for (const auto &line : read(m_proc + "/cpuinfo").split('\n')) {
        if (m_cpuModel.isEmpty() && line.startsWith("model name"))
            m_cpuModel = line.section(':', 1).trimmed();
        else if (line.startsWith("physical id"))
            physical = line.section(':', 1).trimmed();
        else if (line.startsWith("core id"))
            coreIds.insert(physical + '/' + line.section(':', 1).trimmed());
        else if (line.startsWith("cpu cores") && !cores)
            cores = line.section(':', 1).trimmed().toInt();
    }
    m_physicalCores = coreIds.isEmpty() ? cores : int(coreIds.size());

    connect(&m_nvidiaSmi, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        if (code == 0 && status == QProcess::NormalExit) {
            m_nvidia = nvidiaSmi(QString::fromUtf8(m_nvidiaSmi.readAllStandardOutput()));
            m_nvidiaAt = nowNs();
        }
    });

    m_timer.setInterval(1000);
    connect(&m_timer, &QTimer::timeout, this, &SysMonitor::sample);
    m_timer.start();
    sample();
}

SysMonitor::~SysMonitor() {
    if (m_nvidiaSmi.state() != QProcess::NotRunning) {
        m_nvidiaSmi.kill();
        m_nvidiaSmi.waitForFinished(500);
    }
}

void SysMonitor::setInterval(int ms) {
    ms = qBound(250, ms, 10000);
    if (ms == m_timer.interval())
        return;
    m_timer.setInterval(ms);
    emit settingsChanged();
}

void SysMonitor::setPaused(bool paused) {
    if (paused == m_paused)
        return;
    m_paused = paused;
    if (paused)
        m_timer.stop();
    else {
        m_timer.start();
        sample();
    }
    emit settingsChanged();
}

void SysMonitor::setActivePage(int page) {
    if (page == m_activePage)
        return;
    m_activePage = page;
    emit settingsChanged();
    // Show fresh numbers right away instead of up to a second late.
    if (!m_paused)
        sample();
}

QString SysMonitor::read(const QString &path) const {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

QVariantList SysMonitor::stat(const QString &label, const QString &value) const {
    return {label, value};
}

void SysMonitor::push(const QString &key, double value) {
    auto &h = m_history[key];
    if (h.isEmpty())
        h.fill(value, HistoryLength);   // a flat start instead of a jump from zero
    h.append(value);
    while (h.size() > HistoryLength)
        h.removeFirst();
}

QVariantList SysMonitor::history(const QString &key) const {
    QVariantList list;
    for (double v : m_history.value(key))
        list.append(v);
    return list;
}

void SysMonitor::sample() {
    const qint64 now = nowNs();
    // The time that really passed, so a late timer does not inflate rates.
    m_lastDt = m_lastSampleNs ? qMax(0.05, double(now - m_lastSampleNs) / 1e9) : m_timer.interval() / 1000.0;
    m_lastSampleNs = now;

    // Per-process GPU use is needed every tick on the process list; elsewhere
    // a slow full scan is enough to know whether the dGPU has clients.
    // Per-process GPU use is only shown on the process list, so the cheap
    // reread of known GPU clients runs there; the full descriptor walk that
    // finds new clients (and tells whether the dGPU is in use) runs rarely.
    const bool processes = m_activePage == ProcessesPage;
    const bool full = m_tick % (processes ? 10 : 30) == 0;
    if (full || processes)
        m_gpu.scan(full);
    ++m_tick;

    QVariantList devices;
    sampleCpu(devices);
    sampleMemory(devices);
    sampleGpus(devices);
    sampleDisks(devices);
    sampleNetwork(devices);
    m_devices = devices;
    sampleBattery();
    // Some hwmon drivers (laptop fans through the EC, NVMe) take milliseconds
    // per read, and nothing outside the sensors page shows them.
    if (m_activePage == SensorsPage || m_sensors.isEmpty())
        sampleSensors();
    emit sampled();
}

void SysMonitor::sampleCpu(QVariantList &out) {
    const QString statText = read(m_proc + "/stat");
    const auto cpu = cpuTimes(statText);
    QVariantList cores;
    double total = 0;
    if (!cpu.isEmpty() && cpu.size() == m_lastCpu.size()) {
        total = usage(m_lastCpu[0], cpu[0]);
        for (int i = 1; i < cpu.size(); ++i)
            cores.append(usage(m_lastCpu[i], cpu[i]));
    } else {
        for (int i = 1; i < cpu.size(); ++i)
            cores.append(0.0);
    }
    m_lastCpu = cpu;
    m_cpuPercent = total;
    push("cpu", total);

    // Average current clock over all cores, in GHz.
    double freq = 0;
    int counted = 0;
    for (int i = 0; i < cpu.size() - 1; ++i) {
        const QString f = read(QString("%1/devices/system/cpu/cpu%2/cpufreq/scaling_cur_freq").arg(m_sys).arg(i)).trimmed();
        if (!f.isEmpty()) {
            freq += f.toDouble();
            ++counted;
        }
    }
    const QLocale locale;
    const double uptime = read(m_proc + "/uptime").split(' ').value(0).toDouble();
    const int days = int(uptime / 86400), hours = int(uptime / 3600) % 24, minutes = int(uptime / 60) % 60;
    const QString uptimeText = days > 0 ? tr("%1 d %2 h %3 min").arg(days).arg(hours).arg(minutes)
                                        : tr("%1 h %2 min").arg(hours).arg(minutes);
    const auto loadParts = read(m_proc + "/loadavg").split(' ');
    const QString threads = loadParts.value(3).section('/', 1);
    const QString load = loadParts.mid(0, 3).join("  ");

    QVariantList stats;
    stats << QVariant(stat(tr("Utilization"), percentText(total)));
    if (counted)
        stats << QVariant(stat(tr("Speed"), locale.toString(freq / counted / 1e6, 'f', 2) + " GHz"));
    stats << QVariant(stat(tr("Cores"), QString::number(m_physicalCores)));
    stats << QVariant(stat(tr("Logical processors"), QString::number(cores.size())));
    stats << QVariant(stat(tr("Threads"), threads));
    stats << QVariant(stat(tr("Load average"), load));
    stats << QVariant(stat(tr("Up time"), uptimeText));

    QVariantMap d;
    d["id"] = "cpu";
    d["kind"] = "cpu";
    d["title"] = tr("CPU");
    d["subtitle"] = m_cpuModel;
    d["value"] = total;
    d["valueText"] = counted ? percentText(total) + "  " + locale.toString(freq / counted / 1e6, 'f', 2) + " GHz"
                             : percentText(total);
    d["history"] = history("cpu");
    d["scale"] = 100;
    d["cores"] = cores;
    d["stats"] = stats;
    out.append(d);
}

void SysMonitor::sampleMemory(QVariantList &out) {
    const auto m = meminfo(read(m_proc + "/meminfo"));
    const double total = m.value("MemTotal"), available = m.value("MemAvailable");
    const double used = total - available;
    const double cached = double(m.value("Cached")) + m.value("Buffers") + m.value("SReclaimable") - m.value("Shmem");
    const double swapTotal = m.value("SwapTotal"), swapUsed = swapTotal - m.value("SwapFree");
    const double percent = total > 0 ? used / total * 100 : 0;
    m_memPercent = percent;
    push("mem", percent);

    QVariantList stats;
    stats << QVariant(stat(tr("In use"), bytes(used)));
    stats << QVariant(stat(tr("Available"), bytes(available)));
    stats << QVariant(stat(tr("Cached"), bytes(qMax(0.0, cached))));
    stats << QVariant(stat(tr("Shared"), bytes(m.value("Shmem"))));
    stats << QVariant(stat(tr("Committed"), bytes(m.value("Committed_AS")) + " / " + bytes(m.value("CommitLimit"))));
    if (swapTotal > 0)
        stats << QVariant(stat(tr("Swap"), bytes(swapUsed) + " / " + bytes(swapTotal)));

    QVariantMap d;
    d["id"] = "mem";
    d["kind"] = "memory";
    d["title"] = tr("Memory");
    d["subtitle"] = tr("%1 total").arg(bytes(total));
    d["value"] = percent;
    d["valueText"] = QString("%1 / %2 (%3)").arg(bytes(used), bytes(total), percentText(percent));
    d["history"] = history("mem");
    d["scale"] = 100;
    d["stats"] = stats;
    out.append(d);
}

void SysMonitor::pollNvidia(const QString &) {
    if (m_nvidiaSmi.state() != QProcess::NotRunning)
        return;
    const QString smi = QStandardPaths::findExecutable("nvidia-smi");
    if (smi.isEmpty())
        return;
    m_nvidiaSmi.start(smi, {"--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
                            "--format=csv,noheader,nounits"});
}

void SysMonitor::sampleGpus(QVariantList &out) {
    const QLocale locale;
    const auto busyByDevice = m_gpu.busyByDevice();
    double busiest = 0;
    QDir drm(m_sys + "/class/drm");
    int amdIndex = 0, nvidiaIndex = 0;
    for (const auto &card : drm.entryList({"card*"}, QDir::Dirs | QDir::System)) {
        if (card.contains('-'))
            continue;   // connectors like card1-eDP-1
        const QString dev = drm.filePath(card) + "/device";
        const QString vendor = read(dev + "/vendor").trimmed();
        const QString pdev = QFileInfo(QFileInfo(dev).symLinkTarget()).fileName();
        QVariantMap d;
        QVariantList stats;
        d["kind"] = "gpu";
        d["scale"] = 100;
        double value = 0;

        if (vendor == "0x1002" || vendor == "0x8086") {
            const bool amd = vendor == "0x1002";
            const QString key = "gpu-" + pdev;
            const QString busyText = read(dev + "/gpu_busy_percent").trimmed();
            value = busyText.isEmpty() ? busyByDevice.value(pdev) : busyText.toDouble();
            const double vramUsed = read(dev + "/mem_info_vram_used").toDouble();
            const double vramTotal = read(dev + "/mem_info_vram_total").toDouble();
            const double gttUsed = read(dev + "/mem_info_gtt_used").toDouble();
            const double gttTotal = read(dev + "/mem_info_gtt_total").toDouble();
            const bool integrated = vramTotal > 0 && vramTotal <= 4.0 * 1024 * 1024 * 1024 && gttTotal > vramTotal;
            d["id"] = key;
            d["title"] = tr("GPU %1").arg(amdIndex + nvidiaIndex);
            d["subtitle"] = amd ? (integrated ? tr("AMD Radeon Graphics (integrated)") : tr("AMD Radeon"))
                                : tr("Intel Graphics (integrated)");
            stats << QVariant(stat(tr("Utilization"), percentText(value)));
            if (vramTotal > 0)
                stats << QVariant(stat(integrated ? tr("Dedicated memory") : tr("Video memory"),
                                       bytes(vramUsed) + " / " + bytes(vramTotal)));
            if (gttTotal > 0)
                stats << QVariant(stat(tr("Shared memory"), bytes(gttUsed) + " / " + bytes(gttTotal)));
            // Temperature and power come from the card's own hwmon directory.
            for (const auto &hw : QDir(dev + "/hwmon").entryList({"hwmon*"}, QDir::Dirs)) {
                const QString h = dev + "/hwmon/" + hw;
                const QString temp = read(h + "/temp1_input").trimmed();
                if (!temp.isEmpty())
                    stats << QVariant(stat(tr("Temperature"), locale.toString(temp.toDouble() / 1000, 'f', 0) + " °C"));
                QString power = read(h + "/power1_average").trimmed();
                if (power.isEmpty())
                    power = read(h + "/power1_input").trimmed();
                if (!power.isEmpty())
                    stats << QVariant(stat(tr("Power"), locale.toString(power.toDouble() / 1e6, 'f', 1) + " W"));
            }
            stats << QVariant(stat(tr("PCI slot"), pdev));
            push(key, value);
            d["value"] = value;
            d["valueText"] = percentText(value);
            d["history"] = history(key);
            ++amdIndex;
        } else if (vendor == "0x10de") {
            const QString key = "gpu-" + pdev;
            const QString runtime = read(dev + "/power/runtime_status").trimmed();
            const bool asleep = runtime == "suspended";
            QString model;
            for (const auto &line : read(m_proc + "/driver/nvidia/gpus/" + pdev + "/information").split('\n'))
                if (line.startsWith("Model:"))
                    model = line.section(':', 1).trimmed();
            if (model.isEmpty())
                model = m_nvidia.valid ? m_nvidia.name : tr("NVIDIA GPU");
            d["id"] = key;
            d["title"] = tr("GPU %1").arg(amdIndex + nvidiaIndex);
            d["subtitle"] = model;
            if (asleep) {
                // Asking nvidia-smi would wake the card and cost battery for
                // nothing, so a sleeping dGPU is reported as such.
                m_nvidia = {};
                d["note"] = tr("Sleeping to save power. It wakes up when an app needs it.");
                d["valueText"] = tr("Sleeping");
                stats << QVariant(stat(tr("Status"), tr("Sleeping (D3cold)")));
            } else {
                // Polling only while other processes keep the card busy lets
                // it fall back asleep as soon as they are done.
                if (m_gpu.nvidiaInUse() && m_tick % 2 == 0)
                    pollNvidia(pdev);
                const bool fresh = m_nvidia.valid && nowNs() - m_nvidiaAt < 5'000'000'000LL;
                value = fresh && m_nvidia.utilization >= 0 ? m_nvidia.utilization : busyByDevice.value(pdev);
                d["valueText"] = percentText(value);
                stats << QVariant(stat(tr("Status"), tr("Active")));
                stats << QVariant(stat(tr("Utilization"), percentText(value)));
                if (fresh) {
                    if (m_nvidia.memoryTotalMiB > 0)
                        stats << QVariant(stat(tr("Video memory"), bytes(m_nvidia.memoryUsedMiB * 1048576) + " / " +
                                                                       bytes(m_nvidia.memoryTotalMiB * 1048576)));
                    if (m_nvidia.temperature >= 0)
                        stats << QVariant(stat(tr("Temperature"), locale.toString(m_nvidia.temperature, 'f', 0) + " °C"));
                    if (m_nvidia.power >= 0)
                        stats << QVariant(stat(tr("Power"), locale.toString(m_nvidia.power, 'f', 1) + " W"));
                } else if (!m_gpu.nvidiaInUse()) {
                    d["note"] = tr("Awake, but no app is using it. It will go back to sleep shortly.");
                }
            }
            stats << QVariant(stat(tr("PCI slot"), pdev));
            push(key, value);
            d["value"] = value;
            d["asleep"] = asleep;
            d["history"] = history(key);
            ++nvidiaIndex;
        } else {
            continue;
        }
        busiest = qMax(busiest, value);
        d["stats"] = stats;
        out.append(d);
    }
    m_gpuPercent = busiest;
}

// The mount points living on a whole disk, following device-mapper layers
// (LUKS, LVM) down to the partitions underneath.
static QHash<QString, QStringList> mountsByDisk(const QString &procRoot, const QString &sysRoot) {
    QHash<QString, QStringList> result;
    QFile f(procRoot + "/mounts");
    if (!f.open(QIODevice::ReadOnly))
        return result;
    QSet<QString> seenDevices;
    for (const auto &line : QString::fromUtf8(f.readAll()).split('\n')) {
        const auto parts = line.split(' ');
        if (parts.size() < 2 || !parts[0].startsWith("/dev/"))
            continue;
        const QString device = QFileInfo(parts[0]).canonicalFilePath();
        QString name = QFileInfo(device).fileName();
        QStringList stack{name};
        QSet<QString> disks;
        while (!stack.isEmpty()) {
            const QString n = stack.takeLast();
            const auto slaves = QDir(sysRoot + "/class/block/" + n + "/slaves").entryList(QDir::Dirs | QDir::System | QDir::NoDotAndDotDot);
            if (!slaves.isEmpty()) {
                stack << slaves;
                continue;
            }
            // A partition's sysfs directory sits inside its disk's.
            const QString real = QFileInfo(sysRoot + "/class/block/" + n).canonicalFilePath();
            if (QFileInfo::exists(real + "/partition"))
                disks.insert(QFileInfo(QFileInfo(real).absolutePath()).fileName());
            else
                disks.insert(n);
        }
        // Btrfs subvolumes mount the same device many times; list the first.
        if (seenDevices.contains(device))
            continue;
        seenDevices.insert(device);
        for (const auto &disk : disks)
            result[disk].append(QString(parts[1]).replace("\\040", " "));
    }
    return result;
}

void SysMonitor::sampleDisks(QVariantList &out) {
    const auto disks = diskstats(read(m_proc + "/diskstats"));
    const auto mounts = mountsByDisk(m_proc, m_sys);
    QStringList names = disks.keys();
    std::sort(names.begin(), names.end());
    double busiest = 0;
    int index = 0;
    for (const auto &name : names) {
        // Empty card readers and the like have no size.
        if (read(m_sys + "/class/block/" + name + "/size").trimmed().toULongLong() == 0)
            continue;
        const auto now = disks.value(name);
        const auto before = m_lastDisk.value(name, now);
        const double readRate = double(now.readBytes - qMin(now.readBytes, before.readBytes)) / m_lastDt;
        const double writeRate = double(now.writeBytes - qMin(now.writeBytes, before.writeBytes)) / m_lastDt;
        const double busy = qBound(0.0, double(now.busyMs - qMin(now.busyMs, before.busyMs)) / (m_lastDt * 10), 100.0);
        const QString key = "disk-" + name;
        push(key, busy);
        push(key + "-r", readRate);
        push(key + "-w", writeRate);
        busiest = qMax(busiest, busy);

        const QString model = read(m_sys + "/class/block/" + name + "/device/model").trimmed();
        const double capacity = read(m_sys + "/class/block/" + name + "/size").trimmed().toDouble() * 512;
        const bool rotational = read(m_sys + "/class/block/" + name + "/queue/rotational").trimmed() == "1";
        QString type = name.startsWith("nvme") ? "SSD (NVMe)" : rotational ? "HDD" : "SSD";

        QVariantList stats;
        stats << QVariant(stat(tr("Active time"), percentText(busy)));
        stats << QVariant(stat(tr("Read speed"), rate(readRate)));
        stats << QVariant(stat(tr("Write speed"), rate(writeRate)));
        stats << QVariant(stat(tr("Capacity"), bytes(capacity)));
        stats << QVariant(stat(tr("Type"), type));
        for (const auto &mount : mounts.value(name)) {
            struct statvfs vfs;
            if (statvfs(mount.toLocal8Bit().constData(), &vfs) == 0 && vfs.f_blocks > 0) {
                const double size = double(vfs.f_blocks) * vfs.f_frsize;
                const double free = double(vfs.f_bavail) * vfs.f_frsize;
                stats << QVariant(stat(mount, tr("%1 free of %2").arg(bytes(free), bytes(size))));
            }
        }

        QVariantMap d;
        d["id"] = key;
        d["kind"] = "disk";
        d["title"] = tr("Disk %1 (%2)").arg(index++).arg(name);
        d["subtitle"] = model.isEmpty() ? type : model;
        d["value"] = busy;
        d["valueText"] = percentText(busy);
        d["history"] = history(key);
        d["history2"] = QVariantList();
        d["scale"] = 100;
        d["stats"] = stats;
        out.append(d);
    }
    m_lastDisk = disks;
    m_diskPercent = busiest;
}

void SysMonitor::sampleNetwork(QVariantList &out) {
    const auto nets = netdev(read(m_proc + "/net/dev"));
    QStringList names = nets.keys();
    std::sort(names.begin(), names.end());
    for (const auto &name : names) {
        if (read(m_sys + "/class/net/" + name + "/operstate").trimmed() != "up")
            continue;
        const auto now = nets.value(name);
        const auto before = m_lastNet.value(name, now);
        const double rx = double(now.rxBytes - qMin(now.rxBytes, before.rxBytes)) / m_lastDt;
        const double tx = double(now.txBytes - qMin(now.txBytes, before.txBytes)) / m_lastDt;
        const QString key = "net-" + name;
        push(key + "-rx", rx);
        push(key + "-tx", tx);
        double peak = 64 * 1024;
        for (double v : m_history.value(key + "-rx")) peak = qMax(peak, v);
        for (double v : m_history.value(key + "-tx")) peak = qMax(peak, v);

        const bool wireless = QFileInfo::exists(m_sys + "/class/net/" + name + "/wireless");
        QVariantList stats;
        stats << QVariant(stat(tr("Receive"), rate(rx)));
        stats << QVariant(stat(tr("Send"), rate(tx)));
        stats << QVariant(stat(tr("Received in total"), bytes(now.rxBytes)));
        stats << QVariant(stat(tr("Sent in total"), bytes(now.txBytes)));
        const auto iface = QNetworkInterface::interfaceFromName(name);
        for (const auto &entry : iface.addressEntries()) {
            const auto ip = entry.ip();
            if (ip.isLinkLocal())
                continue;
            stats << QVariant(stat(ip.protocol() == QAbstractSocket::IPv4Protocol ? tr("IPv4 address") : tr("IPv6 address"),
                                   ip.toString()));
        }
        if (!iface.hardwareAddress().isEmpty())
            stats << QVariant(stat(tr("Hardware address"), iface.hardwareAddress()));
        const QString speed = read(m_sys + "/class/net/" + name + "/speed").trimmed();
        if (!speed.isEmpty() && speed.toInt() > 0)
            stats << QVariant(stat(tr("Link speed"), speed + " Mbit/s"));

        QVariantMap d;
        d["id"] = key;
        d["kind"] = "network";
        d["title"] = wireless ? tr("Wi-Fi") : tr("Ethernet");
        d["subtitle"] = name;
        d["value"] = rx + tx;
        d["valueText"] = tr("R: %1  S: %2").arg(rate(rx), rate(tx));
        d["history"] = history(key + "-rx");
        d["history2"] = history(key + "-tx");
        d["scale"] = peak;
        d["legend"] = tr("Receive");
        d["legend2"] = tr("Send");
        d["stats"] = stats;
        out.append(d);
    }
    m_lastNet = nets;
}

void SysMonitor::sampleBattery() {
    QVariantMap result;
    bool acOnline = false;
    QDir supplies(m_sys + "/class/power_supply");
    for (const auto &name : supplies.entryList(QDir::Dirs | QDir::System | QDir::NoDotAndDotDot)) {
        const QString uevent = read(supplies.filePath(name) + "/uevent");
        if (uevent.contains("POWER_SUPPLY_TYPE=Mains") && uevent.contains("POWER_SUPPLY_ONLINE=1"))
            acOnline = true;
        const auto b = ProcParse::battery(uevent);
        if (!b.valid || !result.isEmpty())
            continue;
        const QLocale locale;
        const bool charging = b.status == "Charging";
        const bool discharging = b.status == "Discharging";
        push("battery", b.percent);
        push("battery-power", qMax(0.0, b.powerW));

        double hours = -1;
        if (b.powerW > 0.1 && discharging && b.energyNowWh > 0)
            hours = b.energyNowWh / b.powerW;
        else if (b.powerW > 0.1 && charging && b.energyFullWh > b.energyNowWh)
            hours = (b.energyFullWh - b.energyNowWh) / b.powerW;
        QString remainingText;
        if (hours >= 0) {
            const int minutes = int(hours * 60);
            remainingText = tr("%1 h %2 min").arg(minutes / 60).arg(minutes % 60);
        }

        QString statusText = b.status;
        if (charging) statusText = tr("Charging");
        else if (discharging) statusText = tr("On battery");
        else if (b.status == "Full") statusText = tr("Fully charged");
        else if (b.status == "Not charging") statusText = tr("Plugged in, not charging");

        QVariantList stats;
        stats << QVariant(stat(tr("Status"), statusText));
        if (b.powerW >= 0)
            stats << QVariant(stat(charging ? tr("Charging power") : tr("Power draw"), locale.toString(b.powerW, 'f', 1) + " W"));
        if (!remainingText.isEmpty())
            stats << QVariant(stat(charging ? tr("Full in") : tr("Time left"), remainingText));
        if (b.energyNowWh >= 0 && b.energyFullWh > 0)
            stats << QVariant(stat(tr("Energy"), locale.toString(b.energyNowWh, 'f', 1) + " / " +
                                                     locale.toString(b.energyFullWh, 'f', 1) + " Wh"));
        if (b.energyDesignWh > 0 && b.energyFullWh > 0)
            stats << QVariant(stat(tr("Health"), percentText(b.energyFullWh / b.energyDesignWh * 100) + "  (" +
                                                     tr("design: %1 Wh").arg(locale.toString(b.energyDesignWh, 'f', 1)) + ")"));
        if (b.cycles > 0)
            stats << QVariant(stat(tr("Charge cycles"), QString::number(b.cycles)));
        if (!b.model.isEmpty())
            stats << QVariant(stat(tr("Model"), b.model));

        result["present"] = true;
        result["percent"] = b.percent;
        result["charging"] = charging;
        result["statusText"] = statusText;
        result["remainingText"] = remainingText;
        result["powerW"] = b.powerW;
        result["history"] = history("battery");
        result["powerHistory"] = history("battery-power");
        result["stats"] = stats;
    }
    if (result.isEmpty())
        result["present"] = false;
    result["acOnline"] = acOnline;
    m_battery = result;
}

void SysMonitor::sampleSensors() {
    QVariantList sensors;
    const QLocale locale;
    QDir hwmon(m_sys + "/class/hwmon");
    QStringList names = hwmon.entryList({"hwmon*"}, QDir::Dirs | QDir::System);
    std::sort(names.begin(), names.end(), [](const QString &a, const QString &b) { return a.mid(5).toInt() < b.mid(5).toInt(); });
    for (const auto &hw : names) {
        const QString dir = hwmon.filePath(hw);
        const QString chip = read(dir + "/name").trimmed();
        // Batteries and USB-C ports have their own page section or say nothing useful.
        if (chip.startsWith("ucsi") || chip == "ACAD" || chip.startsWith("BAT") || chip.contains("fan_curve"))
            continue;
        QString title = chip;
        if (chip == "k10temp" || chip == "coretemp" || chip == "zenpower") title = tr("Processor");
        else if (chip == "amdgpu") title = tr("AMD graphics");
        else if (chip == "nvme") title = tr("NVMe SSD");
        else if (chip == "acpitz") title = tr("Mainboard (ACPI)");
        else if (chip.startsWith("mt7") || chip.startsWith("iwlwifi") || chip.contains("phy")) title = tr("Wi-Fi card");
        else if (chip == "asus" || chip == "thinkpad" || chip == "dell_smm") title = tr("Laptop fans");
        else if (chip == "acpi_fan") title = tr("ACPI fan");

        const auto files = QDir(dir).entryList({"temp*_input", "fan*_input"}, QDir::Files | QDir::System);
        for (const auto &file : files) {
            const QString base = file.left(file.indexOf('_'));
            const QString raw = read(dir + '/' + file).trimmed();
            if (raw.isEmpty())
                continue;
            QString label = read(dir + '/' + base + "_label").trimmed();
            QVariantMap s;
            s["chip"] = title;
            if (base.startsWith("temp")) {
                const double c = raw.toDouble() / 1000;
                if (c <= -40 || c > 150)
                    continue;
                const double crit = read(dir + '/' + base + "_crit").trimmed().toDouble() / 1000;
                s["kind"] = "temp";
                s["value"] = c;
                s["text"] = locale.toString(c, 'f', 0) + " °C";
                s["level"] = c >= (crit > 0 ? crit - 10 : 85) ? 2 : c >= 70 ? 1 : 0;
                // Fill the bar against a sensible range rather than 0 °C.
                s["fraction"] = qBound(0.0, (c - 20) / ((crit > 0 ? crit : 100) - 20), 1.0);
                if (label.isEmpty()) label = tr("Temperature");
                else if (label == "Tctl") label = tr("Package (Tctl)");
                else if (label == "Composite") label = tr("Composite");
                else if (label == "edge") label = tr("Edge");
            } else {
                const double rpm = raw.toDouble();
                s["kind"] = "fan";
                s["value"] = rpm;
                s["text"] = rpm > 0 ? locale.toString(rpm, 'f', 0) + " RPM" : tr("Off");
                s["level"] = 0;
                s["fraction"] = qBound(0.0, rpm / 6000, 1.0);
                if (label.isEmpty()) label = tr("Fan");
                else if (label == "cpu_fan") label = tr("CPU fan");
                else if (label == "gpu_fan") label = tr("GPU fan");
            }
            s["label"] = label;
            sensors.append(s);
        }
    }
    if (m_nvidia.valid && m_nvidia.temperature >= 0) {
        QVariantMap s;
        s["chip"] = m_nvidia.name;
        s["kind"] = "temp";
        s["label"] = tr("Temperature");
        s["value"] = m_nvidia.temperature;
        s["text"] = locale.toString(m_nvidia.temperature, 'f', 0) + " °C";
        s["level"] = m_nvidia.temperature >= 85 ? 2 : m_nvidia.temperature >= 70 ? 1 : 0;
        s["fraction"] = qBound(0.0, (m_nvidia.temperature - 20) / 80, 1.0);
        sensors.append(s);
    }
    m_sensors = sensors;
}

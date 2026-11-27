#include <QDir>
#include <QFile>
#include <QProcess>
#include <QTemporaryDir>
#include <QtTest>
#include <unistd.h>

#include "processmodel.h"
#include "procparse.h"
#include "services.h"
#include "theme.h"
#include "translator.h"

using namespace ProcParse;

static void write(const QString &path, const QByteArray &text) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    QVERIFY(f.open(QIODevice::WriteOnly));
    f.write(text);
}

class OmaTaskTests : public QObject {
    Q_OBJECT

private slots:
    void cpuUsageFromStatDeltas() {
        const auto a = cpuTimes("cpu  100 0 100 800 0 0 0 0 0 0\ncpu0 50 0 50 400 0 0 0 0 0 0\nbtime 1700000000\n");
        const auto b = cpuTimes("cpu  150 0 150 900 0 0 0 0 0 0\ncpu0 100 0 50 450 0 0 0 0 0 0\n");
        QCOMPARE(a.size(), 2);
        QCOMPARE(usage(a[0], b[0]), 50.0);
        QCOMPARE(usage(a[1], b[1]), 50.0);
        QCOMPARE(bootTime("cpu 1 2 3 4\nbtime 1700000000\n"), 1700000000ull);
    }

    void meminfoInBytes() {
        const auto m = meminfo("MemTotal:       16000000 kB\nMemAvailable:    8000000 kB\nHugePages_Total:       0\n");
        QCOMPARE(m.value("MemTotal"), 16000000ull * 1024);
        QCOMPARE(m.value("HugePages_Total"), 0ull);
    }

    void diskstatsKeepsWholeDisks() {
        const auto d = diskstats(
            " 259       0 nvme0n1 100 0 2000 0 50 0 4000 0 0 300 0\n"
            " 259       1 nvme0n1p1 1 0 8 0 0 0 0 0 0 1 0\n"
            "   7       0 loop0 1 0 8 0 0 0 0 0 0 1 0\n"
            " 253       0 dm-0 1 0 8 0 0 0 0 0 0 1 0\n");
        QCOMPARE(d.size(), 1);
        QCOMPARE(d.value("nvme0n1").readBytes, 2000ull * 512);
        QCOMPARE(d.value("nvme0n1").writeBytes, 4000ull * 512);
        QCOMPARE(d.value("nvme0n1").busyMs, 300ull);
        QVERIFY(isWholeDisk("sda"));
        QVERIFY(!isWholeDisk("sda1"));
        QVERIFY(!isWholeDisk("zram0"));
    }

    void netdevSkipsVirtual() {
        const auto n = netdev("Inter-|   Receive\n face |bytes\n    lo: 10 1 0 0 0 0 0 0 10 1 0 0 0 0 0 0\n"
                              "wlan0: 1000 5 0 0 0 0 0 0 2000 6 0 0 0 0 0 0\n veth12: 1 1 0 0 0 0 0 0 1 1 0 0 0 0 0 0\n");
        QCOMPARE(n.size(), 1);
        QCOMPARE(n.value("wlan0").rxBytes, 1000ull);
        QCOMPARE(n.value("wlan0").txBytes, 2000ull);
    }

    void pidStatWithSpacesInName() {
        PidStat s;
        QVERIFY(pidStat("1234 (Web Content) S 1000 1234 1234 0 -1 4194560 100 0 0 0 70 30 0 0 20 5 12 0 98765 0 0", &s));
        QCOMPARE(s.pid, 1234);
        QCOMPARE(s.comm, QString("Web Content"));
        QCOMPARE(s.state, QChar('S'));
        QCOMPARE(s.ppid, 1000);
        QCOMPARE(s.ticks, 100ull);
        QCOMPARE(s.nice, 5);
        QCOMPARE(s.threads, 12);
        QCOMPARE(s.startTicks, 98765ull);
    }

    void statusAndIo() {
        const auto st = pidStatus("Name:\tx\nUid:\t1000\t1000\t1000\t1000\nVmRSS:\t   2048 kB\nRssAnon:\t    1024 kB\n");
        QCOMPARE(st.uid, 1000u);
        QCOMPARE(st.rssAnon, 1024ull * 1024);
        const auto io = pidIo("rchar: 5\nread_bytes: 4096\nwrite_bytes: 8192\n");
        QCOMPARE(io.readBytes, 4096ull);
        QCOMPARE(io.writeBytes, 8192ull);
    }

    void drmFdinfoPicksBusiestEngine() {
        const auto c = drmFdinfo("pos:\t0\ndrm-driver:\tamdgpu\ndrm-client-id:\t46\ndrm-pdev:\t0000:65:00.0\n"
                                 "drm-memory-vram:\t10096 KiB\ndrm-engine-gfx:\t7000 ns\ndrm-engine-compute:\t600 ns\n");
        QVERIFY(c.valid);
        QCOMPARE(c.pdev, QString("0000:65:00.0"));
        QCOMPARE(c.clientId, 46ull);
        QCOMPARE(c.engineNs, 7000ull);
        QCOMPARE(c.vramBytes, 10096ull * 1024);
    }

    void nvidiaSmiCsv() {
        const auto g = nvidiaSmi("NVIDIA GeForce RTX 4060 Laptop GPU, 37, 512, 8188, 48, 12.34\n");
        QVERIFY(g.valid);
        QCOMPARE(g.utilization, 37.0);
        QCOMPARE(g.memoryTotalMiB, 8188.0);
        QCOMPARE(g.power, 12.34);
        const auto na = nvidiaSmi("NVIDIA GeForce RTX 4060 Laptop GPU, 3, 1, 8188, 40, [N/A]\n");
        QCOMPARE(na.power, -1.0);
    }

    void batteryFromChargeOrEnergy() {
        const auto charge = battery("POWER_SUPPLY_NAME=BAT1\nPOWER_SUPPLY_TYPE=Battery\nPOWER_SUPPLY_STATUS=Discharging\n"
                                    "POWER_SUPPLY_VOLTAGE_MIN_DESIGN=16000000\nPOWER_SUPPLY_VOLTAGE_NOW=15000000\n"
                                    "POWER_SUPPLY_CURRENT_NOW=1000000\nPOWER_SUPPLY_CHARGE_FULL_DESIGN=4000000\n"
                                    "POWER_SUPPLY_CHARGE_FULL=3000000\nPOWER_SUPPLY_CHARGE_NOW=1500000\nPOWER_SUPPLY_CAPACITY=50\n");
        QVERIFY(charge.valid);
        QCOMPARE(charge.powerW, 15.0);
        QCOMPARE(charge.energyNowWh, 24.0);
        QCOMPARE(charge.energyDesignWh, 64.0);
        const auto energy = battery("POWER_SUPPLY_TYPE=Battery\nPOWER_SUPPLY_POWER_NOW=7500000\nPOWER_SUPPLY_ENERGY_NOW=30000000\n"
                                    "POWER_SUPPLY_ENERGY_FULL=50000000\n");
        QCOMPARE(energy.powerW, 7.5);
        QCOMPARE(energy.energyFullWh, 50.0);
        QVERIFY(!battery("POWER_SUPPLY_TYPE=Mains\nPOWER_SUPPLY_ONLINE=1\n").valid);
    }

    void hyprlandStartup() {
        QCOMPARE(hyprExecOnce("exec-once = waybar # bar\n# exec-once = off\nexec = other\n"), QStringList{"waybar"});
        const QString lua = "hl.on(\"hyprland.start\", function()\n"
                            "  hl.exec_cmd(\"omarchy-launch-shell\")\n"
                            "  hl.exec_cmd(o.launch(\"udiskie --automount\"))\n"
                            "end)\n"
                            "-- o.launch_on_start(\"commented\")\n"
                            "o.launch_on_start('syncthing')\n";
        QCOMPARE(hyprLuaStartup(lua, true), (QStringList{"omarchy-launch-shell", "udiskie --automount", "syncthing"}));
        QCOMPARE(hyprLuaStartup(lua, false), QStringList{"syncthing"});
        QCOMPARE(hyprSources("source = ~/.config/hypr/a.conf\nsource = b.conf\n", "/home/u", "/etc/hypr"),
                 (QStringList{"/home/u/.config/hypr/a.conf", "/etc/hypr/b.conf"}));
    }

    void hyprAutostartReadsLuaFiles() {
        QTemporaryDir home, omarchy;
        write(omarchy.filePath("default/hypr/autostart.lua"), "hl.exec_cmd(\"omarchy-launch-shell\")\n");
        write(home.filePath(".config/hypr/autostart.lua"), "o.launch_on_start(\"syncthing\")\n");
        write(home.filePath(".config/hypr/bindings.lua"), "hl.exec_cmd(\"not-at-start\")\n");
        const auto entries = Services::hyprAutostart(home.path(), omarchy.path());
        QCOMPARE(entries.size(), 2);
        QCOMPARE(entries[0].toMap().value("name").toString(), QString("omarchy-launch-shell"));
        QCOMPARE(entries[1].toMap().value("name").toString(), QString("syncthing"));
    }

    void servicesMergeSortsFailedFirst() {
        const auto units = systemctlJson(R"([{"unit":"b.service","active":"active","sub":"running","description":"B"},
                                             {"unit":"a.service","active":"failed","sub":"failed","description":"A"}])");
        const auto files = systemctlJson(R"([{"unit_file":"b.service","state":"enabled"},
                                             {"unit_file":"c.service","state":"disabled"},
                                             {"unit_file":"t@.service","state":"disabled"}])");
        const auto merged = Services::merge(units, files);
        QCOMPARE(merged.size(), 3);
        QCOMPARE(merged[0].toMap().value("unit").toString(), QString("a.service"));
        QCOMPARE(merged[1].toMap().value("enabled").toString(), QString("enabled"));
        QCOMPARE(merged[2].toMap().value("unit").toString(), QString("c.service"));
    }

    void groupsAppsUnderTheirRoot() {
        QHash<int, ProcessModel::Proc> procs;
        auto add = [&](int pid, int ppid, const QString &comm, uint uid = 1000) {
            ProcessModel::Proc p;
            p.pid = pid; p.ppid = ppid; p.comm = comm; p.uid = uid;
            procs.insert(pid, p);
        };
        add(1, 0, "systemd", 0);
        add(900, 1, "systemd");
        add(1000, 900, "chromium");
        add(1001, 1000, "chromium");
        add(1002, 1001, "chromium");
        add(2000, 900, "ghostty");
        add(2001, 2000, "bash");
        add(3000, 1, "sudo", 0);
        add(3001, 3000, "bash");
        QCOMPARE(ProcessModel::groupRoot(1002, procs), 1000);
        QCOMPARE(ProcessModel::groupRoot(2001, procs), 2000);
        QCOMPARE(ProcessModel::groupRoot(900, procs), 900);
        // A user process under a root parent starts its own group.
        QCOMPARE(ProcessModel::groupRoot(3001, procs), 3001);
    }

    void processModelReadsAFakeProc() {
        QTemporaryDir proc;
        write(proc.filePath("stat"), "cpu  1 0 1 10 0 0 0 0\nbtime 1700000000\n");
        write(proc.filePath("10/stat"), "10 (myapp) S 1 10 10 0 -1 0 0 0 0 0 5 5 0 0 20 0 3 0 100 0 0");
        write(proc.filePath("10/status"), QString("Uid:\t%1\t0\t0\t0\nRssAnon:\t2048 kB\n").arg(getuid()).toUtf8());
        write(proc.filePath("11/stat"), "11 (helper) S 10 10 10 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 101 0 0");
        write(proc.filePath("11/status"), QString("Uid:\t%1\t0\t0\t0\nRssAnon:\t1024 kB\n").arg(getuid()).toUtf8());
        ProcessModel model(nullptr, proc.path());
        model.refresh();
        QCOMPARE(model.processCount(), 2);
        // A background section header and one group of two.
        QCOMPARE(model.rowCount(), 2);
        const int group = model.rowOf("g:10");
        QVERIFY(group >= 0);
        QCOMPARE(model.data(model.index(group), ProcessModel::CountRole).toInt(), 2);
        QCOMPARE(model.data(model.index(group), ProcessModel::MemRole).toDouble(), 3.0 * 1024 * 1024);
        model.toggle("g:10");
        QCOMPARE(model.rowCount(), 4);
        model.setGrouped(false);
        QCOMPARE(model.rowCount(), 2);
        model.setFilter("helper");
        QCOMPARE(model.rowCount(), 1);
        QCOMPARE(model.data(model.index(0), ProcessModel::PidRole).toInt(), 11);
    }

    void endTaskStopsARealProcess() {
        QProcess sleeper;
        sleeper.start("sleep", {"60"});
        QVERIFY(sleeper.waitForStarted());
        ProcessModel model(nullptr);
        model.refresh();
        const QString key = "p:" + QString::number(sleeper.processId());
        QVERIFY(model.endTask(key, false));
        QVERIFY(sleeper.waitForFinished(3000));
        QCOMPARE(sleeper.exitStatus(), QProcess::CrashExit);   // ended by SIGTERM
    }

    void germanCatalogCoversPlurals() {
        QTemporaryDir dir;
        write(dir.filePath("language"), "de\n");
        Translator t(dir.filePath("language"));
        QCOMPARE(t.translate("ProcessesPage", "%n processes", nullptr, 1), QString("%n Prozess"));
        QCOMPARE(t.translate("ProcessesPage", "%n processes", nullptr, 5), QString("%n Prozesse"));
        QCOMPARE(t.translate("SysMonitor", "Memory"), QString("Arbeitsspeicher"));
    }
};

QTEST_MAIN(OmaTaskTests)
#include "omatask_tests.moc"

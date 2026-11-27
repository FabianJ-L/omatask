#pragma once

#include <QHash>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include "gpuclients.h"
#include "procparse.h"

// Samples the machine once per interval: CPU, memory, disks, network, both
// GPUs, the battery and every hwmon sensor, keeping a minute of history for
// the graphs. It also drives the process list's clock, so everything on
// screen moves in step.
class SysMonitor : public QObject {
    Q_OBJECT
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY settingsChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY settingsChanged)
    Q_PROPERTY(int activePage READ activePage WRITE setActivePage NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY sampled)
    Q_PROPERTY(QVariantMap battery READ battery NOTIFY sampled)
    Q_PROPERTY(QVariantList sensors READ sensors NOTIFY sampled)
    Q_PROPERTY(double cpuPercent READ cpuPercent NOTIFY sampled)
    Q_PROPERTY(double memPercent READ memPercent NOTIFY sampled)
    Q_PROPERTY(double diskPercent READ diskPercent NOTIFY sampled)
    Q_PROPERTY(double gpuPercent READ gpuPercent NOTIFY sampled)
    Q_PROPERTY(int historyLength READ historyLength CONSTANT)

public:
    enum Page { ProcessesPage = 0, PerformancePage, SensorsPage, StartupPage, ServicesPage };

    explicit SysMonitor(const QString &procRoot = "/proc", const QString &sysRoot = "/sys", QObject *parent = nullptr);
    ~SysMonitor() override;

    int interval() const { return m_timer.interval(); }
    void setInterval(int ms);
    bool paused() const { return m_paused; }
    void setPaused(bool paused);
    int activePage() const { return m_activePage; }
    void setActivePage(int page);

    QVariantList devices() const { return m_devices; }
    QVariantMap battery() const { return m_battery; }
    QVariantList sensors() const { return m_sensors; }
    double cpuPercent() const { return m_cpuPercent; }
    double memPercent() const { return m_memPercent; }
    double diskPercent() const { return m_diskPercent; }
    double gpuPercent() const { return m_gpuPercent; }
    int historyLength() const { return HistoryLength; }

    GpuClients &gpuClients() { return m_gpu; }
    int coreCount() const { return qMax(1, int(m_lastCpu.size()) - 1); }
    double lastIntervalSeconds() const { return m_lastDt; }

    Q_INVOKABLE void sampleNow() { sample(); }

signals:
    void settingsChanged();
    // Emitted after every sample; the process model refreshes on it.
    void sampled();

private:
    static constexpr int HistoryLength = 60;
    using History = QList<double>;

    void sample();
    void sampleCpu(QVariantList &out);
    void sampleMemory(QVariantList &out);
    void sampleGpus(QVariantList &out);
    void sampleDisks(QVariantList &out);
    void sampleNetwork(QVariantList &out);
    void sampleBattery();
    void sampleSensors();
    void pollNvidia(const QString &pciPath);
    void push(const QString &key, double value);
    QVariantList history(const QString &key) const;
    QString read(const QString &path) const;
    QVariantList stat(const QString &label, const QString &value) const;

    QString m_proc, m_sys;
    QTimer m_timer;
    bool m_paused = false;
    int m_activePage = 0;
    int m_tick = 0;
    double m_lastDt = 1;
    qint64 m_lastSampleNs = 0;

    QList<ProcParse::CpuTimes> m_lastCpu;
    QHash<QString, ProcParse::DiskCounters> m_lastDisk;
    QHash<QString, ProcParse::NetCounters> m_lastNet;
    QHash<QString, History> m_history;
    QString m_cpuModel;
    int m_physicalCores = 0;

    GpuClients m_gpu;
    QProcess m_nvidiaSmi;
    ProcParse::NvidiaGpu m_nvidia;
    qint64 m_nvidiaAt = 0;

    QVariantList m_devices, m_sensors;
    QVariantMap m_battery;
    double m_cpuPercent = 0, m_memPercent = 0, m_diskPercent = 0, m_gpuPercent = 0;
};

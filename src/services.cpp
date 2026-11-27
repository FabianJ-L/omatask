#include "services.h"

#include "procparse.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QLocale>
#include <QSet>
#include <QStandardPaths>

static QString readText(const QString &path) {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

Services::Services(const QString &homeDir, QObject *parent)
    : QObject(parent), m_home(homeDir.isEmpty() ? QDir::homePath() : homeDir) {}

void Services::setSystem(bool system) {
    if (system == m_system)
        return;
    m_system = system;
    m_units.clear();
    emit changed();
    refresh();
}

void Services::setFilter(const QString &filter) {
    if (filter == m_filter)
        return;
    m_filter = filter;
    emit changed();
}

QVariantList Services::units() const {
    if (m_filter.trimmed().isEmpty())
        return m_units;
    QVariantList filtered;
    for (const auto &u : m_units) {
        const auto map = u.toMap();
        if (map.value("unit").toString().contains(m_filter.trimmed(), Qt::CaseInsensitive) ||
            map.value("description").toString().contains(m_filter.trimmed(), Qt::CaseInsensitive))
            filtered.append(u);
    }
    return filtered;
}

void Services::setError(const QString &error) {
    m_error = error;
    emit changed();
}

void Services::clearError() {
    setError({});
}

void Services::run(const QStringList &args, std::function<void(const QByteArray &)> done) {
    const QString systemctl = QStandardPaths::findExecutable("systemctl");
    if (systemctl.isEmpty()) {
        setError(tr("systemctl was not found, so services cannot be shown."));
        return;
    }
    auto *proc = new QProcess(this);
    ++m_running;
    emit changed();
    connect(proc, &QProcess::finished, this, [this, proc, done](int code, QProcess::ExitStatus) {
        --m_running;
        if (code == 0)
            done(proc->readAllStandardOutput());
        else
            setError(QString::fromUtf8(proc->readAllStandardError()).trimmed());
        proc->deleteLater();
        emit changed();
    });
    proc->start(systemctl, args);
}

QVariantList Services::merge(const QList<QVariantMap> &units, const QList<QVariantMap> &files) {
    QHash<QString, QString> fileState;
    for (const auto &f : files)
        fileState.insert(f.value("unit_file").toString(), f.value("state").toString());
    QVariantList result;
    QSet<QString> seen;
    auto add = [&](const QString &unit, const QString &description, const QString &active, const QString &sub) {
        if (unit.endsWith("@.service") || unit.startsWith("dbus-:"))
            return;   // templates and D-Bus activation leftovers are not services to manage
        QVariantMap m;
        m["unit"] = unit;
        m["name"] = QString(unit).remove(".service");
        m["description"] = description;
        m["active"] = active;
        m["sub"] = sub;
        m["enabled"] = fileState.value(unit, "static");
        m["running"] = active == "active";
        m["failed"] = active == "failed";
        result.append(m);
        seen.insert(unit);
    };
    for (const auto &u : units)
        add(u.value("unit").toString(), u.value("description").toString(), u.value("active").toString(),
            u.value("sub").toString());
    // Installed but never loaded: still worth listing so they can be started.
    for (auto it = fileState.cbegin(); it != fileState.cend(); ++it)
        if (!seen.contains(it.key()) && it.key().endsWith(".service"))
            add(it.key(), QString(), "inactive", "dead");
    std::sort(result.begin(), result.end(), [](const QVariant &a, const QVariant &b) {
        const auto x = a.toMap(), y = b.toMap();
        // Failed first, then running, then the rest, each alphabetically.
        const int rx = x["failed"].toBool() ? 0 : x["running"].toBool() ? 1 : 2;
        const int ry = y["failed"].toBool() ? 0 : y["running"].toBool() ? 1 : 2;
        if (rx != ry)
            return rx < ry;
        return x["unit"].toString().compare(y["unit"].toString(), Qt::CaseInsensitive) < 0;
    });
    return result;
}

void Services::refresh() {
    const QString scope = m_system ? "--system" : "--user";
    const bool system = m_system;
    run({scope, "list-units", "--type=service", "--all", "--output=json", "--no-pager"}, [this, system, scope](const QByteArray &out) {
        if (system != m_system)
            return;
        m_rawUnits = ProcParse::systemctlJson(out);
        run({scope, "list-unit-files", "--type=service", "--output=json", "--no-pager"}, [this, system](const QByteArray &out) {
            if (system != m_system)
                return;
            m_rawFiles = ProcParse::systemctlJson(out);
            m_units = merge(m_rawUnits, m_rawFiles);
            emit changed();
        });
    });
}

static QVariantMap hyprEntry(const QString &command, const QString &file, const QString &homeDir, bool omarchy) {
    QString shown = command;
    // uwsm-app -- foo: the program is what follows the separator.
    for (const QString &prefix : {QStringLiteral("uwsm-app -- "), QStringLiteral("uwsm app -- ")})
        if (shown.startsWith(prefix))
            shown = shown.mid(prefix.size());
    if (shown.startsWith("sleep ") && shown.contains("&&"))
        shown = shown.section("&&", 1).trimmed();
    QVariantMap e;
    e["kind"] = "hyprland";
    e["name"] = QFileInfo(shown.section(' ', 0, 0)).fileName();
    e["command"] = command;
    e["source"] = QString(file).replace(homeDir, "~");
    e["omarchy"] = omarchy;
    e["enabled"] = true;
    e["toggleable"] = false;
    return e;
}

QVariantList Services::hyprAutostart(const QString &homeDir, const QString &omarchyPath) {
    QVariantList entries;
    const QString hyprDir = homeDir + "/.config/hypr";

    // Lua configs (Hyprland 0.50+, current Omarchy): Omarchy's own autostart,
    // then anything the user's files start with o.launch_on_start.
    const QString omarchyAutostart = omarchyPath + "/default/hypr/autostart.lua";
    for (const auto &command : ProcParse::hyprLuaStartup(readText(omarchyAutostart), true))
        entries.append(hyprEntry(command, omarchyAutostart, homeDir, true));
    for (const auto &file : QDir(hyprDir).entryInfoList({"*.lua"}, QDir::Files, QDir::Name)) {
        const bool autostart = file.fileName() == "autostart.lua";
        for (const auto &command : ProcParse::hyprLuaStartup(readText(file.filePath()), autostart))
            entries.append(hyprEntry(command, file.filePath(), homeDir, false));
    }

    // Classic hyprland.conf with exec-once lines and source = includes.
    QStringList queue{hyprDir + "/hyprland.conf"};
    QSet<QString> visited;
    while (!queue.isEmpty() && visited.size() < 64) {
        const QString file = queue.takeFirst();
        if (visited.contains(file))
            continue;
        visited.insert(file);
        const QString text = readText(file);
        if (text.isEmpty())
            continue;
        for (const auto &command : ProcParse::hyprExecOnce(text))
            entries.append(hyprEntry(command, file, homeDir, !file.startsWith(hyprDir)));
        queue << ProcParse::hyprSources(text, homeDir, QFileInfo(file).absolutePath());
    }
    return entries;
}

void Services::refreshStartup() {
    const QString omarchy = qEnvironmentVariable("OMARCHY_PATH", "/usr/share/omarchy");
    QVariantList startup = hyprAutostart(m_home, omarchy);

    // XDG autostart entries, the user's own overriding the system's.
    QHash<QString, QVariantMap> xdg;
    const QString language = QLocale().name().section('_', 0, 0);
    for (const QString &dir : {QString("/etc/xdg/autostart"), m_home + "/.config/autostart"}) {
        for (const auto &file : QDir(dir).entryInfoList({"*.desktop"}, QDir::Files)) {
            QVariantMap e;
            QString name, localized, exec, onlyShowIn;
            bool hidden = false;
            for (const auto &line : readText(file.filePath()).split('\n')) {
                if (line.startsWith("Name=")) name = line.mid(5).trimmed();
                else if (line.startsWith("Name[" + language + "]=")) localized = line.section('=', 1).trimmed();
                else if (line.startsWith("Exec=")) exec = line.mid(5).trimmed();
                else if (line.startsWith("Hidden=")) hidden = line.mid(7).trimmed() == "true";
                else if (line.startsWith("OnlyShowIn=")) onlyShowIn = line.mid(11).trimmed();
            }
            // Entries meant only for GNOME or KDE never start on Hyprland.
            if (!onlyShowIn.isEmpty() && !onlyShowIn.contains("Hyprland", Qt::CaseInsensitive))
                continue;
            e["kind"] = "xdg";
            e["name"] = localized.isEmpty() ? name : localized;
            e["command"] = exec;
            e["source"] = QString(file.filePath()).replace(m_home, "~");
            e["enabled"] = !hidden;
            e["toggleable"] = false;
            xdg.insert(file.fileName(), e);
        }
    }
    for (const auto &e : std::as_const(xdg))
        startup.append(e);

    // User units that start with the session.
    run({"--user", "list-unit-files", "--type=service", "--output=json", "--no-pager"}, [this, startup](const QByteArray &out) {
        QVariantList all = startup;
        for (const auto &f : ProcParse::systemctlJson(out)) {
            const QString state = f.value("state").toString();
            if (state != "enabled" && state != "disabled")
                continue;
            const QString unit = f.value("unit_file").toString();
            if (unit.endsWith("@.service"))
                continue;
            QVariantMap e;
            e["kind"] = "systemd";
            e["name"] = QString(unit).remove(".service");
            e["command"] = unit;
            e["source"] = "systemctl --user";
            e["enabled"] = state == "enabled";
            e["toggleable"] = true;
            e["unit"] = unit;
            all.append(e);
        }
        // Enabled units first, so what actually starts is on top.
        std::stable_sort(all.begin(), all.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value("enabled").toBool() > b.toMap().value("enabled").toBool();
        });
        m_startup = all;
        emit changed();
    });
    m_startup = startup;
    emit changed();
}

void Services::act(const QString &unit, const QString &verb, bool system) {
    static const QSet<QString> verbs{"start", "stop", "restart", "enable", "disable"};
    if (!verbs.contains(verb) || unit.isEmpty() || unit.startsWith('-'))
        return;
    auto after = [this](const QByteArray &) {
        refresh();
        refreshStartup();
    };
    if (!system) {
        run({"--user", verb, unit}, after);
        return;
    }
    // System units need root; polkit asks for the password itself when
    // systemctl talks to systemd, so no pkexec wrapper is needed.
    run({"--system", verb, unit}, after);
}

// Theme watching follows Omacut (MIT, David Heinemeier Hansson).
#include "theme.h"

#include <QColor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <cmath>

Theme::Theme(const QString &directory, QObject *parent, const QString &hyprctl)
    : QObject(parent),
      m_directory(directory.isEmpty() ? QDir::homePath() + "/.local/state/omarchy/current" : directory) {
    m_colors = palette({});
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(80);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_debounce.start(); });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
    connect(&m_debounce, &QTimer::timeout, this, &Theme::reload);

    // Corners follow Hyprland's effective rounding, which themes and personal
    // overrides can both set, so ask hyprctl rather than reading its config.
    // Without Hyprland the corners stay sharp, like Omarchy's default.
    m_hyprctl = !hyprctl.isEmpty() ? hyprctl
              : directory.isEmpty() && !qEnvironmentVariableIsEmpty("HYPRLAND_INSTANCE_SIGNATURE")
                  ? QStandardPaths::findExecutable("hyprctl") : QString();
    m_roundingTimeout.setSingleShot(true);
    m_roundingTimeout.setInterval(500);
    connect(&m_roundingTimeout, &QTimer::timeout, &m_roundingProcess, &QProcess::kill);
    connect(&m_roundingProcess, &QProcess::errorOccurred, this, [this] { m_roundingTimeout.stop(); });
    connect(&m_roundingProcess, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        m_roundingTimeout.stop();
        const auto value = QJsonDocument::fromJson(m_roundingProcess.readAllStandardOutput()).object().value("int");
        if (code != 0 || status != QProcess::NormalExit || !value.isDouble() || value.toInt(-1) < 0)
            return;
        if (value.toInt() != m_radius) {
            m_radius = value.toInt();
            emit changed();
        }
    });
    m_roundingPoll.setInterval(1000);
    connect(&m_roundingPoll, &QTimer::timeout, this, &Theme::refreshRounding);
    if (!m_hyprctl.isEmpty())
        m_roundingPoll.start();
    reload();
}

Theme::~Theme() {
    if (m_roundingProcess.state() != QProcess::NotRunning) {
        m_roundingProcess.kill();
        m_roundingProcess.waitForFinished(1000);
    }
}

void Theme::refreshRounding() {
    if (m_hyprctl.isEmpty() || m_roundingProcess.state() != QProcess::NotRunning)
        return;
    m_roundingProcess.start(m_hyprctl, {"-j", "getoption", "decoration:rounding"});
    m_roundingTimeout.start();
}

QHash<QString, QString> Theme::readColors(const QString &path) {
    QHash<QString, QString> colors;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return colors;
    const QRegularExpression expression(R"re(^\s*([A-Za-z0-9_]+)\s*=\s*["'](#[0-9a-fA-F]{6})["'])re",
                                        QRegularExpression::MultilineOption);
    auto it = expression.globalMatch(QString::fromUtf8(file.readAll()));
    while (it.hasNext()) {
        const auto match = it.next();
        colors.insert(match.captured(1), match.captured(2));
    }
    return colors;
}

QString Theme::readAccent(const QString &path) {
    return readColors(path).value("accent", "#FFD60A");
}

// Every Omarchy theme has the terminal colors (color0 to color15), newer ones
// also name their surfaces and hues. Prefer the names, fall back to the
// numbered colors, then to a neutral dark palette.
QVariantMap Theme::palette(const QHash<QString, QString> &c) {
    auto pick = [&](std::initializer_list<const char *> keys, const QString &fallback) -> QString {
        for (const char *key : keys)
            if (c.contains(key))
                return c.value(key);
        return fallback;
    };
    const QString background = pick({"background", "color0"}, "#121214");
    const QString foreground = pick({"foreground", "color7"}, "#d4d4d8");
    auto mix = [](const QString &a, const QString &b, double t) {
        const QColor x(a), y(b);
        return QColor::fromRgbF(x.redF() + (y.redF() - x.redF()) * t, x.greenF() + (y.greenF() - x.greenF()) * t,
                                x.blueF() + (y.blueF() - x.blueF()) * t).name();
    };
    QVariantMap p;
    p["background"] = background;
    p["darkBackground"] = pick({"dark_background"}, mix(background, "#000000", .25));
    p["darkerBackground"] = pick({"darker_background"}, mix(background, "#000000", .45));
    p["lighterBackground"] = pick({"lighter_background"}, mix(background, foreground, .08));
    p["selection"] = pick({"selection", "selection_background"}, mix(background, foreground, .18));
    p["foreground"] = foreground;
    p["mutedForeground"] = pick({"dark_foreground", "color8"}, mix(background, foreground, .45));
    p["lightForeground"] = pick({"light_foreground"}, mix(background, foreground, .8));
    p["brightForeground"] = pick({"bright_foreground", "color15"}, foreground);
    p["border"] = pick({"muted"}, mix(background, foreground, .2));
    p["red"] = pick({"red", "color1"}, "#e06c75");
    p["green"] = pick({"green", "color2"}, "#98c379");
    p["yellow"] = pick({"yellow", "color3"}, "#e5c07b");
    p["blue"] = pick({"blue", "color4"}, "#61afef");
    p["magenta"] = pick({"magenta", "color5"}, "#c678dd");
    p["cyan"] = pick({"cyan", "color6"}, "#56b6c2");
    p["orange"] = pick({"orange", "bright_yellow", "color11"}, "#d19a66");
    return p;
}

// Black or white, whichever reads on the accent (WCAG relative luminance).
QString Theme::accentForeground() const {
    const QColor c(m_accent);
    auto linear = [](double v) { return v <= .04045 ? v / 12.92 : std::pow((v + .055) / 1.055, 2.4); };
    const double luminance = .2126 * linear(c.redF()) + .7152 * linear(c.greenF()) + .0722 * linear(c.blueF());
    return luminance > .179 ? "black" : "white";
}

void Theme::reload() {
    refreshRounding();
    const auto paths = m_watcher.files() + m_watcher.directories();
    if (!paths.isEmpty())
        m_watcher.removePaths(paths);

    // A theme switch replaces symlinks and files, so watch the parents too and
    // re-arm after every change. Watching the nearest existing ancestor means
    // installing Omarchy later works without restarting the app.
    QString ancestor = m_directory;
    while (!QFileInfo::exists(ancestor) && ancestor != "/")
        ancestor = QFileInfo(ancestor).absolutePath();
    QStringList candidates{ancestor, QFileInfo(ancestor).absolutePath(), m_directory,
                           m_directory + "/theme", m_directory + "/theme/colors.toml"};
    candidates.removeDuplicates();
    for (const auto &path : candidates)
        if (QFileInfo::exists(path))
            m_watcher.addPath(path);

    const auto colors = readColors(m_directory + "/theme/colors.toml");
    const QString accent = colors.value("accent", "#FFD60A");
    const QVariantMap p = palette(colors);
    if (accent != m_accent || p != m_colors) {
        m_accent = accent;
        m_colors = p;
        emit changed();
    }
}

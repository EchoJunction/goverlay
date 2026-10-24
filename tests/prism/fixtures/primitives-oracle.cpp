// Account-free synthetic global/instance codec oracle; no real Prism data.
#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSettings>
#include <cstdio>

static QByteArray envLine(const QString &path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return {};
    for (const auto &line : f.readAll().split('\n'))
        if (line.startsWith("Env=")) return line;
    return {};
}
static QJsonObject expected(bool instance) {
    if (instance) return {{"MANGOHUD_CONFIGFILE", QString::fromUtf8("/tmp/Synthetic 日本語/overlay.conf")}};
    QString value = QString::fromUtf8("global \"quote\" \\ 日本語 😀");
    for (unsigned char c : {0, 8, 9, 10, 12, 13, 127}) value.append(QChar(c));
    return {{"KEEP", value}, {"", "empty key"}};
}
static bool check(QSettings &settings, bool instance) {
    settings.setFallbacksEnabled(false);
    QJsonParseError error;
    const auto json = QJsonDocument::fromJson(settings.value("Env").toString().toUtf8(), &error);
    return settings.status() == QSettings::NoError &&
        settings.value("ConfigVersion").toString() == "1.3" &&
        settings.value("OverridePerformance").toString() == (instance ? "true" : "false") &&
        settings.value("EnableMangoHud").toString() == (instance ? "false" : "true") &&
        error.error == QJsonParseError::NoError && json.isObject() && json.object() == expected(instance) &&
        (instance ? settings.value("Other/Unknown").toString() == "keep"
                  : settings.value("Other/Env").toString() == "leave-this-section");
}
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (argc != 2) return 2;
    const QString directory = QString::fromLocal8Bit(argv[1]) + "/";
    for (bool instance : {false, true}) {
        const QString name = instance ? "instance.cfg" : "global.ini";
        const QString source = directory + name;
        const QString normalized = directory + "normalized-" + name;
        if (!envLine(source).startsWith("Env=\"")) return 3; // production always quotes
        QSettings reader(source, QSettings::IniFormat);
        if (!check(reader, instance)) return 4;
        if (QFile::exists(normalized)) return 5; // require new disposable output
        {
            QSettings writer(normalized, QSettings::IniFormat);
            writer.setFallbacksEnabled(false);
            for (const auto &key : reader.allKeys()) writer.setValue(key, reader.value(key));
            writer.sync();
            if (writer.status() != QSettings::NoError) return 6;
        }
        QSettings rereader(normalized, QSettings::IniFormat);
        if (!check(rereader, instance)) return 7;
        // Qt chooses quoted multi-entry and escaped unquoted single-entry forms.
        if (envLine(normalized).startsWith("Env=\"") == instance) return 8;
    }
    std::printf("Qt %s: 4 synthetic global/instance read + normalize probes PASS\n", qVersion());
}

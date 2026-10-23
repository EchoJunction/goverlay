// Synthetic fixture oracle only; no Prism installation or account data.
#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QTemporaryDir>
#include <cstdio>

static QByteArray envLine(const QString &path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return {};
    for (const auto &line : f.readAll().split('\n'))
        if (line.startsWith("Env=")) return line;
    return {};
}

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (argc != 2) return 2;
    QTemporaryDir temporary;
    if (!temporary.isValid()) return 3;
    const QJsonObject maps[] = {
        {{"KEEP", "quote\" slash\\ newline\n tab\t"},
         {"MANGOHUD_CONFIGFILE", QString::fromUtf8("/tmp/Prism test/日本語,=#;\\path/overlay.conf")}},
        {{"MANGOHUD_CONFIGFILE", QString::fromUtf8("/tmp/Synthetic 日本語/overlay.conf")}}
    };
    const char *names[] = {"scalar-quoted.ini", "scalar-unquoted.ini"};
    for (int i = 0; i < 2; ++i) {
        const QString path = temporary.path() + "/" + names[i];
        const QByteArray json = QJsonDocument(maps[i]).toJson(QJsonDocument::Compact);
        {
            QSettings writer(path, QSettings::IniFormat);
            writer.setFallbacksEnabled(false);
            writer.setValue("Env", QString::fromUtf8(json));
            writer.sync();
            if (writer.status() != QSettings::NoError) return 4;
        }
        if (envLine(path).isEmpty() || envLine(path) != envLine(QString::fromLocal8Bit(argv[1]) + "/" + names[i])) return 5;
        QSettings reader(path, QSettings::IniFormat);
        reader.setFallbacksEnabled(false);
        const QByteArray decoded = reader.value("Env").toString().toUtf8();
        if (decoded != json || QJsonDocument::fromJson(decoded).object() != maps[i]) return 6;
    }
    std::printf("Qt %s: 2 synthetic Env scalar/JSON fixture probes PASS\n", qVersion());
}

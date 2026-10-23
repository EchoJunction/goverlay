// Synthetic Qt6 IniFormat boundary oracle; no real Prism data is accessed.
#include <QCoreApplication>
#include <QFile>
#include <QSettings>
#include <QTemporaryDir>
#include <iostream>

static bool probe(const QString &path, const QByteArray &bytes,
                  const QStringList &keys, const QStringList &values,
                  QSettings::Status status = QSettings::NoError)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    if (file.write(bytes) != bytes.size()) return false;
    file.close();
    QSettings settings(path, QSettings::IniFormat);
    if (settings.allKeys() != keys) return false;
    for (int i = 0; i < keys.size(); ++i)
        if (settings.value(keys[i]).toString() != values[i]) return false;
    return settings.status() == status;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir temporary;
    if (!temporary.isValid()) return 1;
    int sequence = 0;
    auto check = [&](const QByteArray &bytes, const QStringList &keys,
                     const QStringList &values,
                     QSettings::Status status = QSettings::NoError) {
        // Unique files also prevent Qt's per-path settings cache affecting probes.
        bool ok = probe(temporary.filePath(QString::number(++sequence) + ".ini"),
                        bytes, keys, values, status);
        if (!ok) std::cerr << "probe failed: " << sequence << '\n';
        return ok;
    };
    bool ok = check("[General]\n ConfigVersion = 1.3 \nconfigversion=other\n",
                    {"ConfigVersion", "configversion"}, {"1.3", "other"});
    for (auto section : {"General", "general", "GENERAL", " General "})
        ok &= check(QByteArray("[") + section + "]\nEnv=root\n", {"Env"}, {"root"});
    for (auto section : {"%General", "%47eneral"})
        ok &= check(QByteArray("[") + section + "]\nEnv=literal\n",
                    {"General/Env"}, {"literal"});
    ok &= check("[General]\nEnv=first\n%45nv=second\nEn%76=last\n",
                {"Env"}, {"last"});
    ok &= check("[General]\nE\\nv=slash\n", {"E/nv"}, {"slash"});
    ok &= check("[Other/Sub]\nEnv=value\n", {"Other/Sub/Env"}, {"value"},
                QSettings::FormatError);
    ok &= check("[General]\nEnv=abc#hash\nWrapperCommand=abc;comment\n",
                {"Env", "WrapperCommand"}, {"abc#hash", "abc"});
    ok &= check("[General]\n#comment=hash-key\nEnv=visible\n",
                {"#comment", "Env"}, {"hash-key", "visible"});
    ok &= check("[General]\n#comment\\\nEnv=hidden\n",
                {"#comment/\nEnv"}, {"hidden"});
    ok &= check("[General]\n#comment\"\nEnv=hidden\n", {}, {},
                QSettings::FormatError);
    ok &= check("[General]\nEnv=continued\\\nOther=hidden\n",
                {"Env"}, {"continuedOther=hidden"});
    ok &= check("[General]\nEnv=paired\\\\\nOther=separate\n",
                {"Env", "Other"}, {"paired\\", "separate"});
    ok &= check("[General]\nEnv=\"open\nOther=hidden\n",
                {"Env"}, {"open\nOther=hidden\n"});
    if (ok) std::cout << "Qt document oracle: " << sequence << " probes passed\n";
    return ok ? 0 : 1;
}

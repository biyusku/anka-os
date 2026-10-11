// ANKA OS — System Settings › ANKA Updates
//
// All update logic lives in `anka-update` (modules/update/anka-update.sh).
// This module shows its status and starts the privileged systemd units
// (anka-apply-update / anka-rollback) through pkexec.

#include <KLocalizedString>
#include <KPluginFactory>
#include <KQuickConfigModule>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QProcess>
#include <QString>
#include <QStringList>

class AnkaUpdateKCM : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QString currentVersion   READ currentVersion   NOTIFY statusChanged)
    Q_PROPERTY(QString availableVersion READ availableVersion NOTIFY statusChanged)
    Q_PROPERTY(bool    updateAvailable  READ updateAvailable  NOTIFY statusChanged)
    Q_PROPERTY(QString releaseNotesUrl  READ releaseNotesUrl  NOTIFY statusChanged)
    Q_PROPERTY(QString statusError      READ statusError      NOTIFY statusChanged)
    Q_PROPERTY(bool    checking         READ checking         NOTIFY checkingChanged)
    Q_PROPERTY(bool    updating         READ updating         NOTIFY updatingChanged)
    Q_PROPERTY(QString updateLog        READ updateLog        NOTIFY updateLogChanged)

public:
    explicit AnkaUpdateKCM(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        setButtons(NoAdditionalButton);
        checkForUpdates();
    }

    QString currentVersion()   const { return m_currentVersion; }
    QString availableVersion() const { return m_availableVersion; }
    bool    updateAvailable()  const { return m_updateAvailable; }
    QString releaseNotesUrl()  const { return m_releaseNotesUrl; }
    QString statusError()      const { return m_statusError; }
    bool    checking()         const { return m_checking; }
    bool    updating()         const { return m_updating; }
    QString updateLog()        const { return m_updateLog; }

public Q_SLOTS:
    // ── Ask anka-update what is installed and what is available ─────────────
    void checkForUpdates()
    {
        if (m_checking) return;
        m_checking = true;
        Q_EMIT checkingChanged();

        auto *proc = new QProcess(this);
        connect(proc, &QProcess::finished, this, [this, proc](int exitCode, QProcess::ExitStatus status) {
            proc->deleteLater();
            m_checking = false;
            Q_EMIT checkingChanged();

            const QJsonObject json = QJsonDocument::fromJson(proc->readAllStandardOutput()).object();
            if (status != QProcess::NormalExit || exitCode != 0 || json.isEmpty()) {
                const QString err = QString::fromUtf8(proc->readAllStandardError()).trimmed();
                m_statusError = !err.isEmpty() ? err
                    : QLocale().language() == QLocale::Turkish ? QStringLiteral("Güncellemeler denetlenemedi.")
                                                               : QStringLiteral("Couldn't check for updates.");
                Q_EMIT statusChanged();
                return;
            }

            m_statusError.clear();
            m_currentVersion   = json.value(QLatin1String("current")).toString();
            m_availableVersion = json.value(QLatin1String("latest")).toString();
            m_updateAvailable  = json.value(QLatin1String("updateAvailable")).toBool();

            const QString repo      = json.value(QLatin1String("repo")).toString();
            const QString latest    = m_availableVersion;
            if (latest.startsWith(QLatin1Char('v'))) {
                m_releaseNotesUrl = QStringLiteral("https://github.com/%1/releases/tag/%2").arg(repo, latest);
            } else {
                m_releaseNotesUrl = QStringLiteral("https://github.com/%1/compare/%2...%3")
                    .arg(repo,
                         json.value(QLatin1String("currentRev")).toString(),
                         json.value(QLatin1String("latestRev")).toString());
            }
            Q_EMIT statusChanged();
        });
        proc->start(QStringLiteral("anka-update"), {QStringLiteral("status"), QStringLiteral("--json")});
    }

    void startUpdate() { runUnit(QStringLiteral("anka-apply-update.service")); }
    void rollback()    { runUnit(QStringLiteral("anka-rollback.service")); }

    void cancelUpdate()
    {
        auto *proc = new QProcess(this);
        connect(proc, &QProcess::finished, proc, &QObject::deleteLater);
        proc->start(QStringLiteral("pkexec"),
                    {QStringLiteral("systemctl"), QStringLiteral("stop"), QStringLiteral("anka-apply-update.service")});
    }

    // ── Last lines of the update / rollback journal ─────────────────────────
    void readLog()
    {
        auto *proc = new QProcess(this);
        connect(proc, &QProcess::finished, this, [this, proc](int, QProcess::ExitStatus) {
            proc->deleteLater();
            m_updateLog = QString::fromUtf8(proc->readAllStandardOutput());
            Q_EMIT updateLogChanged();
        });
        proc->start(QStringLiteral("journalctl"),
                    {QStringLiteral("-u"), QStringLiteral("anka-apply-update"),
                     QStringLiteral("-u"), QStringLiteral("anka-rollback"),
                     QStringLiteral("-n"), QStringLiteral("80"),
                     QStringLiteral("-o"), QStringLiteral("cat"),
                     QStringLiteral("--no-pager")});
    }

Q_SIGNALS:
    void statusChanged();
    void checkingChanged();
    void updatingChanged();
    void updateLogChanged();

private:
    // `systemctl start` on a oneshot unit returns when the unit has finished.
    void runUnit(const QString &unit)
    {
        if (m_updating) return;
        m_updating = true;
        m_updateLog.clear();
        Q_EMIT updatingChanged();
        Q_EMIT updateLogChanged();

        auto *proc = new QProcess(this);
        connect(proc, &QProcess::finished, this, [this, proc](int, QProcess::ExitStatus) {
            proc->deleteLater();
            m_updating = false;
            Q_EMIT updatingChanged();
            readLog();
            checkForUpdates();
        });
        proc->start(QStringLiteral("pkexec"), {QStringLiteral("systemctl"), QStringLiteral("start"), unit});
    }

    QString m_currentVersion;
    QString m_availableVersion;
    bool    m_updateAvailable = false;
    QString m_releaseNotesUrl;
    QString m_statusError;
    bool    m_checking = false;
    bool    m_updating = false;
    QString m_updateLog;
};

K_PLUGIN_CLASS_WITH_JSON(AnkaUpdateKCM, "kcm_anka_update.json")
#include "kcm_anka_update.moc"

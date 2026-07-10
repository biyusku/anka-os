#include <KQuickConfigModule>
#include <KPluginFactory>
#include <KLocalizedString>

#include <QProcess>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QTimer>
#include <QString>
#include <QUrl>

class KiwimiUpdateKCM : public KQuickConfigModule
{
    Q_OBJECT

    Q_PROPERTY(QString currentVersion   READ currentVersion   NOTIFY currentVersionChanged)
    Q_PROPERTY(QString availableVersion READ availableVersion NOTIFY availableVersionChanged)
    Q_PROPERTY(bool    updateAvailable  READ updateAvailable  NOTIFY updateAvailableChanged)
    Q_PROPERTY(bool    updating         READ updating         NOTIFY updatingChanged)
    Q_PROPERTY(QString updateLog        READ updateLog        NOTIFY updateLogChanged)

public:
    explicit KiwimiUpdateKCM(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
        , m_network(new QNetworkAccessManager(this))
        , m_checkTimer(new QTimer(this))
    {
        setButtons(NoAdditionalButton);

        // Read local installed version
        QFile vf(QStringLiteral("/etc/kiwimi-version"));
        if (vf.open(QIODevice::ReadOnly | QIODevice::Text)) {
            m_currentVersion = QString::fromUtf8(vf.readAll()).trimmed();
            vf.close();
        } else {
            m_currentVersion = i18n("unknown");
        }

        // Periodic check every 5 minutes
        m_checkTimer->setInterval(5 * 60 * 1000);
        connect(m_checkTimer, &QTimer::timeout, this, &KiwimiUpdateKCM::checkForUpdates);
        m_checkTimer->start();

        // Initial check on load
        QTimer::singleShot(500, this, &KiwimiUpdateKCM::checkForUpdates);
    }

    // ── Property accessors ───────────────────────────────────────────────────

    QString currentVersion()   const { return m_currentVersion; }
    QString availableVersion() const { return m_availableVersion; }
    bool    updateAvailable()  const { return m_updateAvailable; }
    bool    updating()         const { return m_updating; }
    QString updateLog()        const { return m_updateLog; }

public Q_SLOTS:

    // ── Check for updates via GitHub API ─────────────────────────────────────
    void checkForUpdates()
    {
        QNetworkRequest req(QUrl(QStringLiteral(
            "https://api.github.com/repos/kiwimi-os/kiwimi/releases/latest"
        )));
        req.setRawHeader("Accept", "application/vnd.github+json");

        QNetworkReply *reply = m_network->get(req);
        connect(reply, &QNetworkReply::finished, this, [this, reply]() {
            reply->deleteLater();
            if (reply->error() != QNetworkReply::NoError) {
                return;
            }
            const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
            if (doc.isNull()) return;

            QString tag = doc.object().value(QLatin1String("tag_name")).toString();
            if (tag.startsWith(QLatin1Char('v'))) {
                tag = tag.mid(1);
            }

            if (!tag.isEmpty() && tag != m_currentVersion) {
                m_availableVersion = tag;
                m_updateAvailable  = true;
                Q_EMIT availableVersionChanged();
                Q_EMIT updateAvailableChanged();
            }
        });
    }

    // ── Start the update via polkit + systemd ────────────────────────────────
    void startUpdate()
    {
        if (m_updating) return;

        m_updating   = true;
        m_updateLog  = QString();
        Q_EMIT updatingChanged();
        Q_EMIT updateLogChanged();

        auto *proc = new QProcess(this);
        proc->setProgram(QStringLiteral("pkexec"));
        proc->setArguments({
            QStringLiteral("systemctl"),
            QStringLiteral("start"),
            QStringLiteral("kiwimi-apply-update.service"),
        });

        connect(proc, &QProcess::readyReadStandardOutput, this, [this, proc]() {
            m_updateLog += QString::fromUtf8(proc->readAllStandardOutput());
            Q_EMIT updateLogChanged();
        });
        connect(proc, &QProcess::readyReadStandardError, this, [this, proc]() {
            m_updateLog += QString::fromUtf8(proc->readAllStandardError());
            Q_EMIT updateLogChanged();
        });
        connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                this, [this, proc](int exitCode, QProcess::ExitStatus) {
            proc->deleteLater();
            m_updating = false;
            Q_EMIT updatingChanged();

            if (exitCode == 0) {
                // Re-read local version after successful update
                QFile vf(QStringLiteral("/etc/kiwimi-version"));
                if (vf.open(QIODevice::ReadOnly | QIODevice::Text)) {
                    m_currentVersion = QString::fromUtf8(vf.readAll()).trimmed();
                    vf.close();
                    Q_EMIT currentVersionChanged();
                }
                m_updateAvailable = false;
                Q_EMIT updateAvailableChanged();
            }
        });

        proc->start();
    }

    // ── Cancel running update ────────────────────────────────────────────────
    void cancelUpdate()
    {
        // kiwimi-apply-update is a oneshot service; kill the process group
        auto *proc = new QProcess(this);
        proc->setProgram(QStringLiteral("pkexec"));
        proc->setArguments({
            QStringLiteral("systemctl"),
            QStringLiteral("stop"),
            QStringLiteral("kiwimi-apply-update.service"),
        });
        connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                proc, &QProcess::deleteLater);
        proc->start();

        m_updating = false;
        Q_EMIT updatingChanged();
    }

    // ── Roll back to the previous NixOS generation ───────────────────────────
    void rollback()
    {
        auto *proc = new QProcess(this);
        proc->setProgram(QStringLiteral("pkexec"));
        proc->setArguments({
            QStringLiteral("nixos-rebuild"),
            QStringLiteral("switch"),
            QStringLiteral("--rollback"),
        });
        connect(proc, &QProcess::readyReadStandardOutput, this, [this, proc]() {
            m_updateLog += QString::fromUtf8(proc->readAllStandardOutput());
            Q_EMIT updateLogChanged();
        });
        connect(proc, &QProcess::readyReadStandardError, this, [this, proc]() {
            m_updateLog += QString::fromUtf8(proc->readAllStandardError());
            Q_EMIT updateLogChanged();
        });
        connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                proc, &QProcess::deleteLater);
        proc->start();
    }

    // ── Tail the service journal ─────────────────────────────────────────────
    void readLog()
    {
        auto *proc = new QProcess(this);
        proc->setProgram(QStringLiteral("journalctl"));
        proc->setArguments({
            QStringLiteral("-u"),
            QStringLiteral("kiwimi-apply-update"),
            QStringLiteral("-n"),
            QStringLiteral("50"),
            QStringLiteral("--no-pager"),
        });
        connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                this, [this, proc](int, QProcess::ExitStatus) {
            m_updateLog = QString::fromUtf8(proc->readAllStandardOutput());
            Q_EMIT updateLogChanged();
            proc->deleteLater();
        });
        proc->start();
    }

Q_SIGNALS:
    void currentVersionChanged();
    void availableVersionChanged();
    void updateAvailableChanged();
    void updatingChanged();
    void updateLogChanged();

private:
    QNetworkAccessManager *m_network;
    QTimer                *m_checkTimer;

    QString m_currentVersion;
    QString m_availableVersion;
    bool    m_updateAvailable = false;
    bool    m_updating        = false;
    QString m_updateLog;
};

K_PLUGIN_CLASS_WITH_JSON(KiwimiUpdateKCM, "kcm_kiwimi_update.json")
#include "kcm_kiwimi_update.moc"
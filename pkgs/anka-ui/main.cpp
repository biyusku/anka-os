// ANKA's own small windows.
//
//   anka-ui welcome [--ai] [--steam] [--bottles]
//       First-login welcome. Exit code: 10 = AI assistant turned on,
//       11 = turned off, 0 = not asked (see modules/installer).
//   anka-ui answer QUESTION
//       ANKA AI's answer; the window shows "Thinking…" until the answer
//       arrives on stdin (written by anka-ai-daemon, closed when complete).

#include <QApplication>
#include <QIcon>
#include <QLocale>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QSocketNotifier>
#include <QTextStream>

#include <unistd.h>

static void readAnswerFromStdin(QObject *window)
{
    auto *buffer = new QByteArray;
    auto *notifier = new QSocketNotifier(STDIN_FILENO, QSocketNotifier::Read, window);
    QObject::connect(notifier, &QSocketNotifier::activated, window, [=] {
        char chunk[4096];
        const ssize_t n = ::read(STDIN_FILENO, chunk, sizeof chunk);
        if (n > 0) {
            buffer->append(chunk, n);
            return;
        }
        // End of input (or an error): show what arrived.
        notifier->setEnabled(false);
        window->setProperty("answer", QString::fromUtf8(*buffer).trimmed());
        window->setProperty("finished", true);
        delete buffer;
    });
}

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("anka-ui"));
    app.setOrganizationName(QStringLiteral("ANKA"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("anka")));
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }

    const QStringList args = app.arguments();
    const QString mode = args.value(1);
    QVariantMap properties{{QStringLiteral("turkish"), QLocale().language() == QLocale::Turkish}};
    QString window;

    if (mode == QLatin1String("welcome")) {
        window = QStringLiteral("Welcome");
        properties.insert(QStringLiteral("hasAi"), args.contains(QLatin1String("--ai")));
        properties.insert(QStringLiteral("hasSteam"), args.contains(QLatin1String("--steam")));
        properties.insert(QStringLiteral("hasBottles"), args.contains(QLatin1String("--bottles")));
    } else if (mode == QLatin1String("answer") && args.size() > 2) {
        window = QStringLiteral("Answer");
        properties.insert(QStringLiteral("question"), args.at(2));
    } else {
        QTextStream(stderr) << "usage: anka-ui welcome [--ai] [--steam] [--bottles]\n"
                               "       anka-ui answer QUESTION   (answer on stdin)\n";
        return 2;
    }

    QQmlApplicationEngine engine;
    engine.setInitialProperties(properties);
    engine.loadFromModule("org.anka.ui", window);
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    if (window == QLatin1String("Answer")) {
        readAnswerFromStdin(engine.rootObjects().constFirst());
    }
    return app.exec();
}

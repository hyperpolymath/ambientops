#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>

#include "AuditorData.h"

int main(int argc, char *argv[]) {
  QGuiApplication app(argc, argv);
  QGuiApplication::setApplicationName("Immutable Auditor");
  QGuiApplication::setOrganizationName("hyperpolymath");

  QQmlApplicationEngine engine;
  AuditorData auditorData;
  engine.rootContext()->setContextProperty("auditorData", &auditorData);
  QObject::connect(
      &engine,
      &QQmlApplicationEngine::objectCreated,
      &app,
      [](QObject *obj, const QUrl &objUrl) {
        if (!obj && objUrl.isValid()) {
          QCoreApplication::exit(EXIT_FAILURE);
        }
      },
      Qt::QueuedConnection);
  engine.loadFromModule("ImmutableAuditor", "Main");

  return app.exec();
}

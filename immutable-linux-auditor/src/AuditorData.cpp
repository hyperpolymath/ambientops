#include "AuditorData.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QStringList>

namespace {

struct CommandResult {
  int exitCode = -1;
  QString stdOut;
  QString stdErr;
  QString invokedProgram;
  QStringList invokedArgs;
  bool started = false;
  bool usedHostBridge = false;
};

CommandResult runCommand(const QString &program, const QStringList &args, int timeoutMs = 2000) {
  QProcess process;
  process.start(program, args);
  if (!process.waitForStarted(500)) {
    return {-1, QString(), QStringLiteral("failed to start"), program, args, false};
  }
  if (!process.waitForFinished(timeoutMs)) {
    process.kill();
    process.waitForFinished();
    return {-1, QString(), QStringLiteral("timeout"), program, args, true};
  }

  return {
      process.exitCode(),
      QString::fromUtf8(process.readAllStandardOutput()),
      QString::fromUtf8(process.readAllStandardError()),
      program,
      args,
      true};
}

CommandResult runCommandWithHostFallback(const QString &program, const QStringList &args, int timeoutMs = 2000) {
  CommandResult primary = runCommand(program, args, timeoutMs);
  if (!primary.started || primary.exitCode == 127) {
    QStringList hostArgs = args;
    hostArgs.prepend(program);
    CommandResult hostResult = runCommand(QStringLiteral("host-spawn"), hostArgs, timeoutMs);
    hostResult.usedHostBridge = hostResult.started;
    if (!hostResult.started || hostResult.exitCode == 127) {
      QStringList flatpakArgs = args;
      flatpakArgs.prepend(program);
      flatpakArgs.prepend(QStringLiteral("--host"));
      CommandResult flatpakResult = runCommand(QStringLiteral("flatpak-spawn"), flatpakArgs, timeoutMs);
      flatpakResult.usedHostBridge = flatpakResult.started;
      return flatpakResult;
    }
    return hostResult;
  }
  return primary;
}

QString formatCommandDetails(const CommandResult &result) {
  const QString commandLine = result.invokedArgs.isEmpty()
                                  ? result.invokedProgram
                                  : QStringLiteral("%1 %2").arg(result.invokedProgram, result.invokedArgs.join(' '));
  const QString header = QStringLiteral("Command: %1\nExit: %2")
                             .arg(commandLine, QString::number(result.exitCode));
  const QString stdoutBlock = result.stdOut.trimmed().isEmpty()
                                  ? QStringLiteral("\nStdout: <empty>")
                                  : QStringLiteral("\nStdout:\n%1").arg(result.stdOut.trimmed());
  const QString stderrBlock = result.stdErr.trimmed().isEmpty()
                                  ? QStringLiteral("\nStderr: <empty>")
                                  : QStringLiteral("\nStderr:\n%1").arg(result.stdErr.trimmed());
  return header + stdoutBlock + stderrBlock;
}

QString formatErrorMessage(const QString &label, const CommandResult &result) {
  QString detail;
  if (!result.started) {
    detail = QStringLiteral("failed to start (%1)").arg(result.invokedProgram);
  } else if (!result.stdErr.trimmed().isEmpty()) {
    detail = result.stdErr.trimmed();
  } else if (result.exitCode == 127) {
    detail = QStringLiteral("command not found");
  }

  if (detail.isEmpty()) {
    return QStringLiteral("%1: unavailable").arg(label);
  }

  return QStringLiteral("%1: unavailable (%2)").arg(label, detail);
}

QVariantMap makeNode(const QString &name,
                     const QString &status,
                     const QVariantList &children = {},
                     const QString &details = QString()) {
  QVariantMap node;
  node.insert("name", name);
  node.insert("status", status);
  node.insert("details", details);
  if (!children.isEmpty()) {
    node.insert("children", children);
  }
  return node;
}

QStringList splitLines(const QString &output) {
  return output.split('\n', Qt::SkipEmptyParts);
}

QStringList splitColumns(const QString &line) {
  return line.trimmed().split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
}

class AuditorTreeModel : public QAbstractListModel {
  Q_OBJECT
public:
  enum Roles {
    NameRole = Qt::UserRole + 1,
    StatusRole,
    DetailsRole,
    DepthRole,
    HasChildrenRole,
    ExpandedRole
  };

  struct Node {
    QString name;
    QString status;
    QString details;
    QString path;
    QVector<int> children;
    int parent = -1;
    int depth = 0;
    bool expanded = true;
  };

  explicit AuditorTreeModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}

  void setPreserveExpanded(bool preserve) {
    m_preserveExpanded = preserve;
  }

  int rowCount(const QModelIndex &parent = QModelIndex()) const override {
    if (parent.isValid()) {
      return 0;
    }
    return m_visible.size();
  }

  QVariant data(const QModelIndex &index, int role) const override {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_visible.size()) {
      return {};
    }

    const Node &node = m_nodes.at(m_visible.at(index.row()));
    switch (role) {
      case NameRole:
        return node.name;
      case StatusRole:
        return node.status;
      case DetailsRole:
        return node.details;
      case DepthRole:
        return node.depth;
      case HasChildrenRole:
        return !node.children.isEmpty();
      case ExpandedRole:
        return node.expanded;
      default:
        return {};
    }
  }

  QHash<int, QByteArray> roleNames() const override {
    return {
        {NameRole, "location"},
        {StatusRole, "status"},
        {DetailsRole, "details"},
        {DepthRole, "depth"},
        {HasChildrenRole, "hasChildren"},
        {ExpandedRole, "expanded"}};
  }

  Q_INVOKABLE void toggleExpanded(int row) {
    if (row < 0 || row >= m_visible.size()) {
      return;
    }
    const int nodeIndex = m_visible.at(row);
    Node &node = m_nodes[nodeIndex];
    if (node.children.isEmpty()) {
      return;
    }
    node.expanded = !node.expanded;
    rebuildVisible();
  }

  void setRows(const QVariantList &rows) {
    beginResetModel();
    QHash<QString, bool> expandedMap = snapshotExpanded();
    m_nodes.clear();
    m_visible.clear();

    auto addNode = [&](const QVariantMap &map,
                       int parentIndex,
                       int depth,
                       const QString &parentPath,
                       auto &&addNodeRef) -> int {
      Node node;
      node.name = map.value("name").toString();
      node.status = map.value("status").toString();
      node.details = map.value("details").toString();
      node.parent = parentIndex;
      node.depth = depth;
      node.path = parentPath.isEmpty() ? node.name : parentPath + "/" + node.name;
      node.expanded = expandedMap.contains(node.path) ? expandedMap.value(node.path) : (depth < 2);

      const int currentIndex = m_nodes.size();
      m_nodes.push_back(node);

      const QVariant childrenVar = map.value("children");
      if (childrenVar.isValid()) {
        const QVariantList children = childrenVar.toList();
        for (const QVariant &childVar : children) {
          const QVariantMap childMap = childVar.toMap();
          const int childIndex = addNodeRef(childMap, currentIndex, depth + 1, node.path, addNodeRef);
          m_nodes[currentIndex].children.push_back(childIndex);
        }
      }

      return currentIndex;
    };

    for (const QVariant &rootVar : rows) {
      const QVariantMap rootMap = rootVar.toMap();
      addNode(rootMap, -1, 0, QString(), addNode);
    }

    rebuildVisible(false);
    endResetModel();
  }

private:
  QVector<Node> m_nodes;
  QVector<int> m_visible;
  bool m_preserveExpanded = true;

  QHash<QString, bool> snapshotExpanded() const {
    if (!m_preserveExpanded) {
      return {};
    }
    QHash<QString, bool> map;
    for (const Node &node : m_nodes) {
      if (!node.path.isEmpty()) {
        map.insert(node.path, node.expanded);
      }
    }
    return map;
  }

  void rebuildVisible(bool emitReset = true) {
    if (emitReset) {
      beginResetModel();
    }

    m_visible.clear();

    std::function<void(int)> appendNode = [&](int index) {
      m_visible.push_back(index);
      const Node &node = m_nodes.at(index);
      if (!node.expanded) {
        return;
      }
      for (int child : node.children) {
        appendNode(child);
      }
    };

    for (int i = 0; i < m_nodes.size(); ++i) {
      if (m_nodes.at(i).parent == -1) {
        appendNode(i);
      }
    }

    if (emitReset) {
      endResetModel();
    }
  }
};

}  // namespace

AuditorData::AuditorData(QObject *parent) : QObject(parent) {
  m_model = new AuditorTreeModel(this);
  static_cast<AuditorTreeModel *>(m_model)->setPreserveExpanded(m_preserveExpanded);
  refresh();
}

QAbstractListModel *AuditorData::model() const {
  return m_model;
}

bool AuditorData::loading() const {
  return m_loading;
}

QStringList AuditorData::errors() const {
  return m_errors;
}

bool AuditorData::hostBridgeUsed() const {
  return m_hostBridgeUsed;
}

bool AuditorData::preserveExpanded() const {
  return m_preserveExpanded;
}

void AuditorData::setPreserveExpanded(bool preserve) {
  if (m_preserveExpanded == preserve) {
    return;
  }
  m_preserveExpanded = preserve;
  auto *model = static_cast<AuditorTreeModel *>(m_model);
  if (model) {
    model->setPreserveExpanded(preserve);
  }
  emit preserveExpandedChanged();
}

void AuditorData::setLoading(bool loading) {
  if (m_loading == loading) {
    return;
  }
  m_loading = loading;
  emit loadingChanged();
}

void AuditorData::setErrors(const QStringList &errors) {
  if (m_errors == errors) {
    return;
  }
  m_errors = errors;
  emit errorsChanged();
}

void AuditorData::setHostBridgeUsed(bool used) {
  if (m_hostBridgeUsed == used) {
    return;
  }
  m_hostBridgeUsed = used;
  emit hostBridgeUsedChanged();
}

void AuditorData::refresh() {
  setLoading(true);
  setHostBridgeUsed(false);
  QStringList errors;
  QVariantList rows = buildRows(&errors);
  buildModelFromRows(rows);
  setErrors(errors);
  emit modelChanged();
  setLoading(false);
}

void AuditorData::buildModelFromRows(const QVariantList &rows) {
  auto *model = static_cast<AuditorTreeModel *>(m_model);
  if (!model) {
    return;
  }
  model->setPreserveExpanded(m_preserveExpanded);
  model->setRows(rows);
}

QVariantList AuditorData::buildRows(QStringList *errors) {
  auto addError = [&](const QString &message) {
    if (errors) {
      errors->append(message);
    }
  };

  QVariantList rootChildren;

  // Root (rpm-ostree)
  QVariantList rootDetails;
  QString rootStatus = QStringLiteral("unavailable");
  QString layeredStatus = QStringLiteral("unknown");
  QString overridesStatus = QStringLiteral("unknown");

  CommandResult rpmStatus = runCommandWithHostFallback("rpm-ostree", {"status", "--json"});
  if (rpmStatus.usedHostBridge) {
    setHostBridgeUsed(true);
  }
  const QString rpmDetails = formatCommandDetails(rpmStatus);
  if (rpmStatus.exitCode == 0) {
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(rpmStatus.stdOut.toUtf8(), &error);
    if (error.error == QJsonParseError::NoError && doc.isObject()) {
      QJsonObject obj = doc.object();
      QJsonArray deployments = obj.value("deployments").toArray();
      QJsonObject booted;
      QJsonObject pending;
      for (const QJsonValue &value : deployments) {
        QJsonObject dep = value.toObject();
        if (dep.value("booted").toBool()) {
          booted = dep;
        } else if (dep.value("staged").toBool()) {
          pending = dep;
        }
      }

      if (!booted.isEmpty()) {
        const QString version = booted.value("version").toString();
        const QString origin = booted.value("origin").toString();
        rootStatus = QStringLiteral("booted: %1").arg(version.isEmpty() ? origin : version);

        QJsonArray packages = booted.value("packages").toArray();
        layeredStatus = QString::number(packages.size());

        QJsonArray overrides = booted.value("overrides").toArray();
        overridesStatus = QString::number(overrides.size());
      } else {
        rootStatus = QStringLiteral("no booted deployment");
      }

      if (!pending.isEmpty()) {
        const QString version = pending.value("version").toString();
        rootDetails.append(makeNode("Deployment: pending", version.isEmpty() ? "staged" : version));
      } else {
        rootDetails.append(makeNode("Deployment: pending", "none"));
      }

      if (!booted.isEmpty()) {
        rootDetails.insert(0, makeNode("Deployment: current", "committed"));
      } else {
        rootDetails.insert(0, makeNode("Deployment: current", "unknown"));
      }
    } else {
      addError("rpm-ostree: failed to parse JSON output");
    }
  } else {
    addError(formatErrorMessage("rpm-ostree", rpmStatus));
  }

  rootDetails.append(makeNode("Layered packages", layeredStatus));
  rootDetails.append(makeNode("Overrides", overridesStatus));
  rootChildren.append(makeNode("Root (rpm-ostree)", rootStatus, rootDetails, rpmDetails));

  // Flatpak
  QVariantList flatpakChildren;
  QString flatpakStatus = QStringLiteral("unavailable");

  CommandResult flatpakSystem = runCommandWithHostFallback("flatpak", {"list", "--app", "--columns=application", "--system"});
  CommandResult flatpakUser = runCommandWithHostFallback("flatpak", {"list", "--app", "--columns=application", "--user"});
  if (flatpakSystem.usedHostBridge || flatpakUser.usedHostBridge) {
    setHostBridgeUsed(true);
  }

  const QString flatpakSystemDetails = formatCommandDetails(flatpakSystem);
  const QString flatpakUserDetails = formatCommandDetails(flatpakUser);

  if (flatpakSystem.exitCode == 0) {
    QStringList lines = splitLines(flatpakSystem.stdOut);
    QVariantList apps;
    for (const QString &line : lines) {
      apps.append(makeNode("app: " + line.trimmed(), "system"));
    }
    flatpakChildren.append(makeNode("System", QString::number(lines.size()) + " apps", apps, flatpakSystemDetails));
    flatpakStatus = "ok";
  } else {
    flatpakChildren.append(makeNode("System", "unavailable", {}, flatpakSystemDetails));
    addError(formatErrorMessage("flatpak (system)", flatpakSystem));
  }

  if (flatpakUser.exitCode == 0) {
    QStringList lines = splitLines(flatpakUser.stdOut);
    QVariantList apps;
    for (const QString &line : lines) {
      apps.append(makeNode("app: " + line.trimmed(), "user"));
    }
    flatpakChildren.append(makeNode("User", QString::number(lines.size()) + " apps", apps, flatpakUserDetails));
    flatpakStatus = "ok";
  } else {
    flatpakChildren.append(makeNode("User", "unavailable", {}, flatpakUserDetails));
    addError(formatErrorMessage("flatpak (user)", flatpakUser));
  }

  rootChildren.append(makeNode("Flatpak", flatpakStatus, flatpakChildren));

  // Containers (Podman + Distrobox)
  QVariantList containerChildren;
  QString containerStatus = QStringLiteral("partial");
  bool podmanOk = false;
  bool distroboxOk = false;

  CommandResult podman = runCommandWithHostFallback("podman", {"ps", "-a", "--format", "json"});
  if (podman.usedHostBridge) {
    setHostBridgeUsed(true);
  }
  const QString podmanDetails = formatCommandDetails(podman);
  if (podman.exitCode == 0) {
    podmanOk = true;
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(podman.stdOut.toUtf8(), &error);
    if (error.error == QJsonParseError::NoError && doc.isArray()) {
      QJsonArray array = doc.array();
      QVariantList podmanItems;
      for (const QJsonValue &value : array) {
        QJsonObject item = value.toObject();
        const QJsonArray names = item.value("Names").toArray();
        const QString name = names.isEmpty() ? item.value("Name").toString() : names.at(0).toString();
        const QString fallbackName = item.value("Id").toString().left(12);
        const QString state = item.value("State").toString();
        const QString status = item.value("Status").toString();
        const QString image = item.value("Image").toString();
        QString details = QStringLiteral("Image: %1\nStatus: %2").arg(image, status);
        podmanItems.append(makeNode("podman: " + (name.isEmpty() ? fallbackName : name), state, {}, details));
      }
      containerChildren.append(makeNode("Podman", QString::number(array.size()), podmanItems, podmanDetails));
    } else {
      containerChildren.append(makeNode("Podman", "parse error", {}, podmanDetails));
      addError("podman: failed to parse JSON output");
    }
  } else {
    containerChildren.append(makeNode("Podman", "unavailable", {}, podmanDetails));
    containerStatus = "unavailable";
    addError(formatErrorMessage("podman", podman));
  }

  CommandResult distrobox = runCommandWithHostFallback("distrobox", {"list", "--no-color"});
  if (distrobox.usedHostBridge) {
    setHostBridgeUsed(true);
  }
  const QString distroboxDetails = formatCommandDetails(distrobox);
  if (distrobox.exitCode == 0) {
    distroboxOk = true;
    QStringList lines = splitLines(distrobox.stdOut);
    QVariantList distroChildren;
    for (const QString &line : lines) {
      if (line.contains("NAME") && line.contains("STATUS")) {
        continue;
      }
      QStringList parts = splitColumns(line);
      if (parts.isEmpty()) {
        continue;
      }
      const QString name = parts.value(0);
      const QString status = parts.value(1);
      distroChildren.append(makeNode("distrobox: " + name, status, {}, line.trimmed()));
    }
    containerChildren.append(makeNode("Distrobox", QString::number(distroChildren.size()), distroChildren, distroboxDetails));
  } else {
    containerChildren.append(makeNode("Distrobox", "unavailable", {}, distroboxDetails));
    addError(formatErrorMessage("distrobox", distrobox));
  }

  if (podmanOk && distroboxOk) {
    containerStatus = "ok";
  } else if (!podmanOk && !distroboxOk) {
    containerStatus = "unavailable";
  }

  rootChildren.append(makeNode("Containers", containerStatus, containerChildren));

  // Toolboxes
  QVariantList toolboxChildren;
  QString toolboxStatus = QStringLiteral("unavailable");

  CommandResult toolbox = runCommandWithHostFallback("toolbox", {"list", "-c"});
  if (toolbox.usedHostBridge) {
    setHostBridgeUsed(true);
  }
  const QString toolboxDetails = formatCommandDetails(toolbox);
  if (toolbox.exitCode == 0) {
    QStringList lines = splitLines(toolbox.stdOut);
    QVariantList toolboxItems;
    for (const QString &line : lines) {
      if (line.contains("CONTAINER")) {
        continue;
      }
      QStringList parts = splitColumns(line);
      if (parts.isEmpty()) {
        continue;
      }
      const QString name = parts.value(0);
      const QString status = parts.value(1);
      toolboxItems.append(makeNode("toolbox: " + name, status, {}, line.trimmed()));
    }
    toolboxStatus = "ok";
    toolboxChildren.append(makeNode("toolboxes", QString::number(toolboxItems.size()), toolboxItems, toolboxDetails));
  } else {
    toolboxChildren.append(makeNode("toolboxes", "unavailable", {}, toolboxDetails));
    addError(formatErrorMessage("toolbox", toolbox));
  }

  rootChildren.append(makeNode("Toolboxes", toolboxStatus, toolboxChildren));

  QVariantList rows;
  rows.append(makeNode("System", QString(), rootChildren));

  return rows;
}

#include "AuditorData.moc"

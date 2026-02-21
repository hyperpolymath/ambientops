#pragma once

#include <QAbstractListModel>
#include <QObject>
#include <QStringList>
#include <QVariant>

class AuditorData : public QObject {
  Q_OBJECT
  Q_PROPERTY(QAbstractListModel *model READ model NOTIFY modelChanged)
  Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
  Q_PROPERTY(QStringList errors READ errors NOTIFY errorsChanged)
  Q_PROPERTY(bool hostBridgeUsed READ hostBridgeUsed NOTIFY hostBridgeUsedChanged)
  Q_PROPERTY(bool preserveExpanded READ preserveExpanded WRITE setPreserveExpanded NOTIFY preserveExpandedChanged)

public:
  explicit AuditorData(QObject *parent = nullptr);

  QAbstractListModel *model() const;
  bool loading() const;
  QStringList errors() const;
  bool hostBridgeUsed() const;
  bool preserveExpanded() const;
  void setPreserveExpanded(bool preserve);

  Q_INVOKABLE void refresh();

signals:
  void modelChanged();
  void loadingChanged();
  void errorsChanged();
  void hostBridgeUsedChanged();
  void preserveExpandedChanged();

private:
  QAbstractListModel *m_model = nullptr;
  bool m_loading = false;
  QStringList m_errors;
  bool m_hostBridgeUsed = false;
  bool m_preserveExpanded = true;

  QVariantList buildRows(QStringList *errors);
  void buildModelFromRows(const QVariantList &rows);
  void setLoading(bool loading);
  void setErrors(const QStringList &errors);
  void setHostBridgeUsed(bool used);
};

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ApplicationWindow {
  id: window
  width: 980
  height: 640
  visible: true
  title: "Immutable Auditor"

  property string description: "Immutable Auditor - a quick map of where software lives on immutable Fedora systems (Silverblue, Kinoite, etc.)."
  property bool showSelectionFallback: false
  property bool showIcons: true
  property bool showStatusChips: true
  property bool colorBlindMode: false
  property string currentHelp: "Select a node to see context-sensitive help."
  property var defaultPalette: ({
    rowEven: "#1f2429",
    rowOdd: "#20262b",
    selection: "#2c333a",
    chipOk: "#2e7d32",
    chipWarn: "#8d6e63",
    chipNeutral: "#5a5f66"
  })
  property var cbPalette: ({
    rowEven: "#20262b",
    rowOdd: "#1f2429",
    selection: "#2a2f36",
    chipOk: "#1e88e5",
    chipWarn: "#f9a825",
    chipNeutral: "#6b7280"
  })

  function iconFor(location) {
    var lower = location.toLowerCase()
    if (lower.indexOf("root") >= 0 || lower.indexOf("rpm-ostree") >= 0) return "computer"
    if (lower.indexOf("flatpak") >= 0) return "package-x-generic"
    if (lower.indexOf("container") >= 0 || lower.indexOf("podman") >= 0) return "docker"
    if (lower.indexOf("toolbox") >= 0 || lower.indexOf("distrobox") >= 0) return "utilities-terminal"
    return "application-x-executable"
  }

  function statusColor(status) {
    var palette = colorBlindMode ? cbPalette : defaultPalette
    var lower = status.toLowerCase()
    if (lower.indexOf("ok") >= 0 || lower.indexOf("booted") >= 0) return palette.chipOk
    if (lower.indexOf("unavailable") >= 0 || lower.indexOf("unknown") >= 0) return palette.chipNeutral
    if (lower.indexOf("pending") >= 0 || lower.indexOf("staged") >= 0) return palette.chipWarn
    return palette.chipNeutral
  }

  function helpFor(location) {
    var lower = location.toLowerCase()
    if (lower.indexOf("root") >= 0 || lower.indexOf("rpm-ostree") >= 0) {
      return "Root deployments are immutable OS images managed by rpm-ostree. Look for booted, pending, layered packages, and overrides."
    }
    if (lower.indexOf("deployment: current") >= 0) {
      return "The booted deployment is the OS image currently running."
    }
    if (lower.indexOf("deployment: pending") >= 0) {
      return "A pending deployment will apply on next reboot."
    }
    if (lower.indexOf("layered") >= 0) {
      return "Layered packages are RPMs layered on top of the immutable image."
    }
    if (lower.indexOf("flatpak") >= 0) {
      return "Flatpak apps are installed in system or user scopes. System scope is shared across users."
    }
    if (lower.indexOf("container") >= 0 || lower.indexOf("podman") >= 0) {
      return "Containers are managed by Podman or Distrobox and run separately from the host."
    }
    if (lower.indexOf("toolbox") >= 0 || lower.indexOf("distrobox") >= 0) {
      return "Toolboxes and Distroboxes provide mutable dev environments on top of the immutable host."
    }
    return "Select a node to see details about where software lives."
  }

  header: ToolBar {
    RowLayout {
      anchors.fill: parent
      spacing: 12
      Label {
        text: window.title
        font.pixelSize: 20
        Layout.alignment: Qt.AlignVCenter
      }
      Label {
        text: window.description
        opacity: 0.7
        elide: Text.ElideRight
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
      }
      Button {
        text: "Refresh"
        enabled: true
        onClicked: auditorData.refresh()
        ToolTip.visible: hovered
        ToolTip.text: "Reload audit data"
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
      }
      Button {
        text: "Settings"
        onClicked: settingsDrawer.open()
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
      }
      Button {
        text: "Help"
        onClicked: helpDrawer.open()
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
      }
      Button {
        text: "About"
        onClicked: aboutDialog.open()
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 12

    Frame {
      Layout.fillWidth: true
      padding: 12
      Label {
        text: "Click a node to see where software lives and its current state."
        opacity: 0.8
      }
    }

    Frame {
      Layout.fillWidth: true
      visible: auditorData.hostBridgeUsed
      padding: 8
      Label {
        text: "Host bridge enabled: data collected from the host system."
        opacity: 0.7
      }
    }

    Frame {
      Layout.fillWidth: true
      visible: auditorData.errors.length > 0
      padding: 12
      ColumnLayout {
        anchors.fill: parent
        spacing: 6
        Label {
          text: "Missing or failed commands"
          font.pixelSize: 14
        }
        Repeater {
          model: auditorData.errors
          Label {
            text: "- " + modelData
            opacity: 0.9
          }
        }
      }
    }

    SplitView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      orientation: Qt.Horizontal

      Frame {
        padding: 8
        SplitView.preferredWidth: 560

        ColumnLayout {
          anchors.fill: parent
          spacing: 6

          Rectangle {
            Layout.fillWidth: true
            height: 32
            color: "#111111"
            RowLayout {
              anchors.fill: parent
              anchors.margins: 6
              spacing: 8
              Label { text: "Location"; color: "white"; Layout.fillWidth: true }
              Label { text: "Status"; color: "white"; width: 220 }
            }
          }

          ListView {
            id: tree
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: auditorData.model
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: -1
            spacing: 2

            delegate: ItemDelegate {
              width: tree.width
              height: 32
              padding: 0
              onClicked: {
                tree.currentIndex = index
                if (model.details && model.details.length > 0) {
                  detailsArea.text = model.details
                } else if (showSelectionFallback) {
                  detailsArea.text = "Selected: " + model.location
                }
                currentHelp = helpFor(model.location)
              }
              background: Rectangle {
                var palette = colorBlindMode ? cbPalette : defaultPalette
                color: tree.currentIndex === index
                  ? palette.selection
                  : (index % 2 === 0 ? palette.rowEven : palette.rowOdd)
              }
              RowLayout {
                anchors.fill: parent
                spacing: 8
                Item {
                  width: (model.depth || 0) * 18
                }
                Image {
                  visible: showIcons
                  source: "image://theme/" + iconFor(model.location)
                  width: 16
                  height: 16
                  fillMode: Image.PreserveAspectFit
                }
                ToolButton {
                  visible: model.hasChildren
                  text: model.expanded ? "▾" : "▸"
                  onClicked: auditorData.model.toggleExpanded(index)
                }
                Label {
                  text: model.location
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                  font.bold: model.depth === 0
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                  visible: showStatusChips
                  color: statusColor(model.status)
                  radius: 8
                  height: 20
                  width: Math.max(80, statusText.implicitWidth + 16)
                  opacity: 0.9
                  Label {
                    id: statusText
                    anchors.centerIn: parent
                    text: model.status
                    color: "white"
                    font.pixelSize: 12
                  }
                }
                Label {
                  visible: !showStatusChips
                  text: model.status
                  width: 220
                  elide: Text.ElideRight
                  opacity: 0.8
                }
              }
            }

            onCurrentIndexChanged: {
              var item = tree.currentItem
              var details = item && item.model ? (item.model.details || "") : ""
              detailsArea.text = details
            }
          }
        }
      }

    Frame {
      padding: 12
      SplitView.preferredWidth: 360

        ColumnLayout {
          anchors.fill: parent
          spacing: 8
          Label {
            text: "Details"
            font.pixelSize: 16
          }
          TextArea {
            id: detailsArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            readOnly: true
            wrapMode: TextEdit.Wrap
            text: "Select a node to see raw command output and metadata."
          }
        }
      }
    }
  }

  Drawer {
    id: settingsDrawer
    width: 300
    edge: Qt.RightEdge
    modal: false
    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 12
      spacing: 8
      Label { text: "Settings"; font.pixelSize: 16 }
      CheckBox {
        text: "Show selection fallback text"
        checked: showSelectionFallback
        onToggled: showSelectionFallback = checked
      }
      CheckBox {
        text: "Show icons"
        checked: showIcons
        onToggled: showIcons = checked
      }
      CheckBox {
        text: "Show status chips"
        checked: showStatusChips
        onToggled: showStatusChips = checked
      }
      CheckBox {
        text: "Color-blind friendly palette"
        checked: colorBlindMode
        onToggled: colorBlindMode = checked
      }
      CheckBox {
        text: "Preserve expanded state on refresh"
        checked: auditorData.preserveExpanded
        onToggled: auditorData.preserveExpanded = checked
      }
    }
  }

  Drawer {
    id: helpDrawer
    width: 340
    edge: Qt.RightEdge
    modal: false
    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 12
      spacing: 8
      Label { text: "Help"; font.pixelSize: 16 }
      Label {
        text: currentHelp
        wrapMode: Text.WordWrap
      }
      Label {
        text: "For full instructions, see docs/MANUAL.md."
        wrapMode: Text.WordWrap
        opacity: 0.7
      }
    }
  }

  Dialog {
    id: aboutDialog
    title: "About Immutable Auditor"
    modal: true
    standardButtons: Dialog.Ok
    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 12
      spacing: 8
      Label {
        text: "Immutable Auditor"
        font.pixelSize: 18
      }
      Label {
        text: "Auditor UI for immutable Fedora variants (Silverblue, Kinoite, etc.)."
        wrapMode: Text.WordWrap
      }
      Label {
        text: "Shows where software lives: root deployments, Flatpak, containers, and toolboxes."
        wrapMode: Text.WordWrap
        opacity: 0.8
      }
      Label {
        text: "Manual: docs/MANUAL.md"
        opacity: 0.7
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: "#66000000"
    visible: auditorData.loading
    z: 99

    BusyIndicator {
      anchors.centerIn: parent
      running: auditorData.loading
    }
  }
}

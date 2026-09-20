import QtQuick
import Quickshell
import qs.Commons
import "../ioskit"

// Preview sheet for the icon kit. Toggle: omarchy-shell shell toggle ios-bar.icon-preview '{}'
// (see extras/hyprland-preview-rule.lua to make it a floating window).
Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool opened: false
  function open(p) { root.opened = true }
  function close() { root.opened = false }
  function dismiss() { root.opened = false; if (root.shell && root.shell.hide) root.shell.hide("ios-bar.icon-preview") }
  // Save the sheet to a PNG without a screen capture (nothing else on your desktop can end up in it):
  //   omarchy-shell shell call ios-bar.icon-preview snapshot /tmp/icons.png
  function snapshot(path) {
    sheet.grabToImage(function(result) { result.saveToFile(path) })
    return "saving " + path
  }
  function toggle() { if (root.opened) root.dismiss(); else root.open("{}") }

  readonly property var items: [
    { k: "wifi", l: 0.0, s: true, t: "wifi off" }, { k: "wifi", l: 0.2, t: "wifi 1" }, { k: "wifi", l: 0.5, t: "wifi 2" }, { k: "wifi", l: 1.0, t: "wifi 3" },
    { k: "ethernet", t: "ethernet" }, { k: "bluetooth", t: "bt on" }, { k: "bluetooth", s: true, t: "bt off" }, { k: "bluetooth", a: true, t: "bt connected" },
    { k: "volume", l: 0.0, t: "vol 0" }, { k: "volume", l: 0.3, t: "vol 1" }, { k: "volume", l: 0.5, t: "vol 2" }, { k: "volume", l: 1.0, t: "vol 3" },
    { k: "volume", m: true, t: "muted" }, { k: "headphones", t: "headphones" }, { k: "display", t: "display" }, { k: "robot", t: "robot" },
    { k: "chevronLeft", t: "chevron" }, { k: "sun", t: "sun" }, { k: "moon", t: "moon" }, { k: "partlySun", t: "partly sun" },
    { k: "partlyMoon", t: "partly moon" }, { k: "cloud", t: "cloud" }, { k: "rain", t: "rain" }, { k: "storm", t: "storm" },
    { k: "snow", t: "snow" }, { k: "fog", t: "fog" }
  ]

  FloatingWindow {
    visible: root.opened
    title: "iOS icon preview"
    color: Color.background
    implicitWidth: 760
    implicitHeight: 480
    minimumSize: Qt.size(760, 480)
    maximumSize: Qt.size(760, 480)

    Rectangle {
      id: sheet
      anchors.fill: parent
      color: Color.background

    Column {
      anchors.fill: parent
      anchors.margins: 14
      spacing: 10
      Text { text: "enlarged"; color: Color.foreground; font.pixelSize: 12 }
      Grid {
        columns: 9
        spacing: 6
        Repeater {
          model: root.items
          delegate: Item {
            required property var modelData
            width: 78; height: 92
            IosIcon {
              centered: false
              inkTarget: 44
              strokePx: 4.8
              kind: modelData.k
              level: modelData.l !== undefined ? modelData.l : 1
              slashed: !!modelData.s
              muted: !!modelData.m
              color: modelData.a ? Color.accent : Color.foreground
              x: (parent.width - width) / 2
              y: 8 + (56 - height) / 2
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; y: 68; text: modelData.t; color: Color.muted; font.pixelSize: 10 }
          }
        }
      }
      Text { text: "true size (as drawn in the bar)"; color: Color.foreground; font.pixelSize: 12 }
      Flow {
        width: parent.width
        spacing: 16
        Repeater {
          model: root.items
          delegate: Item {
            required property var modelData
            width: 34; height: 30
            IosIcon {
              centered: false
              kind: modelData.k
              level: modelData.l !== undefined ? modelData.l : 1
              slashed: !!modelData.s
              muted: !!modelData.m
              color: modelData.a ? Color.accent : Color.foreground
              x: (parent.width - width) / 2
              y: (parent.height - height) / 2
            }
          }
        }
      }
    }
    }
  }
}

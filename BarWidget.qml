import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "Model.js" as Model

// A deliberately compact companion to omarchy.clock. The count communicates
// that this opens a group of clocks without duplicating the local time label.
BarWidget {
  id: root
  moduleName: "io.github.ptgamr.world-clock"

  // The base widget starts with an empty settings object. Only treat it as
  // authoritative after the bar host has injected the shell.json entry.
  property bool hostSettingsReady: false

  readonly property int locationCount: Model.normalizeLocations(setting("locations", Model.defaultLocations())).length
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // Developer/reviewer aid: capture the real loaded panel without relying on
  // compositor screenshots (which correctly show only the lock screen).
  function capturePreview() {
    if (panelLoader.item && typeof panelLoader.item.capturePreview === "function")
      panelLoader.item.capturePreview()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.settingsReady = root.hostSettingsReady
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    root.hostSettingsReady = true
    root.injectPanel()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.ptgamr.world-clock"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function capturePreview(): void { root.capturePreview() }
    function previewStatus(): string {
      return panelLoader.item ? panelLoader.item.previewStatus : "panel unavailable"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? String(root.locationCount) : "󰥔  " + root.locationCount
    tooltipText: "Open World Clock"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}

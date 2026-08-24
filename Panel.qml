import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.ptgamr.world-clock"
  ipcTarget: "io.github.ptgamr.world-clock"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool settingsReady: false
  readonly property var service: root.bar && root.bar.shell
    && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor(root.moduleName)
    : null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string helperPath: decodeURIComponent(
    String(Qt.resolvedUrl("helpers/timezone.py")).replace(/^file:\/\//, ""))

  readonly property var locations: service
    ? service.locations
    : Model.normalizeLocations(setting("locations", Model.defaultLocations()))
  readonly property var homeLocation: Model.homeLocation(locations)
  readonly property bool showTimezoneAbbreviation: service
    ? service.showTimezoneAbbreviation
    : setting("showTimezoneAbbreviation", true) !== false
  readonly property bool showRelativeOffset: service
    ? service.showRelativeOffset
    : setting("showRelativeOffset", true) !== false
  readonly property bool showAnalogClock: service
    ? service.showAnalogClock
    : setting("showAnalogClock", true) !== false
  readonly property string hourFormat: service
    ? service.hourFormat
    : (setting("hourFormat", "12") === "24" ? "24" : "12")

  readonly property var renderedRows: service ? service.renderedRows : []
  readonly property var calendarData: service
    ? service.calendarData
    : ({ monthLabel: "Loading…", weekNumber: 0, days: [] })
  property string localError: ""
  readonly property string serviceError: localError !== ""
    ? localError
    : (service ? service.errorMessage : "")
  readonly property int plannerOffsetMinutes: service ? service.plannerOffsetMinutes : 0
  readonly property bool followingNow: service ? service.followingNow : true
  readonly property double planningTimestamp: service ? service.planningTimestamp : Date.now()
  readonly property var homeRenderedRow: homeLocation
    ? root.renderedRow(homeLocation.id)
    : null
  readonly property string plannerTooltipText: Model.plannerTooltipLabel(
    homeRenderedRow, hourFormat)
  readonly property bool dateShiftBusy: service ? service.dateShiftBusy : false
  readonly property int displaySecond: followingNow
    ? secondsClock.seconds
    : new Date(planningTimestamp).getUTCSeconds()

  property bool showingSettings: false
  property bool addingLocation: false
  property string renamingId: ""
  readonly property bool editorOpen: addingLocation || renamingId !== ""
  readonly property bool showingClockContent: !addingLocation && !showingSettings
  property int selectedIndex: -1
  property bool cursorActive: false
  property int settingsIndex: 0
  property bool settingsCursorActive: false
  property bool reorderAnimating: false
  property int reorderFrom: -1
  property int reorderTo: -1
  property var reorderedLocations: []
  property bool dragReordering: false
  property int dragFrom: -1
  property int dragTo: -1
  property real dragOffset: 0
  readonly property bool reorderBusy: reorderAnimating || dragReordering
  readonly property int reorderDuration: 180
  readonly property int dragDisplaceDuration: 110
  property bool locationHoverSuppressed: false
  property point lastLocationPointer: Qt.point(Number.NaN, Number.NaN)
  readonly property real pointerMovementThreshold: 0.5

  property var timezoneSuggestions: []
  property int suggestionIndex: 0
  property string chosenTimezone: ""
  property string chosenTimezoneName: ""
  property var chosenLatitude: null
  property var chosenLongitude: null
  property string pendingSearchQuery: ""
  property string activeSearchQuery: ""
  property bool assigningSuggestion: false

  readonly property string previewPath: "/tmp/omarchy-world-clock-preview.png"
  readonly property bool previewCaptureRequested: setting("_capturePreview", false) === true
  property string previewStatus: "idle"

  function open() {
    if (root.followingNow) root.resetToNow()
    else root.requestRender()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) root.setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    root.setCenterHoverRevealSuppressed(false)
    root.locationHoverSuppressed = false
    root.lastLocationPointer = Qt.point(Number.NaN, Number.NaN)
    root.cancelEditors()
    root.showingSettings = false
    root.settingsCursorActive = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function openFullView() {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.summon !== "function") return
    root.close()
    root.bar.shell.summon(root.moduleName, JSON.stringify({ source: "compact" }))
  }

  function resetToNow() {
    if (root.service) root.service.resetToNow()
  }

  function setPlannerOffset(minutes) {
    if (root.service) root.service.setPlannerOffset(minutes)
  }

  function stepPlanner(direction, largeStep) {
    if (root.service) root.service.stepPlanner(direction, largeStep)
  }

  function shiftPlanningDate(days) {
    if (root.service) root.service.shiftPlanningDate(days)
  }

  function requestRender() {
    if (root.service) root.service.requestRender()
  }

  function selectedLocation() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.locations.length) return null
    return root.locations[root.selectedIndex]
  }

  function revealSelection() {
    if (root.selectedIndex < 0 || !clockRepeater) return
    Qt.callLater(function() {
      var item = clockRepeater.itemAt(root.selectedIndex)
      root.revealItem(item)
    })
  }

  function revealItem(item) {
    if (!item || !scroll || !contentColumn) return
    var point = item.mapToItem(contentColumn, 0, 0)
    var margin = Style.space(8)
    var top = Math.max(0, point.y - margin)
    var bottom = point.y + item.height + margin
    var maximum = Math.max(0, scroll.contentHeight - scroll.height)
    if (top < scroll.contentY) scroll.contentY = Math.min(maximum, top)
    else if (bottom > scroll.contentY + scroll.height)
      scroll.contentY = Math.max(0, Math.min(maximum, bottom - scroll.height))
  }

  function selectLocation(index) {
    root.selectedIndex = Model.clampedIndex(index, root.locations.length)
    root.cursorActive = root.selectedIndex >= 0
    root.revealSelection()
  }

  function suppressLocationHover() {
    root.locationHoverSuppressed = true
  }

  function locationAtPointer(position) {
    if (!clockRepeater || !position) return -1
    for (var index = 0; index < root.locations.length; index++) {
      var item = clockRepeater.itemAt(index)
      if (!item || !item.visible) continue
      var local = item.mapFromItem(keyCatcher, position.x, position.y)
      if (local.x >= 0 && local.x <= item.width && local.y >= 0 && local.y <= item.height)
        return index
    }
    return -1
  }

  function trackLocationPointer(position) {
    if (!position) return false
    var moved = Model.pointerMoved(
      root.lastLocationPointer.x, root.lastLocationPointer.y,
      position.x, position.y, root.pointerMovementThreshold)
    root.lastLocationPointer = Qt.point(position.x, position.y)
    if (!root.locationHoverSuppressed || !moved) return moved
    root.locationHoverSuppressed = false
    var index = root.locationAtPointer(position)
    if (index >= 0) root.selectLocation(index)
    return moved
  }

  function handleLocationPointer(index, item, mouseArea) {
    var position = item.mapToItem(keyCatcher, mouseArea.mouseX, mouseArea.mouseY)
    var moved = root.trackLocationPointer(position)
    if (root.locationHoverSuppressed && !moved) return
    root.locationHoverSuppressed = false
    root.selectLocation(index)
  }

  function clickLocation(index, item, mouseArea) {
    var position = item.mapToItem(keyCatcher, mouseArea.mouseX, mouseArea.mouseY)
    root.lastLocationPointer = Qt.point(position.x, position.y)
    root.locationHoverSuppressed = false
    root.selectLocation(index)
  }

  function moveSelection(delta) {
    if (root.editorOpen || root.reorderBusy || root.locations.length === 0) return
    root.suppressLocationHover()
    root.selectedIndex = Model.movedSelection(
      root.selectedIndex, root.locations.length, delta, root.cursorActive)
    root.cursorActive = true
    root.revealSelection()
  }

  function selectLocationBoundary(last) {
    if (root.editorOpen || root.reorderBusy || root.locations.length === 0) return
    root.suppressLocationHover()
    root.selectLocation(last ? root.locations.length - 1 : 0)
  }

  function toggleSettings() {
    root.cancelEditors()
    root.showingSettings = !root.showingSettings
    root.settingsIndex = 0
    root.settingsCursorActive = root.showingSettings
  }

  function ensureSelectedLocation() {
    if (root.locations.length === 0) return null
    if (!root.cursorActive)
      root.selectLocation(root.selectedIndex >= 0 ? root.selectedIndex : 0)
    return root.selectedLocation()
  }

  function markSelectedHome() {
    var location = root.ensureSelectedLocation()
    if (location && !location.isHome) root.setHomeLocation(location.id)
  }

  function startRenameSelected() {
    var location = root.ensureSelectedLocation()
    if (location) root.startRename(location.id, location.name)
  }

  function removeSelectedLocation() {
    var location = root.ensureSelectedLocation()
    if (location && root.locations.length > 1)
      root.removeLocation(location.id)
  }

  function moveSettingsSelection(delta) {
    root.settingsIndex = Model.clampedIndex(root.settingsIndex + delta, 2)
    root.settingsCursorActive = true
  }

  function selectSetting(index) {
    root.settingsIndex = Model.clampedIndex(index, 2)
    root.settingsCursorActive = true
  }

  function setAnalogClocks(value) {
    root.persistSetting("showAnalogClock", value)
  }

  function setHourFormat(value) {
    root.persistSetting("hourFormat", value === "24" ? "24" : "12")
  }

  function adjustSelectedSetting(direction) {
    if (root.settingsIndex === 0) root.setAnalogClocks(direction > 0)
    else root.setHourFormat(direction > 0 ? "24" : "12")
  }

  function activateSelectedSetting() {
    if (root.settingsIndex === 0) root.setAnalogClocks(!root.showAnalogClock)
    else root.setHourFormat(root.hourFormat === "12" ? "24" : "12")
  }

  function activateKeyboardSelection() {
    if (root.showingSettings) {
      root.activateSelectedSetting()
      return true
    }
    return false
  }

  function shortcutHint() {
    if (root.addingLocation)
      return "Type to search · ↑/↓ choose · Enter select/add · Esc cancel"
    if (root.renamingId !== "")
      return "Type a new name · Enter save · Esc cancel"
    if (root.showingSettings)
      return "j/k · ←/→ change · Enter apply · a analog · 1/2 format · s done"
    return "j/k select · J/K reorder · ←/→ time · T now · A add · R rename · D delete · H home · S settings"
  }

  function clockRowStep(index) {
    var item = clockRepeater ? clockRepeater.itemAt(index) : null
    return (item ? item.height : Style.space(64)) + clocks.spacing
  }

  function animatedRowOffset(index) {
    var source = root.dragReordering ? root.dragFrom : root.reorderFrom
    var target = root.dragReordering ? root.dragTo : root.reorderTo
    return Model.reorderOffset(index, source, target, root.clockRowStep(source))
  }

  function animateLocationMove(from, to) {
    if (root.editorOpen || root.reorderBusy || from < 0 || from >= root.locations.length) return
    var target = Model.clampedIndex(to, root.locations.length)
    if (target < 0 || from === target) return
    root.suppressLocationHover()
    var source = root.locations[from]
    root.reorderedLocations = Model.moveLocation(root.locations, source.id, target - from)
    root.cursorActive = true
    // Arm Behaviors before changing the offsets, matching Omamux's reorder
    // sequence so the source and displaced rows animate instead of jumping.
    root.reorderAnimating = true
    root.reorderFrom = from
    root.reorderTo = target
    reorderTimer.restart()
  }

  function finishReorder() {
    if (!root.reorderAnimating) return
    var target = root.reorderTo
    var next = root.reorderedLocations
    root.reorderAnimating = false
    root.reorderFrom = -1
    root.reorderTo = -1
    root.reorderedLocations = []
    root.selectedIndex = target
    root.persistLocations(next)
    root.revealSelection()
  }

  function moveSelectedLocation(delta) {
    if (!root.cursorActive) {
      root.moveSelection(delta)
      return
    }
    root.animateLocationMove(root.selectedIndex, root.selectedIndex + delta)
  }

  function beginDrag(index) {
    if (root.editorOpen || root.reorderAnimating || root.locations.length < 2
        || index < 0 || index >= root.locations.length) return false
    root.dragFrom = index
    root.dragTo = index
    root.dragOffset = 0
    root.dragReordering = true
    root.selectLocation(index)
    return true
  }

  function updateDrag(offset) {
    if (!root.dragReordering) return
    root.dragOffset = Number(offset || 0)
    var target = root.dragFrom + Math.round(root.dragOffset / root.clockRowStep(root.dragFrom))
    root.dragTo = Model.clampedIndex(target, root.locations.length)
  }

  function finishDrag() {
    if (!root.dragReordering) return
    var from = root.dragFrom
    var target = root.dragTo
    root.dragReordering = false
    root.dragFrom = -1
    root.dragTo = -1
    root.dragOffset = 0
    if (from === target) return
    var source = root.locations[from]
    root.selectedIndex = target
    root.persistLocations(Model.moveLocation(root.locations, source.id, target - from))
    root.revealSelection()
  }

  function renderedRow(id) {
    return root.service ? root.service.renderedRow(id) : null
  }

  function availabilityFor(row) {
    if (!row) return { key: "off", label: "…" }
    return Model.availability(row.hour, row.minute, row.isWeekend)
  }

  function availabilityColor(status) {
    if (!status) return Color.muted
    if (status.key === "work")
      return Style.selectedStateColor(root.contentForeground, Color.accent, Color.urgent)
    if (status.key === "edge") return Color.muted
    return Color.urgent
  }

  function persistLocations(nextLocations) {
    if (root.service) {
      root.service.persistLocations(nextLocations)
      return
    }
    var entry = { id: root.moduleName }
    for (var existing in root.settings)
      if (existing !== "id") entry[existing] = root.settings[existing]
    entry.locations = Model.normalizeLocations(nextLocations)

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    root.requestRender()
  }

  function persistSetting(key, value) {
    if (root.service) {
      root.service.persistSetting(key, value)
      return
    }
    var entry = { id: root.moduleName }
    for (var existing in root.settings)
      if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function removeLocation(id) {
    root.persistLocations(Model.removeLocation(root.locations, id))
  }

  function moveLocation(id, delta) {
    for (var i = 0; i < root.locations.length; i++) {
      if (root.locations[i].id !== id) continue
      root.animateLocationMove(i, i + delta)
      return
    }
  }

  function setHomeLocation(id) {
    root.persistLocations(Model.setHomeLocation(root.locations, id))
  }

  onLocationsChanged: {
    root.selectedIndex = Model.clampedIndex(root.selectedIndex, root.locations.length)
    if (root.cursorActive) root.revealSelection()
  }

  function startRename(id, name) {
    root.addingLocation = false
    root.renamingId = id
    Qt.callLater(function() {
      renameField.text = name
      renameField.selectAll()
      renameField.forceActiveFocus()
      root.revealItem(renameEditor)
    })
  }

  function commitRename() {
    if (root.renamingId === "") return
    var next = Model.renameLocation(root.locations, root.renamingId, renameField.text)
    root.persistLocations(next)
    root.renamingId = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function startAddingLocation() {
    root.renamingId = ""
    root.addingLocation = true
    root.localError = ""
    root.chosenTimezone = ""
    root.chosenTimezoneName = ""
    root.chosenLatitude = null
    root.chosenLongitude = null
    root.timezoneSuggestions = []
    root.suggestionIndex = 0
    Qt.callLater(function() {
      nameField.text = ""
      timezoneField.text = ""
      timezoneField.forceActiveFocus()
      root.requestTimezoneSearch("")
      root.revealItem(addEditor)
    })
  }

  function cancelEditors() {
    root.addingLocation = false
    root.renamingId = ""
    root.timezoneSuggestions = []
    root.localError = ""
    searchDebounce.stop()
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function requestTimezoneSearch(query) {
    root.pendingSearchQuery = String(query || "")
    searchDebounce.restart()
  }

  function startTimezoneSearch() {
    if (searchProcess.running) return
    root.activeSearchQuery = root.pendingSearchQuery
    searchProcess.command = [
      "python3",
      root.helperPath,
      "search",
      root.activeSearchQuery,
      "--limit",
      "6"
    ]
    searchProcess.running = true
  }

  function chooseSuggestion(suggestion) {
    if (!suggestion) return
    root.assigningSuggestion = true
    timezoneField.text = suggestion.timezone
    root.assigningSuggestion = false
    root.chosenTimezone = suggestion.timezone
    root.chosenTimezoneName = suggestion.name
    root.chosenLatitude = suggestion.latitude === undefined ? null : suggestion.latitude
    root.chosenLongitude = suggestion.longitude === undefined ? null : suggestion.longitude
    root.timezoneSuggestions = []
    if (String(nameField.text || "").trim() === "") nameField.text = suggestion.name
    nameField.forceActiveFocus()
  }

  function commitAddLocation() {
    var timezone = root.chosenTimezone
    var defaultName = root.chosenTimezoneName
    var latitude = root.chosenLatitude
    var longitude = root.chosenLongitude
    if (timezone === "" && root.timezoneSuggestions.length > 0) {
      var selected = root.timezoneSuggestions[Math.max(
        0, Math.min(root.suggestionIndex, root.timezoneSuggestions.length - 1))]
      timezone = selected.timezone
      defaultName = selected.name
      latitude = selected.latitude === undefined ? null : selected.latitude
      longitude = selected.longitude === undefined ? null : selected.longitude
    }
    if (timezone === "") {
      root.localError = "Choose a timezone from the search results."
      return
    }

    var name = String(nameField.text || "").trim() || defaultName
    var next = Model.addLocation(root.locations, name, timezone, latitude, longitude)
    root.persistLocations(next)
    root.addingLocation = false
    root.selectedIndex = next.length - 1
    root.cursorActive = true
    root.timezoneSuggestions = []
    root.localError = ""
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      root.revealSelection()
    })
  }

  function capturePreview() {
    root.previewStatus = "opening"
    if (!root.opened) root.open()
    previewCaptureTimer.restart()
  }

  function writePreview() {
    var previewWidth = Math.max(1, Math.ceil(keyCatcher.width))
    var previewHeight = Math.max(1, Math.ceil(keyCatcher.height))
    root.previewStatus = "capturing " + previewWidth + "x" + previewHeight
      + " opened=" + root.opened + " visible=" + keyCatcher.visible
    keyCatcher.grabToImage(function(result) {
      if (!result || !result.saveToFile(root.previewPath)) {
        root.previewStatus = "save failed"
        root.localError = "Could not save the panel preview."
      } else {
        root.previewStatus = "saved " + root.previewPath
      }
    }, Qt.size(previewWidth, previewHeight))
  }

  onPreviewCaptureRequestedChanged: {
    if (root.previewCaptureRequested) root.capturePreview()
  }

  SystemClock {
    id: secondsClock
    enabled: root.opened && root.showAnalogClock
    precision: SystemClock.Seconds
  }

  Process {
    id: searchProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!root.addingLocation || raw === "") return
        try {
          var result = JSON.parse(raw)
          if (Array.isArray(result) && root.activeSearchQuery === root.pendingSearchQuery) {
            root.timezoneSuggestions = result
            root.suggestionIndex = 0
            Qt.callLater(function() { root.revealItem(addEditor) })
          }
        } catch (error) {
          root.timezoneSuggestions = []
        }
      }
    }
    onExited: {
      if (root.addingLocation && root.activeSearchQuery !== root.pendingSearchQuery)
        Qt.callLater(root.startTimezoneSearch)
    }
  }

  Timer {
    id: searchDebounce
    interval: 140
    onTriggered: root.startTimezoneSearch()
  }

  Timer {
    id: reorderTimer
    interval: root.reorderDuration
    onTriggered: root.finishReorder()
  }

  Timer {
    id: previewCaptureTimer
    interval: 600
    onTriggered: root.writePreview()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(
      fixedHeader.implicitHeight + contentColumn.implicitHeight
        + shortcutFooter.implicitHeight + Style.space(20),
      Style.space(760))

    Rectangle {
      id: keyCatcher
      anchors.fill: parent
      color: Color.popups.background
      focus: true

      HoverHandler {
        onPointChanged: root.trackLocationPointer(point.position)
      }

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.editorOpen) return
        if (event.key === Qt.Key_Escape) {
          if (root.showingSettings) {
            root.showingSettings = false
          } else {
            root.close()
          }
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          if (root.showingSettings) root.adjustSelectedSetting(-1)
          else root.stepPlanner(-1, !!(event.modifiers & Qt.ShiftModifier))
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          if (root.showingSettings) root.adjustSelectedSetting(1)
          else root.stepPlanner(1, !!(event.modifiers & Qt.ShiftModifier))
          event.accepted = true
        } else if (event.key === Qt.Key_Down || event.text === "j") {
          if (root.showingSettings) root.moveSettingsSelection(1)
          else root.moveSelection(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up || event.text === "k") {
          if (root.showingSettings) root.moveSettingsSelection(-1)
          else root.moveSelection(-1)
          event.accepted = true
        } else if (!root.showingSettings && event.key === Qt.Key_Home) {
          root.selectLocationBoundary(false)
          event.accepted = true
        } else if (!root.showingSettings && event.key === Qt.Key_End) {
          root.selectLocationBoundary(true)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space) {
          if (root.activateKeyboardSelection()) event.accepted = true
        } else if (!root.showingSettings && event.text === "J") {
          root.moveSelectedLocation(1)
          event.accepted = true
        } else if (!root.showingSettings && event.text === "K") {
          root.moveSelectedLocation(-1)
          event.accepted = true
        } else if (event.text === "s" || event.text === "S") {
          root.toggleSettings()
          event.accepted = true
        } else if (!root.showingSettings && (event.text === "h" || event.text === "H")) {
          root.markSelectedHome()
          event.accepted = true
        } else if (!root.showingSettings && (event.text === "r" || event.text === "R")) {
          root.startRenameSelected()
          event.accepted = true
        } else if (!root.showingSettings && (event.key === Qt.Key_Delete
            || event.text === "d" || event.text === "D"
            || event.text === "x" || event.text === "X")) {
          root.removeSelectedLocation()
          event.accepted = true
        } else if (event.text === "a" || event.text === "A") {
          if (root.showingSettings) {
            root.selectSetting(0)
            root.setAnalogClocks(!root.showAnalogClock)
          } else root.startAddingLocation()
          event.accepted = true
        } else if (root.showingSettings && event.text === "1") {
          root.selectSetting(1)
          root.setHourFormat("12")
          event.accepted = true
        } else if (root.showingSettings && event.text === "2") {
          root.selectSetting(1)
          root.setHourFormat("24")
          event.accepted = true
        } else if (event.text === "[" || event.text === "{") {
          root.shiftPlanningDate(event.text === "{" ? -7 : -1)
          event.accepted = true
        } else if (event.text === "]" || event.text === "}") {
          root.shiftPlanningDate(event.text === "}" ? 7 : 1)
          event.accepted = true
        } else if (event.text === "t" || event.text === "T") {
          root.resetToNow()
          event.accepted = true
        }
      }

      Column {
        id: fixedHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: implicitHeight
        spacing: Style.space(10)

          Item {
            width: parent.width
            height: Math.max(monthTitle.implicitHeight, calendarControls.implicitHeight)

            Text {
              id: monthTitle
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.calendarData.monthLabel || "Loading…"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Row {
              id: calendarControls
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Button {
                text: "‹"
                enabled: !root.dateShiftBusy
                opacity: enabled ? 1 : 0.35
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.title
                horizontalPadding: Style.space(7)
                verticalPadding: Style.space(3)
                onClicked: root.shiftPlanningDate(-7)
              }

              Button {
                text: "Today"
                selected: root.followingNow
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(9)
                verticalPadding: Style.space(5)
                onClicked: root.resetToNow()
              }

              Button {
                text: "›"
                enabled: !root.dateShiftBusy
                opacity: enabled ? 1 : 0.35
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.title
                horizontalPadding: Style.space(7)
                verticalPadding: Style.space(3)
                onClicked: root.shiftPlanningDate(7)
              }
            }
          }

          Row {
            id: calendarWeek
            width: parent.width
            height: Style.space(46)

            Column {
              width: Style.space(42)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "CW"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: String(root.calendarData.weekNumber || "")
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Repeater {
              model: root.calendarData.days || []

              Item {
                id: calendarDay
                required property var modelData
                width: (calendarWeek.width - Style.space(42)) / 7
                height: calendarWeek.height

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(3)

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: calendarDay.modelData.weekday
                    color: calendarDay.modelData.isAdjacentMonth
                      ? Qt.darker(root.contentForeground, 1.8)
                      : Qt.darker(root.contentForeground, 1.35)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Rectangle {
                    width: Style.space(26)
                    height: Style.space(24)
                    radius: Style.cornerRadius
                    color: calendarDay.modelData.isSelected ? Color.accent : "transparent"

                    Text {
                      anchors.centerIn: parent
                      text: String(calendarDay.modelData.day)
                      color: calendarDay.modelData.isSelected
                        ? Color.popups.background
                        : calendarDay.modelData.isAdjacentMonth
                          ? Qt.darker(root.contentForeground, 1.8)
                          : root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      font.bold: calendarDay.modelData.isSelected
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: !root.dateShiftBusy
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (calendarDay.modelData.offsetDays !== 0)
                      root.shiftPlanningDate(calendarDay.modelData.offsetDays)
                  }
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.contentForeground
            opacity: 0.14
          }

          Item {
            width: parent.width
            height: Math.max(worldClockTitle.implicitHeight, headerActions.implicitHeight)

            Text {
              id: worldClockTitle
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "WORLD CLOCK"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              font.letterSpacing: 1
            }

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Button {
                text: root.showingSettings ? "Done" : "Settings"
                selected: root.showingSettings
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(9)
                verticalPadding: Style.space(5)
                onClicked: {
                  root.toggleSettings()
                }
              }

            }
          }

      }

      Flickable {
        id: scroll
        anchors.top: fixedHeader.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: shortcutFooter.top
        anchors.bottomMargin: Style.space(8)
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: scroll.width
          spacing: Style.space(10)

          Rectangle {
            visible: root.showingSettings
            width: parent.width
            implicitHeight: appearanceSettings.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.contentForeground, Color.accent, Color.urgent)

            Column {
              id: appearanceSettings
              x: Style.space(10)
              y: Style.space(9)
              width: parent.width - Style.space(20)
              spacing: Style.space(8)

              Text {
                text: "APPEARANCE"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                font.letterSpacing: 1
              }

              CursorSurface {
                id: analogSettingRow
                width: parent.width
                height: Math.max(analogSettingLabel.implicitHeight, analogSetting.implicitHeight)
                  + Style.space(8)
                hasCursor: root.showingSettings && root.settingsCursorActive
                  && root.settingsIndex === 0
                foreground: root.contentForeground
                accent: Color.accent

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: root.selectSetting(0)
                }

                Text {
                  id: analogSettingLabel
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Analog clocks"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }

                ToggleSwitch {
                  id: analogSetting
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  checked: root.showAnalogClock
                  rounded: false
                  foreground: root.contentForeground
                  accent: Color.accent
                  onToggled: root.setAnalogClocks(!checked)
                }
              }

              CursorSurface {
                id: hourFormatSettingRow
                width: parent.width
                height: Math.max(hourFormatLabel.implicitHeight, hourFormatButtons.implicitHeight)
                  + Style.space(8)
                hasCursor: root.showingSettings && root.settingsCursorActive
                  && root.settingsIndex === 1
                foreground: root.contentForeground
                accent: Color.accent

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: root.selectSetting(1)
                }

                Text {
                  id: hourFormatLabel
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Hour format"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }

                Row {
                  id: hourFormatButtons
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  Button {
                    text: "12 hour"
                    selected: root.hourFormat === "12"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(4)
                    onClicked: root.setHourFormat("12")
                  }

                  Button {
                    text: "24 hour"
                    selected: root.hourFormat === "24"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(4)
                    onClicked: root.setHourFormat("24")
                  }
                }
              }
            }
          }

          Text {
            visible: root.serviceError !== ""
            width: parent.width
            text: root.serviceError
            color: Color.urgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            id: clocks
            visible: root.showingClockContent
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              id: clockRepeater
              model: root.locations

              CursorSurface {
                id: clockCard
                required property var modelData
                required property int index
                readonly property var rendered: root.renderedRow(modelData.id)
                readonly property var availability: root.availabilityFor(rendered)
                property real animatedOffset: root.animatedRowOffset(index)

                width: clocks.width
                implicitHeight: rowContent.implicitHeight + Style.space(18)
                hasCursor: root.cursorActive && index === root.selectedIndex
                current: modelData.isHome
                foreground: root.contentForeground
                accent: Color.accent
                z: dragHandler.active || (root.reorderAnimating && index === root.reorderFrom)
                  ? 2 : 1
                transform: Translate {
                  y: dragHandler.active ? dragHandler.translation.y : clockCard.animatedOffset
                }

                Behavior on animatedOffset {
                  enabled: root.reorderBusy && !dragHandler.active
                  NumberAnimation {
                    duration: root.dragReordering
                      ? root.dragDisplaceDuration
                      : root.reorderDuration
                    easing.type: Easing.OutCubic
                  }
                }

                MouseArea {
                  id: clockMouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !root.reorderAnimating
                  cursorShape: root.locations.length > 1 ? Qt.OpenHandCursor : Qt.ArrowCursor
                  onEntered: root.handleLocationPointer(
                    clockCard.index, clockCard, clockMouseArea)
                  onPositionChanged: root.handleLocationPointer(
                    clockCard.index, clockCard, clockMouseArea)
                  onClicked: root.clickLocation(
                    clockCard.index, clockCard, clockMouseArea)
                }

                DragHandler {
                  id: dragHandler
                  target: null
                  enabled: root.locations.length > 1
                    && !root.editorOpen
                    && !root.reorderAnimating
                  xAxis.enabled: false
                  onTranslationChanged: root.updateDrag(translation.y)
                  onActiveChanged: {
                    if (active) root.beginDrag(clockCard.index)
                    else root.finishDrag()
                  }
                }

                Column {
                  id: rowContent
                  x: Style.space(12)
                  y: Style.space(9)
                  width: parent.width - Style.space(24)
                  spacing: Style.space(6)

                  Item {
                    width: parent.width
                    height: Math.max(analogClock.height,
                      locationBlock.implicitHeight, timeBlock.implicitHeight)

                    Column {
                      id: locationBlock
                      anchors.left: parent.left
                      anchors.right: analogClock.left
                      anchors.rightMargin: Style.space(12)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(2)

                      Row {
                        spacing: Style.space(7)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: clockCard.modelData.name
                          color: root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.title
                          font.bold: true
                        }

                        Rectangle {
                          visible: clockCard.modelData.isHome
                          width: homeBadgeText.implicitWidth + Style.space(12)
                          height: homeBadgeText.implicitHeight + Style.space(6)
                          radius: Style.space(2)
                          color: Style.normalFillFor(root.contentForeground, Color.accent, Color.urgent)
                          border.width: Style.spacing.hairline
                          border.color: Style.normalBorderFor(
                            root.contentForeground, Color.accent, Color.urgent)

                          Text {
                            id: homeBadgeText
                            anchors.centerIn: parent
                            text: "HOME"
                            color: root.contentForeground
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                            font.letterSpacing: 1
                          }
                        }
                      }

                      Text {
                        text: clockCard.rendered ? clockCard.rendered.weekday : "Loading…"
                        color: Qt.darker(root.contentForeground, 1.35)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }

                    AnalogClock {
                      id: analogClock
                      visible: root.showAnalogClock
                      width: visible ? implicitWidth : 0
                      height: visible ? implicitHeight : 0
                      anchors.right: timeBlock.left
                      anchors.rightMargin: visible ? Style.space(18) : 0
                      anchors.verticalCenter: parent.verticalCenter
                      hour: clockCard.rendered ? clockCard.rendered.hour : 0
                      minute: clockCard.rendered ? clockCard.rendered.minute : 0
                      second: root.displaySecond
                      foreground: root.contentForeground
                      background: Color.popups.background
                      accent: Color.accent
                      secondHandColor: Color.urgent
                      opacity: clockCard.rendered ? 1 : 0.4
                    }

                    Column {
                      id: timeBlock
                      width: Style.space(112)
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(1)

                      Row {
                        anchors.right: parent.right
                        spacing: Style.space(4)

                        Text {
                          id: localTimeText
                          text: clockCard.rendered
                            ? (root.hourFormat === "24"
                                ? clockCard.rendered.time : clockCard.rendered.time12)
                            : "--:--"
                          color: root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.iconLarge
                          font.bold: true
                        }

                        Text {
                          visible: root.hourFormat === "12"
                          anchors.baseline: localTimeText.baseline
                          text: clockCard.rendered ? clockCard.rendered.period : ""
                          color: root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                      }

                      Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: clockCard.rendered
                          ? Model.metadataForRow(clockCard.rendered,
                              root.showTimezoneAbbreviation, root.showRelativeOffset, false)
                          : clockCard.modelData.timezone
                        color: Qt.darker(root.contentForeground, 1.35)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideLeft
                      }
                    }
                  }

                }
              }
            }
          }

          Rectangle {
            id: renameEditor
            visible: root.renamingId !== ""
            width: parent.width
            implicitHeight: renameContent.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.contentForeground, Color.accent, Color.urgent)

            Column {
              id: renameContent
              x: Style.space(10)
              y: Style.space(9)
              width: parent.width - Style.space(20)
              spacing: Style.space(7)

              Text {
                text: "RENAME LOCATION"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                font.letterSpacing: 1
              }

              Row {
                spacing: Style.space(6)

                TextField {
                  id: renameField
                  width: renameContent.width - saveRename.implicitWidth - cancelRename.implicitWidth - Style.space(12)
                  foreground: root.contentForeground
                  placeholderText: "Display name"
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      root.cancelEditors()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.commitRename()
                      event.accepted = true
                    }
                  }
                }

                Button {
                  id: saveRename
                  text: "Save"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.commitRename()
                }

                Button {
                  id: cancelRename
                  text: "Cancel"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.cancelEditors()
                }
              }
            }
          }

          Rectangle {
            id: addEditor
            visible: root.addingLocation
            width: parent.width
            implicitHeight: addContent.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.contentForeground, Color.accent, Color.urgent)

            Column {
              id: addContent
              x: Style.space(10)
              y: Style.space(9)
              width: parent.width - Style.space(20)
              spacing: Style.space(7)

              Text {
                text: "ADD LOCATION"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                font.letterSpacing: 1
              }

              Row {
                spacing: Style.space(6)

                TextField {
                  id: timezoneField
                  width: (addContent.width - Style.space(6)) * 0.58
                  foreground: root.contentForeground
                  placeholderText: "Search city or IANA timezone"
                  onTextChanged: {
                    if (root.assigningSuggestion) return
                    root.chosenTimezone = ""
                    root.chosenTimezoneName = ""
                    root.chosenLatitude = null
                    root.chosenLongitude = null
                    root.requestTimezoneSearch(text)
                  }
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      root.cancelEditors()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                      if (root.suggestionIndex < root.timezoneSuggestions.length - 1)
                        root.suggestionIndex++
                      event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                      if (root.suggestionIndex > 0) root.suggestionIndex--
                      event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      if (root.timezoneSuggestions.length > 0)
                        root.chooseSuggestion(root.timezoneSuggestions[root.suggestionIndex])
                      event.accepted = true
                    }
                  }
                }

                TextField {
                  id: nameField
                  width: (addContent.width - Style.space(6)) * 0.42
                  foreground: root.contentForeground
                  placeholderText: "Alias"
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      root.cancelEditors()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.commitAddLocation()
                      event.accepted = true
                    }
                  }
                }
              }

              Column {
                visible: root.timezoneSuggestions.length > 0
                width: parent.width
                spacing: 0

                Repeater {
                  model: root.timezoneSuggestions

                  Rectangle {
                    required property var modelData
                    required property int index
                    width: addContent.width
                    height: suggestionText.implicitHeight + Style.space(10)
                    radius: Style.cornerRadius
                    color: index === root.suggestionIndex
                      ? Style.hoverFillFor(root.contentForeground, Color.accent, Color.urgent)
                      : "transparent"

                    Row {
                      id: suggestionText
                      x: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(8)

                      Text {
                        text: modelData.name
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                      }

                      Text {
                        text: modelData.timezone
                        color: Qt.darker(root.contentForeground, 1.5)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        visible: modelData.country !== ""
                        text: "· " + modelData.country
                        color: Qt.darker(root.contentForeground, 1.7)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onPositionChanged: root.suggestionIndex = index
                      onClicked: root.chooseSuggestion(modelData)
                    }
                  }
                }
              }

              Row {
                spacing: Style.space(6)

                Button {
                  text: "Add"
                  enabled: root.chosenTimezone !== "" || root.timezoneSuggestions.length > 0
                  opacity: enabled ? 1 : 0.35
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.commitAddLocation()
                }

                Button {
                  text: "Cancel"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.cancelEditors()
                }
              }
            }
          }

        }
      }

      Column {
        id: shortcutFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: implicitHeight
        spacing: Style.space(7)

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: root.contentForeground
          opacity: 0.14
        }

        Item {
          id: plannerDock
          width: parent.width
          height: Style.space(24)
          readonly property real thumbCenterX: plannerSlider.x
            + plannerSlider.width * plannerSlider.progress

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "−24h"
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSlider {
            id: plannerSlider
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(42)
            anchors.rightMargin: Style.space(42)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(18)
            bar: root.bar
            minimum: -96
            maximum: 96
            value: root.plannerOffsetMinutes / 15
            step: 1
            integer: true
            tickCount: 9
            trackHeight: Style.space(3)
            knobSize: 0
            fillColor: trackColor
            onMoved: function(next) { root.setPlannerOffset(Math.round(next) * 15) }
            onReleased: function(next) { root.setPlannerOffset(Math.round(next) * 15) }
            onRightClicked: root.resetToNow()
          }

          Rectangle {
            width: Style.space(10)
            height: width
            radius: 0
            x: Math.max(plannerSlider.x, Math.min(
              plannerSlider.x + plannerSlider.width - width,
              plannerDock.thumbCenterX - width / 2))
            anchors.verticalCenter: plannerSlider.verticalCenter
            color: root.contentForeground
            border.width: Style.spacing.hairline
            border.color: Color.popups.background
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "+24h"
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Item {
          id: plannerStatusRow
          visible: root.plannerOffsetMinutes !== 0
          width: parent.width
          height: Math.max(shortcutText.implicitHeight,
            plannerTooltip.height, resetNowHint.implicitHeight)
          readonly property real tooltipRightEdge: resetNowHint.x - Style.space(8)

          Rectangle {
            id: plannerTooltip
            visible: root.plannerTooltipText !== ""
            x: Math.max(0, Math.min(
              plannerStatusRow.tooltipRightEdge - width,
              plannerDock.thumbCenterX - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: plannerTooltipText.implicitWidth + Style.space(14)
            height: plannerTooltipText.implicitHeight + Style.space(8)
            radius: Style.space(2)
            color: Style.normalFillFor(
              root.contentForeground, Color.accent, Color.urgent)
            border.width: Style.spacing.hairline
            border.color: Style.normalBorderFor(
              root.contentForeground, Color.accent, Color.urgent)

            Text {
              id: plannerTooltipText
              anchors.centerIn: parent
              text: root.plannerTooltipText + " · "
                + Model.formatDuration(root.plannerOffsetMinutes, true)
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          Text {
            id: resetNowHint
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: plannerTooltip.verticalCenter
            text: "T now"
            color: Qt.darker(root.contentForeground, 1.75)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Text {
          id: shortcutText
          visible: root.plannerOffsetMinutes === 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.shortcutHint()
          color: Qt.darker(root.contentForeground, 1.6)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}

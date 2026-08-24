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
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string helperPath: decodeURIComponent(
    String(Qt.resolvedUrl("helpers/timezone.py")).replace(/^file:\/\//, ""))

  readonly property var locations: Model.normalizeLocations(
    setting("locations", Model.defaultLocations()))
  readonly property var homeLocation: Model.homeLocation(locations)
  readonly property bool showTimezoneAbbreviation: setting("showTimezoneAbbreviation", true) !== false
  readonly property bool showRelativeOffset: setting("showRelativeOffset", true) !== false
  readonly property bool showAnalogClock: setting("showAnalogClock", true) !== false
  readonly property string hourFormat: setting("hourFormat", "12") === "24" ? "24" : "12"

  property var renderedRows: []
  property var calendarData: ({ monthLabel: "Loading…", weekNumber: 0, days: [] })
  property string serviceError: ""
  property double dayAnchorTimestamp: Date.now()
  property int plannerOffsetMinutes: 0
  property bool followingNow: true
  readonly property double planningTimestamp: dayAnchorTimestamp + plannerOffsetMinutes * 60000
  readonly property int displaySecond: followingNow
    ? secondsClock.seconds
    : new Date(planningTimestamp).getUTCSeconds()

  property bool renderQueued: false
  property double activeRenderTimestamp: 0
  property int dateShiftOffset: 0

  property bool managingLocations: false
  property bool showingSettings: false
  property bool addingLocation: false
  property string renamingId: ""
  readonly property bool editorOpen: addingLocation || renamingId !== ""

  property var timezoneSuggestions: []
  property int suggestionIndex: 0
  property string chosenTimezone: ""
  property string chosenTimezoneName: ""
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
    root.cancelEditors()
    root.showingSettings = false
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

  function resetToNow() {
    root.followingNow = true
    root.plannerOffsetMinutes = 0
    root.dayAnchorTimestamp = Date.now()
    root.requestRender()
  }

  function setPlannerOffset(minutes) {
    root.followingNow = false
    root.plannerOffsetMinutes = Model.clampPlannerMinutes(minutes)
  }

  function stepPlanner(direction, largeStep) {
    var amount = largeStep ? 60 : 15
    root.setPlannerOffset(root.plannerOffsetMinutes + direction * amount)
  }

  function shiftPlanningDate(days) {
    if (dateShiftProcess.running || !root.homeLocation) return
    root.followingNow = false
    root.dateShiftOffset = root.plannerOffsetMinutes
    dateShiftProcess.command = [
      "python3",
      root.helperPath,
      "shift-date",
      String(Math.round(root.planningTimestamp)),
      root.homeLocation.timezone,
      String(days)
    ]
    dateShiftProcess.running = true
  }

  function requestRender() {
    root.renderQueued = true
    if (!renderProcess.running) Qt.callLater(root.startRender)
  }

  function startRender() {
    if (renderProcess.running || !root.renderQueued) return
    root.renderQueued = false
    root.activeRenderTimestamp = Math.round(root.planningTimestamp)
    renderProcess.command = [
      "python3",
      root.helperPath,
      "render",
      String(root.activeRenderTimestamp),
      JSON.stringify(root.locations)
    ]
    renderProcess.running = true
  }

  function renderedRow(id) {
    for (var i = 0; i < root.renderedRows.length; i++)
      if (root.renderedRows[i].id === id) return root.renderedRows[i]
    return null
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
    root.persistLocations(Model.moveLocation(root.locations, id, delta))
  }

  function setHomeLocation(id) {
    root.persistLocations(Model.setHomeLocation(root.locations, id))
  }

  function startRename(id, name) {
    root.addingLocation = false
    root.renamingId = id
    Qt.callLater(function() {
      renameField.text = name
      renameField.selectAll()
      renameField.forceActiveFocus()
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
    root.chosenTimezone = ""
    root.chosenTimezoneName = ""
    root.timezoneSuggestions = []
    root.suggestionIndex = 0
    Qt.callLater(function() {
      nameField.text = ""
      timezoneField.text = ""
      timezoneField.forceActiveFocus()
      root.requestTimezoneSearch("")
    })
  }

  function cancelEditors() {
    root.addingLocation = false
    root.renamingId = ""
    root.timezoneSuggestions = []
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
    root.timezoneSuggestions = []
    if (String(nameField.text || "").trim() === "") nameField.text = suggestion.name
    nameField.forceActiveFocus()
  }

  function commitAddLocation() {
    var timezone = root.chosenTimezone
    var defaultName = root.chosenTimezoneName
    if (timezone === "" && root.timezoneSuggestions.length > 0) {
      var selected = root.timezoneSuggestions[Math.max(
        0, Math.min(root.suggestionIndex, root.timezoneSuggestions.length - 1))]
      timezone = selected.timezone
      defaultName = selected.name
    }
    if (timezone === "") {
      root.serviceError = "Choose a timezone from the search results."
      return
    }

    var name = String(nameField.text || "").trim() || defaultName
    root.persistLocations(Model.addLocation(root.locations, name, timezone))
    root.addingLocation = false
    root.timezoneSuggestions = []
    root.serviceError = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function capturePreview() {
    root.previewStatus = "opening"
    if (!root.opened) root.open()
    root.resetToNow()
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
        root.serviceError = "Could not save the panel preview."
      } else {
        root.previewStatus = "saved " + root.previewPath
      }
    }, Qt.size(previewWidth, previewHeight))
  }

  onPlanningTimestampChanged: requestRender()
  onLocationsChanged: requestRender()
  onPreviewCaptureRequestedChanged: {
    if (root.previewCaptureRequested) root.capturePreview()
  }

  Component.onCompleted: {
    root.dayAnchorTimestamp = Date.now()
    root.requestRender()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (!root.followingNow) return
      root.plannerOffsetMinutes = 0
      root.dayAnchorTimestamp = date.getTime()
    }
  }

  SystemClock {
    id: secondsClock
    enabled: root.opened && root.showAnalogClock
    precision: SystemClock.Seconds
  }

  Process {
    id: renderProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") return
        try {
          var result = JSON.parse(raw)
          if (result.error) {
            root.serviceError = result.error
            return
          }
          if (Number(result.timestampMs) !== root.activeRenderTimestamp) return
          if (root.activeRenderTimestamp !== Math.round(root.planningTimestamp)) return
          root.renderedRows = result.rows || []
          root.calendarData = result.calendar || { monthLabel: "", weekNumber: 0, days: [] }
          root.serviceError = ""
        } catch (error) {
          root.serviceError = "Timezone conversion returned invalid data."
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.serviceError === "")
        root.serviceError = "Timezone conversion failed. Check Python and tzdata."
      if (root.renderQueued) Qt.callLater(root.startRender)
    }
  }

  Process {
    id: dateShiftProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") return
        try {
          var result = JSON.parse(raw)
          if (result.error) {
            root.serviceError = result.error
            return
          }
          root.dayAnchorTimestamp = Number(result.timestampMs) - root.dateShiftOffset * 60000
          root.serviceError = result.normalized
            ? "That local time falls in a DST gap, so it was moved forward."
            : ""
        } catch (error) {
          root.serviceError = "Could not change the planning date."
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.serviceError === "")
        root.serviceError = "Could not change the planning date."
    }
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
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(760))

    Rectangle {
      id: keyCatcher
      anchors.fill: parent
      color: Color.popups.background
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.editorOpen) return
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          root.stepPlanner(-1, !!(event.modifiers & Qt.ShiftModifier))
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          root.stepPlanner(1, !!(event.modifiers & Qt.ShiftModifier))
          event.accepted = true
        } else if (event.text === "t" || event.text === "T") {
          root.resetToNow()
          event.accepted = true
        }
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: scroll.width
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
                enabled: !dateShiftProcess.running
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
                enabled: !dateShiftProcess.running
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
                  enabled: !dateShiftProcess.running
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
                  root.cancelEditors()
                  root.managingLocations = false
                  root.showingSettings = !root.showingSettings
                }
              }

              Button {
                id: manageButton
                text: root.managingLocations ? "Done" : "Manage"
                selected: root.managingLocations
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(9)
                verticalPadding: Style.space(5)
                onClicked: {
                  root.cancelEditors()
                  root.showingSettings = false
                  root.managingLocations = !root.managingLocations
                }
              }
            }
          }

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

              Item {
                width: parent.width
                height: Math.max(analogSettingLabel.implicitHeight, analogSetting.implicitHeight)

                Text {
                  id: analogSettingLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Analog clocks"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }

                ToggleSwitch {
                  id: analogSetting
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  checked: root.showAnalogClock
                  rounded: false
                  foreground: root.contentForeground
                  accent: Color.accent
                  onToggled: root.persistSetting("showAnalogClock", !checked)
                }
              }

              Item {
                width: parent.width
                height: Math.max(hourFormatLabel.implicitHeight, hourFormatButtons.implicitHeight)

                Text {
                  id: hourFormatLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Hour format"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }

                Row {
                  id: hourFormatButtons
                  anchors.right: parent.right
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
                    onClicked: root.persistSetting("hourFormat", "12")
                  }

                  Button {
                    text: "24 hour"
                    selected: root.hourFormat === "24"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(4)
                    onClicked: root.persistSetting("hourFormat", "24")
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
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.locations

              Rectangle {
                id: clockCard
                required property var modelData
                required property int index
                readonly property var rendered: root.renderedRow(modelData.id)
                readonly property var availability: root.availabilityFor(rendered)

                width: clocks.width
                implicitHeight: rowContent.implicitHeight + Style.space(18)
                radius: Style.cornerRadius
                color: modelData.isHome
                  ? Style.selectedFillFor(root.contentForeground, Color.accent, Color.urgent)
                  : "transparent"

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

                  Row {
                    visible: root.managingLocations
                    spacing: Style.space(4)

                    Button {
                      text: "Rename"
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      fontSize: Style.font.bodySmall
                      horizontalPadding: Style.space(7)
                      verticalPadding: Style.space(4)
                      onClicked: root.startRename(clockCard.modelData.id, clockCard.modelData.name)
                    }

                    Button {
                      text: "Home"
                      enabled: !clockCard.modelData.isHome
                      opacity: enabled ? 1 : 0.35
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      fontSize: Style.font.bodySmall
                      horizontalPadding: Style.space(7)
                      verticalPadding: Style.space(4)
                      onClicked: root.setHomeLocation(clockCard.modelData.id)
                    }

                    Button {
                      text: "↑"
                      enabled: clockCard.index > 0
                      opacity: enabled ? 1 : 0.35
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      fontSize: Style.font.bodySmall
                      horizontalPadding: Style.space(7)
                      verticalPadding: Style.space(4)
                      onClicked: root.moveLocation(clockCard.modelData.id, -1)
                    }

                    Button {
                      text: "↓"
                      enabled: clockCard.index < root.locations.length - 1
                      opacity: enabled ? 1 : 0.35
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      fontSize: Style.font.bodySmall
                      horizontalPadding: Style.space(7)
                      verticalPadding: Style.space(4)
                      onClicked: root.moveLocation(clockCard.modelData.id, 1)
                    }

                    Button {
                      text: "Remove"
                      enabled: root.locations.length > 1
                      opacity: enabled ? 1 : 0.35
                      foreground: Color.urgent
                      fontFamily: root.contentFontFamily
                      fontSize: Style.font.bodySmall
                      horizontalPadding: Style.space(7)
                      verticalPadding: Style.space(4)
                      onClicked: root.removeLocation(clockCard.modelData.id)
                    }
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
            height: plannerSlider.implicitHeight

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "−12h"
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
              bar: root.bar
              minimum: -48
              maximum: 48
              value: root.plannerOffsetMinutes / 15
              step: 1
              integer: true
              tickCount: 9
              onMoved: function(next) { root.setPlannerOffset(Math.round(next) * 15) }
              onReleased: function(next) { root.setPlannerOffset(Math.round(next) * 15) }
              onRightClicked: root.resetToNow()
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "+12h"
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Model.planningLabel(root.plannerOffsetMinutes, root.followingNow)
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "←/→ 15 min   ·   Shift + ←/→ 1 hour   ·   T now"
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle {
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
                  placeholderText: "Name or person"
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

          Button {
            visible: root.managingLocations && !root.editorOpen
            anchors.horizontalCenter: parent.horizontalCenter
            text: "+ Add location"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            fontSize: Style.font.body
            onClicked: root.startAddingLocation()
          }
        }
      }
    }
  }
}

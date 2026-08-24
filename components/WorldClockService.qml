import QtQuick
import Quickshell
import Quickshell.Io
import "../Model.js" as Model

// Session-wide state shared by the compact bar popup and the expanded panel.
// Durable preferences remain in the widget's inline shell.json entry; the
// actively selected instant intentionally lives only in this service.
Item {
  id: root

  readonly property string moduleName: "io.github.ptgamr.world-clock"
  readonly property string helperPath: decodeURIComponent(
    String(Qt.resolvedUrl("../helpers/timezone.py")).replace(/^file:\/\//, ""))

  // Injected by omarchy-shell's service loader.
  property var shell: null
  property var settings: ({})
  property bool settingsReady: false
  property bool defaultDetectionAttempted: false

  property var locations: Model.defaultLocations()
  readonly property var homeLocation: Model.homeLocation(locations)
  property bool showTimezoneAbbreviation: true
  property bool showRelativeOffset: true
  property bool showAnalogClock: true
  property string hourFormat: "12"

  property var renderedRows: []
  property double renderedTimestamp: 0
  readonly property var visibleRows: Model.previewRenderedRows(
    renderedRows, renderedTimestamp, planningTimestamp)
  property var calendarData: ({ monthLabel: "Loading…", weekNumber: 0, days: [] })
  property string errorMessage: ""
  property double dayAnchorTimestamp: Date.now()
  property int plannerOffsetMinutes: 0
  property bool followingNow: true
  readonly property double planningTimestamp: dayAnchorTimestamp + plannerOffsetMinutes * 60000

  property bool renderQueued: false
  property double activeRenderTimestamp: 0
  property int dateShiftOffset: 0
  readonly property bool dateShiftBusy: dateShiftProcess.running

  property double timelineStartTimestamp: planningTimestamp - 12 * 60 * 60 * 1000
  property var timelineData: ({
    startTimestampMs: 0,
    endTimestampMs: 0,
    hours: 24,
    stepMinutes: 30,
    slotCount: 48,
    ticks: [],
    rows: []
  })
  property bool timelineQueued: false
  property double activeTimelineStart: 0

  property int meetingDurationMinutes: 60
  readonly property double meetingEndTimestamp: planningTimestamp + meetingDurationMinutes * 60000
  property var meetingData: ({
    startTimestampMs: 0,
    endTimestampMs: 0,
    durationMinutes: 60,
    homeDate: "",
    homeDateLabel: "",
    rows: []
  })
  property bool meetingQueued: false
  property double activeMeetingStart: 0
  property int activeMeetingDuration: 60
  property string copyStatus: ""

  function entrySettings() {
    if (!root.shell || !root.shell.barConfig || !root.shell.barConfig.layout) return null
    var layout = root.shell.barConfig.layout
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var entries = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (!entry || String(entry.id || "") !== root.moduleName) continue
        var result = ({})
        for (var key in entry) if (key !== "id") result[key] = entry[key]
        return result
      }
    }
    return null
  }

  function syncSettings() {
    var next = root.entrySettings()
    if (next === null) return

    root.settings = next
    root.settingsReady = true
    if (Array.isArray(next.locations) && next.locations.length > 0)
      root.locations = Model.normalizeLocations(next.locations)
    else
      root.detectFirstRunTimezone()
    root.showTimezoneAbbreviation = next.showTimezoneAbbreviation !== false
    root.showRelativeOffset = next.showRelativeOffset !== false
    root.showAnalogClock = next.showAnalogClock !== false
    root.hourFormat = next.hourFormat === "24" ? "24" : "12"
  }

  function mergedEntry() {
    var entry = { id: root.moduleName, configVersion: 1 }
    for (var key in root.settings)
      if (key !== "id" && key !== "configVersion") entry[key] = root.settings[key]
    return entry
  }

  function persistLocations(nextLocations) {
    var normalized = Model.normalizeLocations(nextLocations)
    var entry = root.mergedEntry()
    entry.locations = normalized
    root.locations = normalized
    var nextSettings = ({})
    for (var key in entry) if (key !== "id") nextSettings[key] = entry[key]
    root.settings = nextSettings
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.moduleName, entry)
  }

  function persistSetting(key, value) {
    var entry = root.mergedEntry()
    entry[key] = value
    var nextSettings = ({})
    for (var existing in entry) if (existing !== "id") nextSettings[existing] = entry[existing]
    root.settings = nextSettings
    if (key === "showTimezoneAbbreviation") root.showTimezoneAbbreviation = value !== false
    else if (key === "showRelativeOffset") root.showRelativeOffset = value !== false
    else if (key === "showAnalogClock") root.showAnalogClock = value !== false
    else if (key === "hourFormat") root.hourFormat = value === "24" ? "24" : "12"
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.moduleName, entry)
  }

  function detectFirstRunTimezone() {
    if (!root.settingsReady || root.defaultDetectionAttempted
        || (Array.isArray(root.settings.locations) && root.settings.locations.length > 0)) return
    root.defaultDetectionAttempted = true
    defaultTimezoneProcess.command = ["python3", root.helperPath, "detect-timezone"]
    defaultTimezoneProcess.running = true
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

  function setPlanningTimestamp(timestampMs) {
    var value = Number(timestampMs)
    if (!isFinite(value)) return
    root.followingNow = false
    root.dayAnchorTimestamp = value
    root.plannerOffsetMinutes = 0
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

  function centerTimelineOnSelection() {
    root.timelineStartTimestamp = Math.round(root.planningTimestamp - 12 * 60 * 60 * 1000)
    root.requestTimeline()
  }

  function requestTimeline() {
    root.timelineQueued = true
    if (!timelineProcess.running) Qt.callLater(root.startTimeline)
  }

  function setMeetingDuration(minutes) {
    var snapped = Math.round(Number(minutes) / 15) * 15
    if (!isFinite(snapped)) return
    root.meetingDurationMinutes = Math.max(15, Math.min(12 * 60, snapped))
  }

  function requestMeeting() {
    root.meetingQueued = true
    if (!meetingProcess.running) Qt.callLater(root.startMeeting)
  }

  function startMeeting() {
    if (meetingProcess.running || !root.meetingQueued) return
    root.meetingQueued = false
    root.activeMeetingStart = Math.round(root.planningTimestamp)
    root.activeMeetingDuration = root.meetingDurationMinutes
    meetingProcess.command = [
      "python3",
      root.helperPath,
      "meeting",
      String(root.activeMeetingStart),
      String(root.activeMeetingDuration),
      JSON.stringify(root.locations)
    ]
    meetingProcess.running = true
  }

  function meetingText() {
    var meeting = root.meetingData || ({})
    var rows = Array.isArray(meeting.rows) ? meeting.rows : []
    if (rows.length === 0) return ""
    var lines = ["Meeting time · " + String(meeting.homeDateLabel || "")]
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var range = root.hourFormat === "24" ? row.range24 : row.range12
      if (row.startDate !== meeting.homeDate) range = row.startWeekday + " " + range
      lines.push(row.name + " — " + range + (row.abbreviation ? " " + row.abbreviation : ""))
    }
    return lines.join("\n")
  }

  function copyMeetingTime() {
    var value = root.meetingText()
    if (value === "") return
    Quickshell.execDetached(["omarchy-clipboard-paste-text", "--copy-only", value])
    root.copyStatus = "Copied meeting time"
    copyStatusTimer.restart()
  }

  function startTimeline() {
    if (timelineProcess.running || !root.timelineQueued) return
    root.timelineQueued = false
    root.activeTimelineStart = Math.round(root.timelineStartTimestamp)
    timelineProcess.command = [
      "python3",
      root.helperPath,
      "timeline",
      String(root.activeTimelineStart),
      JSON.stringify(root.locations),
      "--hours",
      "24",
      "--step-minutes",
      "30"
    ]
    timelineProcess.running = true
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
    for (var i = 0; i < root.visibleRows.length; i++)
      if (root.visibleRows[i].id === id) return root.visibleRows[i]
    return null
  }

  onShellChanged: Qt.callLater(root.syncSettings)
  onLocationsChanged: {
    root.requestRender()
    root.requestMeeting()
    if (root.timelineData.startTimestampMs) root.requestTimeline()
  }
  onPlanningTimestampChanged: {
    root.requestRender()
    root.requestMeeting()
  }
  onMeetingDurationMinutesChanged: root.requestMeeting()

  Connections {
    target: root.shell
    function onBarConfigChanged() { root.syncSettings() }
  }

  Component.onCompleted: {
    root.dayAnchorTimestamp = Date.now()
    Qt.callLater(root.syncSettings)
    root.requestRender()
    root.requestMeeting()
  }

  Timer {
    id: copyStatusTimer
    interval: 2200
    onTriggered: root.copyStatus = ""
  }

  SystemClock {
    precision: SystemClock.Minutes
    onDateChanged: {
      if (!root.followingNow) return
      root.plannerOffsetMinutes = 0
      root.dayAnchorTimestamp = date.getTime()
    }
  }

  Process {
    id: defaultTimezoneProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!root.settingsReady || raw === ""
            || (Array.isArray(root.settings.locations) && root.settings.locations.length > 0)) return
        try {
          var result = JSON.parse(raw)
          if (result.timezone) root.persistLocations(Model.defaultLocations(result.timezone))
        } catch (error) {
          root.errorMessage = "Could not detect the local timezone."
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.settingsReady)
        root.errorMessage = "Could not detect the local timezone."
    }
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
            root.errorMessage = result.error
            return
          }
          if (Number(result.timestampMs) !== root.activeRenderTimestamp) return
          if (root.activeRenderTimestamp !== Math.round(root.planningTimestamp)) return
          root.renderedTimestamp = Number(result.timestampMs)
          root.renderedRows = result.rows || []
          root.calendarData = result.calendar || { monthLabel: "", weekNumber: 0, days: [] }
          root.errorMessage = ""
        } catch (error) {
          root.errorMessage = "Timezone conversion returned invalid data."
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.errorMessage === "")
        root.errorMessage = "Timezone conversion failed. Check Python and tzdata."
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
            root.errorMessage = result.error
            return
          }
          root.dayAnchorTimestamp = Number(result.timestampMs) - root.dateShiftOffset * 60000
          root.errorMessage = result.normalized
            ? "That local time falls in a DST gap, so it was moved forward."
            : ""
        } catch (error) {
          root.errorMessage = "Could not change the planning date."
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.errorMessage === "")
        root.errorMessage = "Could not change the planning date."
    }
  }

  Process {
    id: timelineProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") return
        try {
          var result = JSON.parse(raw)
          if (result.error) {
            root.errorMessage = result.error
            return
          }
          if (Number(result.startTimestampMs) !== root.activeTimelineStart) return
          root.timelineData = result
          root.errorMessage = ""
        } catch (error) {
          root.errorMessage = "Timeline conversion returned invalid data."
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.errorMessage === "")
        root.errorMessage = "Could not build the timezone timeline."
      if (root.timelineQueued) Qt.callLater(root.startTimeline)
    }
  }

  Process {
    id: meetingProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") return
        try {
          var result = JSON.parse(raw)
          if (result.error) {
            root.errorMessage = result.error
            return
          }
          if (Number(result.startTimestampMs) !== root.activeMeetingStart
              || Number(result.durationMinutes) !== root.activeMeetingDuration) return
          if (root.activeMeetingStart !== Math.round(root.planningTimestamp)
              || root.activeMeetingDuration !== root.meetingDurationMinutes) return
          root.meetingData = result
          root.errorMessage = ""
        } catch (error) {
          root.errorMessage = "Meeting time conversion returned invalid data."
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.errorMessage === "")
        root.errorMessage = "Could not prepare the meeting time."
      if (root.meetingQueued) Qt.callLater(root.startMeeting)
    }
  }
}

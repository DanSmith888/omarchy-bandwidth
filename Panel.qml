import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "dansmith888.network"
  ipcTarget: "dansmith888.network"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var iconChoices: [
    { down: "↓", up: "↑" },
    { down: "▼", up: "▲" },
    { down: "⬇", up: "⬆" },
    { down: "⇓", up: "⇑" },
    { down: "⬊", up: "⬈" },
    { down: "•", up: "•" }
  ]

  property var themeColors: ({})
  readonly property var colorChoices: Model.themePalette(root.themeColors)

  readonly property int speedWidth: Model.clampInt(setting("speedWidth", 0), 0, 300, 0)
  readonly property bool showIcon: Model.asBool(setting("showIcon", true), true)
  readonly property string selectedInterface: String(setting("selectedInterface", "auto"))
  readonly property string downloadIcon: String(setting("downloadIcon", "↓"))
  readonly property string uploadIcon: String(setting("uploadIcon", "↑"))
  readonly property string byteColor: String(setting("byteColor", ""))
  readonly property string kiloColor: String(setting("kiloColor", ""))
  readonly property string megaColor: String(setting("megaColor", ""))
  readonly property string gigaColor: String(setting("gigaColor", ""))
  readonly property string alertColor: String(setting("alertColor", ""))
  readonly property int downloadAlertValue: Math.max(0, Math.round(Number(setting("downloadAlertValue", 0))))
  readonly property string downloadAlertScale: Model.isFixedScale(setting("downloadAlertScale", "mega")) ? Model.normalizeScale(setting("downloadAlertScale")) : "mega"
  readonly property int uploadAlertValue: Math.max(0, Math.round(Number(setting("uploadAlertValue", 0))))
  readonly property string uploadAlertScale: Model.isFixedScale(setting("uploadAlertScale", "mega")) ? Model.normalizeScale(setting("uploadAlertScale")) : "mega"
  readonly property int minThreshold: Math.max(0, Math.round(Number(setting("minThreshold", 0))))
  readonly property string minThresholdScale: Model.isFixedScale(setting("minThresholdScale", "base")) ? Model.normalizeScale(setting("minThresholdScale")) : "base"
  readonly property int pollIntervalMs: Math.max(500, Number(setting("pollIntervalMs", 2000)))
  readonly property string unitSystem: Model.normalizeSystem(setting("unitSystem", "bytes"))
  readonly property string unitScale: Model.normalizeScale(setting("unitScale", "auto"))

  readonly property var unitSystemOptions: [
    { value: "bytes", label: "Bytes (kB, MB, GB)" },
    { value: "bits", label: "Bits (kb, Mb, Gb)" },
    { value: "binary", label: "Binary bytes (KiB, MiB, GiB)" }
  ]

  readonly property var unitOptions: [
    { value: "auto", label: "Auto" },
    { value: "base", label: Model.unitLabel(unitSystem, "base") + "/s" },
    { value: "kilo", label: Model.unitLabel(unitSystem, "kilo") + "/s" },
    { value: "mega", label: Model.unitLabel(unitSystem, "mega") + "/s" },
    { value: "giga", label: Model.unitLabel(unitSystem, "giga") + "/s" }
  ]

  readonly property var magnitudeOptions: unitOptions.slice(1)

  // Segmented-control variants: short chip labels, full unit in the tooltip.
  readonly property var unitSystemChips: [
    { value: "bytes", label: "Bytes", tooltip: "Decimal bytes: kB, MB, GB (×1000)" },
    { value: "bits", label: "Bits", tooltip: "Bits: kb, Mb, Gb (×1000, ×8)" },
    { value: "binary", label: "Binary", tooltip: "Binary bytes: KiB, MiB, GiB (×1024)" }
  ]
  readonly property var unitChips: [{ value: "auto", label: "Auto", tooltip: "Pick the magnitude per reading" }].concat(magnitudeChips)
  readonly property var magnitudeChips: Model.SCALES.map(function(sc) {
    return { value: sc, label: Model.shortUnitLabel(unitSystem, sc), tooltip: Model.unitLabel(unitSystem, sc) + "/s" }
  })
  readonly property var refreshChips: refreshOptions

  // Unit label for the base magnitude of the active system ("B" or "b").
  readonly property string baseUnit: Model.unitLabel(unitSystem, "base")

  readonly property var refreshOptions: [
    { value: "500", label: "0.5s" },
    { value: "1000", label: "1s" },
    { value: "2000", label: "2s" },
    { value: "3000", label: "3s" },
    { value: "5000", label: "5s" }
  ]

  property real downloadRate: 0
  property real uploadRate: 0
  property var interfaceList: []
  property string resolvedLabel: "…"
  property var throughputPrev: ({})
  property var networkProcesses: []
  // Recent rates, oldest first, for the panel sparklines.
  property var downloadHistory: []
  property var uploadHistory: []
  readonly property int historySamples: Model.clampInt(setting("historySamples", 60), 20, 240, 60)
  function setHistorySamples(v) { persistSettings({ historySamples: Model.clampInt(v, 20, 240, 60) }) }
  readonly property var historyChips: [
    { value: "30", label: "30" },
    { value: "60", label: "60" },
    { value: "120", label: "120" },
    { value: "240", label: "240" }
  ]
  property var networkProcessPrev: ({})

  // minThreshold is a number + magnitude in the active unit system.
  readonly property real minThresholdBytes: Model.thresholdBytes(minThreshold, minThresholdScale, unitSystem)
  readonly property bool downloadIdle: downloadRate < minThresholdBytes
  readonly property bool uploadIdle: uploadRate < minThresholdBytes
  readonly property string idleText: "- " + Model.unitLabel(unitSystem, unitScale) + "/s"
  readonly property string downloadText: downloadIdle ? idleText : Model.formatRate(downloadRate, unitSystem, unitScale)
  readonly property string uploadText: uploadIdle ? idleText : Model.formatRate(uploadRate, unitSystem, unitScale)
  // Compact variants shown in the bar itself.
  readonly property string barIdleText: "-" + Model.shortUnitLabel(unitSystem, unitScale)
  readonly property string barDownloadText: downloadIdle ? barIdleText : Model.formatBar(downloadRate, unitSystem, unitScale)
  readonly property string barUploadText: uploadIdle ? barIdleText : Model.formatBar(uploadRate, unitSystem, unitScale)

  // Tier boundaries are 1 kilo and 1 mega in the active unit system.
  function tierColorForRate(rate) {
    var tier = Model.magnitudeIndex(rate, unitSystem)
    if (tier === 0) return byteColor
    if (tier === 1) return kiloColor
    if (tier === 2) return megaColor
    return gigaColor
  }

  // Alert limits are stored as a number + magnitude in the active unit
  // system; at or above the limit the alert colour overrides the tier colour.
  readonly property real downloadAlertBytes: Model.thresholdBytes(downloadAlertValue, downloadAlertScale, unitSystem)
  readonly property real uploadAlertBytes: Model.thresholdBytes(uploadAlertValue, uploadAlertScale, unitSystem)
  readonly property bool downloadAlerting: downloadAlertBytes > 0 && alertColor !== "" && downloadRate >= downloadAlertBytes
  readonly property bool uploadAlerting: uploadAlertBytes > 0 && alertColor !== "" && uploadRate >= uploadAlertBytes

  readonly property string downloadTierColor: downloadAlerting ? alertColor : tierColorForRate(downloadRate)
  readonly property string uploadTierColor: uploadAlerting ? alertColor : tierColorForRate(uploadRate)

  readonly property var interfaceOptions: {
    var opts = [
      { value: "auto", label: "Auto (default route)" },
      { value: "all", label: "All interfaces" }
    ]
    for (var i = 0; i < interfaceList.length; i++)
      opts.push({ value: interfaceList[i], label: interfaceList[i] })
    return opts
  }

  function persistSettings(patch) {
    var next = Object.assign({}, root.settings, patch)
    root.settings = next
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = next
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  function setSpeedWidth(v) { persistSettings({ speedWidth: Model.clampInt(v, 0, 300, 0) }) }
  function setShowIcon(v) { persistSettings({ showIcon: !!v }) }

  function setSelectedInterface(value) {
    persistSettings({ selectedInterface: String(value || "auto") })
  }

  function setDownloadIcon(icon) { persistSettings({ downloadIcon: icon }) }
  function setUploadIcon(icon) { persistSettings({ uploadIcon: icon }) }
  function setByteColor(hex) { persistSettings({ byteColor: hex }) }
  function setKiloColor(hex) { persistSettings({ kiloColor: hex }) }
  function setMegaColor(hex) { persistSettings({ megaColor: hex }) }
  function setGigaColor(hex) { persistSettings({ gigaColor: hex }) }
  function setAlertColor(hex) { persistSettings({ alertColor: hex }) }
  function setDownloadAlertValue(value) { persistSettings({ downloadAlertValue: Math.max(0, Math.round(Number(value) || 0)) }) }
  function setDownloadAlertScale(value) { persistSettings({ downloadAlertScale: Model.isFixedScale(value) ? Model.normalizeScale(value) : "mega" }) }
  function setUploadAlertValue(value) { persistSettings({ uploadAlertValue: Math.max(0, Math.round(Number(value) || 0)) }) }
  function setUploadAlertScale(value) { persistSettings({ uploadAlertScale: Model.isFixedScale(value) ? Model.normalizeScale(value) : "mega" }) }

  function setMinThreshold(value) { persistSettings({ minThreshold: Math.max(0, Math.round(Number(value) || 0)) }) }
  function setMinThresholdScale(value) { persistSettings({ minThresholdScale: Model.isFixedScale(value) ? Model.normalizeScale(value) : "base" }) }
  function setUnitSystem(value) { persistSettings({ unitSystem: Model.normalizeSystem(value) }) }
  function setUnitScale(value) { persistSettings({ unitScale: Model.normalizeScale(value) }) }
  function setPollIntervalMs(value) { persistSettings({ pollIntervalMs: Math.max(500, Math.round(Number(value) || 2000)) }) }

  function refreshNow() { pollProc.running = true }

  function handleSample(raw) {
    var sample = Model.parseSample(raw)
    root.interfaceList = sample.list
    var active = Model.resolveActive(sample, root.selectedInterface)
    root.resolvedLabel = active.label
    var now = Date.now() / 1000
    var state = Model.throughputState(root.throughputPrev, { key: root.selectedInterface, rx: active.rx, tx: active.tx }, now)
    root.throughputPrev = state
    root.downloadRate = state.downloadRate
    root.uploadRate = state.uploadRate
    root.downloadHistory = Model.pushHistory(root.downloadHistory, state.downloadRate, root.historySamples)
    root.uploadHistory = Model.pushHistory(root.uploadHistory, state.uploadRate, root.historySamples)
  }

  function refreshProcessesNow() { if (root.opened) processProc.running = true }

  function handleProcessSample(raw) {
    var now = Date.now()
    var state = Model.parseNetworkProcesses(raw, root.networkProcessPrev, now)
    root.networkProcessPrev = state.previous
    root.networkProcesses = state.list
  }

  function refreshThemeColorsNow() { themeColorsProc.running = true }

  function handleThemeColorsSample(raw) {
    root.themeColors = Model.parseThemeColors(raw)
  }

  onSelectedInterfaceChanged: throughputPrev = ({})
  onOpenedChanged: if (opened) { refreshProcessesNow(); refreshThemeColorsNow() }
  Component.onCompleted: refreshThemeColorsNow()

  Timer {
    interval: root.pollIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshNow()
      root.refreshProcessesNow()
    }
  }

  Process {
    id: processProc
    command: ["bash", "-lc", "ss -H -tanpi 2>/dev/null"]
    stdout: StdioCollector {
      id: processOut
      waitForEnd: true
      onStreamFinished: root.handleProcessSample(text)
    }
  }

  Process {
    id: themeColorsProc
    command: ["bash", "-lc", "cat ~/.local/state/omarchy/current/theme/colors.toml 2>/dev/null"]
    stdout: StdioCollector {
      id: themeColorsOut
      waitForEnd: true
      onStreamFinished: root.handleThemeColorsSample(text)
    }
  }

  Process {
    id: pollProc
    command: ["bash", "-lc", Model.pollScript()]
    stdout: StdioCollector {
      id: pollOut
      waitForEnd: true
      onStreamFinished: root.handleSample(text)
    }
  }

  PopupCard {
    id: popup
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.barIdentity
    open: root.opened
    contentWidth: Style.space(380)
    contentHeight: Style.space(680)

    ScrollView {
      id: scrollArea
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff

      ColumnLayout {
        id: column
        width: scrollArea.width - Style.space(16)
        spacing: Style.spacing.md

        // ---------- Hero: speed mark · name · interface ----------
        PanelHero {
          Layout.fillWidth: true
          Layout.preferredHeight: implicitHeight
          title: "Network Speed"
          meta: root.resolvedLabel
          foreground: Color.popups.text
          fontFamily: Style.font.family
          iconComponent: Component {
            Text {
              text: "󰓅"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.downloadIcon + " " + root.downloadText + "   " + root.uploadIcon + " " + root.uploadText
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        // History, the way the CPU and GPU panels show theirs. One graph per
        // direction: a rate has no ceiling to scale against, so each is
        // scaled to the tallest sample in its own window (ceiling 0).
        Text {
          Layout.fillWidth: true
          text: root.downloadIcon + " download"
          color: Qt.darker(Color.popups.text, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Sparkline {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(34)
          values: root.downloadHistory
          ceiling: 0
          lineColor: root.downloadTierColor !== "" ? root.downloadTierColor : Color.accent
        }

        Text {
          Layout.fillWidth: true
          text: root.uploadIcon + " upload"
          color: Qt.darker(Color.popups.text, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Sparkline {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(34)
          values: root.uploadHistory
          ceiling: 0
          lineColor: root.uploadTierColor !== "" ? root.uploadTierColor : Color.accent
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "TOP APPS"; foreground: Color.popups.text }

        Text {
          Layout.fillWidth: true
          visible: root.networkProcesses.length === 0
          text: "No active connections detected yet."
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.networkProcesses.slice(0, 5)
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.spacing.sm

            Text {
              Layout.fillWidth: true
              text: modelData.name + " (" + modelData.pid + ")"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              text: "↓ " + Model.formatRate(modelData.rxRate, root.unitSystem, root.unitScale) + "  ↑ " + Model.formatRate(modelData.txRate, root.unitSystem, root.unitScale)
              color: Qt.darker(Color.popups.text, 1.2)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "INTERFACE"; foreground: Color.popups.text }

        Dropdown {
          Layout.alignment: Qt.AlignLeft
          showLabel: false
          value: root.selectedInterface
          options: root.interfaceOptions
          foreground: Color.popups.text
          background: Color.popups.background
          popupBorder: Color.popups.border
          onChanged: function(value) { root.setSelectedInterface(value) }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "DISPLAY"; foreground: Color.popups.text }

        Text {
          Layout.fillWidth: true
          text: "Unit system — applies to readings, speed colors, and the threshold"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        ButtonGroup {
          Layout.alignment: Qt.AlignLeft
          value: root.unitSystem
          options: root.unitSystemChips
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontFamily: Style.font.family
          onChanged: function(value) { root.setUnitSystem(value) }
        }

        Text {
          Layout.fillWidth: true
          text: "Scale (Auto picks per reading; a fixed scale never changes)"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        ButtonGroup {
          Layout.alignment: Qt.AlignLeft
          value: root.unitScale
          options: root.unitChips
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontFamily: Style.font.family
          onChanged: function(value) { root.setUnitScale(value) }
        }

        Toggle {
          Layout.fillWidth: true
          label: "Network icon"
          description: "󰓅 in front of the readings."
          checked: root.showIcon
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: Style.font.family
          onClicked: root.setShowIcon(!root.showIcon)
        }

        Text {
          Layout.fillWidth: true
          text: "Refresh interval"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        ButtonGroup {
          Layout.alignment: Qt.AlignLeft
          value: String(root.pollIntervalMs)
          options: root.refreshChips
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontFamily: Style.font.family
          onChanged: function(value) { root.setPollIntervalMs(value) }
        }

        Text {
          Layout.fillWidth: true
          text: "Graph history (samples)"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        ButtonGroup {
          Layout.alignment: Qt.AlignLeft
          value: String(root.historySamples)
          options: root.historyChips
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontFamily: Style.font.family
          onChanged: function(value) { root.setHistorySamples(value) }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "DOWNLOAD"; foreground: Color.popups.text }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.iconChoices
            delegate: Rectangle {
              required property var modelData
              width: Style.space(30)
              height: Style.space(30)
              radius: Style.cornerRadius
              color: root.downloadIcon === modelData.down ? Style.selectedFillFor(Color.popups.text, Color.accent) : "transparent"
              border.width: root.downloadIcon === modelData.down ? 1 : 0
              border.color: Color.accent

              Text {
                anchors.centerIn: parent
                text: modelData.down
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setDownloadIcon(modelData.down)
              }
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "UPLOAD"; foreground: Color.popups.text }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.iconChoices
            delegate: Rectangle {
              required property var modelData
              width: Style.space(30)
              height: Style.space(30)
              radius: Style.cornerRadius
              color: root.uploadIcon === modelData.up ? Style.selectedFillFor(Color.popups.text, Color.accent) : "transparent"
              border.width: root.uploadIcon === modelData.up ? 1 : 0
              border.color: Color.accent

              Text {
                anchors.centerIn: parent
                text: modelData.up
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setUploadIcon(modelData.up)
              }
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "IDLE THRESHOLD"; foreground: Color.popups.text }

        Text {
          Layout.fillWidth: true
          text: "Hide tiny background traffic: any rate under this shows as \"" + root.idleText + "\" instead of a number. 0 shows everything."
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          Layout.fillWidth: true
          text: "Hide readings under"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          NumberField {
            label: ""
            value: root.minThreshold
            from: 0
            to: 100000
            stepSize: 1
            foreground: Color.popups.text
            accent: Color.accent
            field.editable: false
            onModified: function(value) { root.setMinThreshold(value) }
          }

          ButtonGroup {
            value: root.minThresholdScale
            options: root.magnitudeChips
            foreground: Color.popups.text
            background: Color.popups.background
            accent: Color.accent
            fontFamily: Style.font.family
            onChanged: function(value) { root.setMinThresholdScale(value) }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "LAYOUT"; foreground: Color.popups.text }

        Text {
          Layout.fillWidth: true
          text: "Width of each reading in pixels. 0 fits the readings and holds that width so the bar stays still."
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        NumberField {
          label: ""
          value: root.speedWidth
          from: 0
          to: 300
          stepSize: 2
          foreground: Color.popups.text
          accent: Color.accent
          field.editable: false
          onModified: function(value) { root.setSpeedWidth(value) }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "SPEED COLORS"; foreground: Color.popups.text }

        Text {
          Layout.fillWidth: true
          text: "Pick a color for each speed band. A reading (arrow, number and unit) takes the color of the band it is currently in; download and upload share these. ∅ keeps the normal bar color."
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          text: "Under 1 " + Model.unitLabel(root.unitSystem, "kilo") + "/s"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.colorChoices.length
            delegate: Rectangle {
              required property int index
              readonly property string swatch: root.colorChoices[index]
              width: Style.space(22)
              height: Style.space(22)
              radius: width / 2
              color: swatch === "" ? "transparent" : swatch
              border.width: root.byteColor === swatch ? 2 : 1
              border.color: root.byteColor === swatch ? Color.accent : Qt.darker(Color.popups.text, 1.6)

              Text {
                visible: swatch === ""
                anchors.centerIn: parent
                text: "∅"
                color: Color.popups.text
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setByteColor(swatch)
              }
            }
          }
        }

        Text {
          text: "1 " + Model.unitLabel(root.unitSystem, "kilo") + "/s to 1 " + Model.unitLabel(root.unitSystem, "mega") + "/s"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.colorChoices.length
            delegate: Rectangle {
              required property int index
              readonly property string swatch: root.colorChoices[index]
              width: Style.space(22)
              height: Style.space(22)
              radius: width / 2
              color: swatch === "" ? "transparent" : swatch
              border.width: root.kiloColor === swatch ? 2 : 1
              border.color: root.kiloColor === swatch ? Color.accent : Qt.darker(Color.popups.text, 1.6)

              Text {
                visible: swatch === ""
                anchors.centerIn: parent
                text: "∅"
                color: Color.popups.text
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setKiloColor(swatch)
              }
            }
          }
        }

        Text {
          text: "1 " + Model.unitLabel(root.unitSystem, "mega") + "/s to 1 " + Model.unitLabel(root.unitSystem, "giga") + "/s"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.colorChoices.length
            delegate: Rectangle {
              required property int index
              readonly property string swatch: root.colorChoices[index]
              width: Style.space(22)
              height: Style.space(22)
              radius: width / 2
              color: swatch === "" ? "transparent" : swatch
              border.width: root.megaColor === swatch ? 2 : 1
              border.color: root.megaColor === swatch ? Color.accent : Qt.darker(Color.popups.text, 1.6)

              Text {
                visible: swatch === ""
                anchors.centerIn: parent
                text: "∅"
                color: Color.popups.text
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setMegaColor(swatch)
              }
            }
          }
        }

        Text {
          text: "1 " + Model.unitLabel(root.unitSystem, "giga") + "/s and above"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.colorChoices.length
            delegate: Rectangle {
              required property int index
              readonly property string swatch: root.colorChoices[index]
              width: Style.space(22)
              height: Style.space(22)
              radius: width / 2
              color: swatch === "" ? "transparent" : swatch
              border.width: root.gigaColor === swatch ? 2 : 1
              border.color: root.gigaColor === swatch ? Color.accent : Qt.darker(Color.popups.text, 1.6)

              Text {
                visible: swatch === ""
                anchors.centerIn: parent
                text: "∅"
                color: Color.popups.text
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setGigaColor(swatch)
              }
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "ALERT"; foreground: Color.popups.text }

        Text {
          Layout.fillWidth: true
          text: "Flag heavy traffic: when download or upload reaches its limit, that reading turns the alert color (overriding the speed band color). Set a limit to 0 to turn it off."
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          text: "Download at or above"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          NumberField {
            label: ""
            value: root.downloadAlertValue
            from: 0
            to: 10000
            stepSize: 5
            foreground: Color.popups.text
            accent: Color.accent
            field.editable: false
            onModified: function(value) { root.setDownloadAlertValue(value) }
          }

          ButtonGroup {
            value: root.downloadAlertScale
            options: root.magnitudeChips
            foreground: Color.popups.text
            background: Color.popups.background
            accent: Color.accent
            fontFamily: Style.font.family
            onChanged: function(value) { root.setDownloadAlertScale(value) }
          }
        }

        Text {
          text: "Upload at or above"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          NumberField {
            label: ""
            value: root.uploadAlertValue
            from: 0
            to: 10000
            stepSize: 5
            foreground: Color.popups.text
            accent: Color.accent
            field.editable: false
            onModified: function(value) { root.setUploadAlertValue(value) }
          }

          ButtonGroup {
            value: root.uploadAlertScale
            options: root.magnitudeChips
            foreground: Color.popups.text
            background: Color.popups.background
            accent: Color.accent
            fontFamily: Style.font.family
            onChanged: function(value) { root.setUploadAlertScale(value) }
          }
        }

        Text {
          text: "Alert color"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.colorChoices.length
            delegate: Rectangle {
              required property int index
              readonly property string swatch: root.colorChoices[index]
              width: Style.space(22)
              height: Style.space(22)
              radius: width / 2
              color: swatch === "" ? "transparent" : swatch
              border.width: root.alertColor === swatch ? 2 : 1
              border.color: root.alertColor === swatch ? Color.accent : Qt.darker(Color.popups.text, 1.6)

              Text {
                visible: swatch === ""
                anchors.centerIn: parent
                text: "∅"
                color: Color.popups.text
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setAlertColor(swatch)
              }
            }
          }
        }
      }
    }
  }
}

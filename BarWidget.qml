import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "dansmith888.bandwidth"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var panel = panelLoader.item
    if (!panel) return
    panel.bar = root.bar
    panel.settings = root.settings
    panel.anchorItem = surface
    panel.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  // Matches the tighter margin the CPU and GPU pills use, so the three sit
  // the same distance apart as the bar's other widgets.
  implicitWidth: row.implicitWidth + Style.space(5) * 2
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // One source of truth for the mark, so the pill and the width it reserves
  // can never drift apart. Same shape as the CPU and GPU pills.
  readonly property string markGlyph: "󰓅"
  readonly property bool showIcon: panelLoader.item ? panelLoader.item.showIcon === true : true

  readonly property string downloadIcon: panelLoader.item ? panelLoader.item.downloadIcon : "↓"
  readonly property string uploadIcon: panelLoader.item ? panelLoader.item.uploadIcon : "↑"
  readonly property string downloadLabel: downloadIcon + (panelLoader.item ? panelLoader.item.barDownloadText : "…")
  readonly property string uploadLabel: uploadIcon + (panelLoader.item ? panelLoader.item.barUploadText : "…")

  // Widest realistic reading, used only to reserve a stable column width.
  readonly property string widestReading: panelLoader.item
    ? Model.widestReading(panelLoader.item.unitSystem, panelLoader.item.unitScale)
    : "999G"

  // Middle-click lands in btop. -or-focus-tui reuses an existing btop window
  // instead of stacking up terminals.
  readonly property var btopCommand: ["omarchy-launch-or-focus-tui", "btop"]

  readonly property string tooltipText: {
    var panel = panelLoader.item
    if (!panel) return "Network Speed"
    var top = panel.networkProcesses && panel.networkProcesses.length > 0
      ? panel.networkProcesses[0] : null
    return Model.tooltip(panel.resolvedLabel, [
      ["Download", panel.downloadText],
      ["Upload", panel.uploadText],
      ["Busiest", top
        ? top.name + "  \u2193 " + Model.formatRate(top.rxRate, panel.unitSystem, panel.unitScale)
          + "  \u2191 " + Model.formatRate(top.txRate, panel.unitSystem, panel.unitScale)
        : ""]
    ])
  }

  // Reserving a width per column keeps the pill — and everything beside it in
  // the bar — still as digits come and go. Reserving the *theoretical* widest
  // reading buys that with a permanent gap, which is worse than the fidget it
  // fixes. So reserve what each column has actually needed: grow to fit,
  // never shrink. widestReading changes only when the unit system or scale
  // does, which is exactly when the reserves should start over.
  property real downloadReserve: 0
  property real uploadReserve: 0
  onWidestReadingChanged: { downloadReserve = 0; uploadReserve = 0 }

  // A WidgetButton with its own label hidden: the readings are drawn on top
  // as two independently-coloured Texts, but hover, click and the bar's
  // tooltip service all come from the standard component.
  WidgetButton {
    id: surface
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.tooltipText

    onPressed: function(b) {
      // Middle-click lands in btop; anything else opens the panel.
      if (b === Qt.MiddleButton) Quickshell.execDetached(root.btopCommand)
      else if (panelLoader.item) panelLoader.item.toggle()
    }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {

        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showIcon
        text: root.markGlyph
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {

        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        // A pinned width from the LAYOUT section overrides the reserve.
        width: (panelLoader.item && panelLoader.item.speedWidth > 0)
          ? panelLoader.item.speedWidth
          : Math.max(root.downloadReserve, implicitWidth)
        onImplicitWidthChanged: if (implicitWidth > root.downloadReserve) root.downloadReserve = implicitWidth
        horizontalAlignment: (panelLoader.item && panelLoader.item.speedWidth > 0) ? Text.AlignRight : Text.AlignLeft
        elide: Text.ElideRight
        text: root.downloadLabel
        color: {
          var c = panelLoader.item ? panelLoader.item.downloadTierColor : ""
          return c && c !== "" ? c : (root.bar ? root.bar.foreground : Color.foreground)
        }
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {

        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        width: (panelLoader.item && panelLoader.item.speedWidth > 0)
          ? panelLoader.item.speedWidth
          : Math.max(root.uploadReserve, implicitWidth)
        onImplicitWidthChanged: if (implicitWidth > root.uploadReserve) root.uploadReserve = implicitWidth
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
        text: root.uploadLabel
        color: {
          var c = panelLoader.item ? panelLoader.item.uploadTierColor : ""
          return c && c !== "" ? c : (root.bar ? root.bar.foreground : Color.foreground)
        }
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}

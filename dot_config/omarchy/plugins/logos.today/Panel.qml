import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// One place for what needs attention today. The panel only reads a cache file
// that a collector outside this public repo writes on a timer; it never talks
// to the network itself. Strings from that file are untrusted: they are shown
// only through PlainText (see tests/).
Panel {
  id: root
  moduleName: "logos.today"
  ipcTarget: "logos.today"

  readonly property string cachePath: Quickshell.env("HOME") + "/.cache/logos-today.json"
  readonly property string collector: "$HOME/.local/bin/today-collect"
  readonly property string asker: "$HOME/.local/bin/today-ask"

  property var model: null
  property real now: Date.now() / 1000
  readonly property bool stale: Model.stale(model, now)
  readonly property int attention: Model.attention(model)
  readonly property var next: model ? model.calendar.next : null

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function clock(seconds) {
    return new Date(seconds * 1000).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), "HH:mm")
  }

  function meetingTime(next) {
    var start = Model.localDate(next.start)
    if (!start) return ""
    return start.toLocaleString(Qt.locale(Commons.I18n.formatLocale), "ddd d MMM HH:mm") + " - " + next.end.slice(11, 16)
  }

  // Fixed command, the address as one quoted argument, and only the two link shapes.
  function openUrl(url) {
    if (!(Model.isAdoUrl(url) || Model.isTicketUrl(url)) || !root.bar) return
    root.bar.run("xdg-open " + Util.shellQuote(url))
    root.close()
  }

  // Opens a terminal where the assistant walks through one item or all of
  // them. The prompt is built by the command; from here only a fixed word or
  // "reminder" with a checked file stem goes out.
  function ask(what, stem) {
    var args = what === "kit" || what === "all" ? what
      : what === "reminder" && Model.isStem(stem) ? "reminder " + Util.shellQuote(stem) : ""
    if (!root.bar || args === "") return
    root.bar.run(root.asker + " " + args)
    root.close()
  }

  onOpenedChanged: if (opened) file.reload()

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // These live outside the panel content, which is only built on first open:
  // the badge needs the data while the panel is closed.
  FileView {
    id: file
    path: root.cachePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.model = Model.parse(text())
    onLoadFailed: root.model = null
  }

  // The collector replaces the file by rename, which can lose the watch, so
  // also reload every minute; the same tick ages the data into "stale".
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: { root.now = Date.now() / 1000; file.reload() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    // A number or "!" only, never text from the file.
    labelText: vertical ? "" : (root.stale ? "!" : (root.attention > 0 ? String(root.attention) : ""))
    slotSize: Style.bar.iconSlot * (labelText !== "" ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // shortcut: mouse only inside the panel (Esc and Tab work), add a row cursor if the keyboard is wanted
      Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: column
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: heading.implicitHeight

            Label {
              id: heading
              text: strings.t("title")
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Label {
              anchors.right: parent.right
              anchors.baseline: heading.baseline
              width: Math.min(implicitWidth, parent.width - heading.width - Style.space(10))
              dim: !root.stale
              color: root.stale ? root.bar.urgent : root.bar.foreground
              font.pixelSize: Style.font.caption
              text: !root.model ? strings.t("noData")
                : strings.t(root.stale ? "stale" : "updated").arg(root.clock(root.model.generated))
            }
          }

          Entry {
            visible: !!root.model
            title: strings.t("askAll")
            ask: "all"
          }

          // ---------- 1. Reminders ----------
          Header { text: strings.t("reminders") }
          Problem { text: root.model ? root.model.reminders.error : "" }

          Repeater {
            model: root.model ? root.model.reminders.items : []
            Entry {
              required property var modelData
              title: modelData.title
              side: modelData.due
              detail: modelData.description
              ask: modelData.stem !== "" ? "reminder" : ""
              stem: modelData.stem
            }
          }

          Label {
            visible: !!root.model && root.model.reminders.error === "" && root.model.reminders.items.length === 0
            dim: true
            text: strings.t("reminders.none")
          }

          Label {
            visible: !!root.model && root.model.reminders.later + root.model.reminders.undated > 0
            dim: true
            font.pixelSize: Style.font.caption
            text: root.model ? strings.t("reminders.rest")
              .arg(Commons.I18n.formatNumber(root.model.reminders.later))
              .arg(Commons.I18n.formatNumber(root.model.reminders.undated)) : ""
          }

          Repeater {
            model: root.model ? root.model.reminders.timers : []
            Entry {
              required property var modelData
              title: modelData.title
              side: modelData.due
            }
          }

          // ---------- 2. Reviews and approvals ----------
          PanelSeparator { foreground: root.bar.foreground }

          Item {
            width: parent.width
            implicitHeight: Math.max(waitingHeader.implicitHeight, adoSwitch.implicitHeight)

            Header {
              id: waitingHeader
              anchors.verticalCenter: parent.verticalCenter
              text: strings.t("waiting")
            }

            ToggleSwitch {
              id: adoSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              trackHeight: Style.space(16)
              foreground: root.bar.foreground
              checked: !!root.model && root.model.ado.enabled
              // The switch moves when the collector has rewritten the file (after any run in progress).
              onToggled: if (root.bar) root.bar.run(root.collector + (checked ? " ado off" : " ado on"))
            }
          }

          Problem { text: root.model ? root.model.ado.error : "" }

          Repeater {
            model: root.model ? root.model.ado.items : []
            Entry {
              required property var modelData
              title: modelData.title
              side: modelData.approval ? strings.t("waiting.approval") : ""
              detail: modelData.where
              url: modelData.url
            }
          }

          Label {
            visible: !!root.model && root.model.ado.error === "" && root.model.ado.items.length === 0
            dim: true
            text: strings.t(root.model && !root.model.ado.enabled ? "waiting.off" : "waiting.none")
          }

          // ---------- 3. Tickets ----------
          PanelSeparator { foreground: root.bar.foreground }
          Header { text: strings.t("plane") }
          Problem { text: root.model ? root.model.plane.error : "" }

          Label {
            visible: !!root.model && root.model.plane.skipped
            dim: true
            font.pixelSize: Style.font.caption
            text: strings.t("plane.skipped")
          }

          Repeater {
            model: root.model ? root.model.plane.items : []
            Entry {
              required property var modelData
              title: modelData.title
              side: modelData.id
              detail: modelData.state + (modelData.priority !== "" && modelData.priority !== "none" ? " · " + modelData.priority : "")
              url: modelData.url
            }
          }

          Label {
            visible: !!root.model && root.model.plane.error === "" && root.model.plane.items.length === 0
            dim: true
            text: strings.t("plane.none")
          }

          Label {
            visible: !!root.model && root.model.plane.more > 0
            dim: true
            font.pixelSize: Style.font.caption
            text: root.model ? strings.t("plane.more").arg(Commons.I18n.formatNumber(root.model.plane.more)) : ""
          }

          Label {
            visible: !!root.model && root.model.plane.hidden > 0
            dim: true
            font.pixelSize: Style.font.caption
            text: root.model ? strings.t("plane.hidden").arg(Commons.I18n.formatNumber(root.model.plane.hidden)) : ""
          }

          // ---------- 4. Next meeting ----------
          PanelSeparator { foreground: root.bar.foreground }
          Header { text: strings.t("meeting") }
          Problem { text: root.model ? root.model.calendar.error : "" }

          Entry {
            visible: !!root.next
            title: root.next ? root.next.title : ""
            detail: root.next ? root.meetingTime(root.next) : ""
          }

          Label {
            visible: !!root.model && root.model.calendar.error === "" && !root.next
            dim: true
            text: strings.t("meeting.none")
          }

          // ---------- 5. Backup age ----------
          PanelSeparator { foreground: root.bar.foreground }
          Header { text: strings.t("kit") }
          Problem { text: root.model ? root.model.kit.error : "" }

          // A stale kit is remade with the assistant: the row opens it.
          Entry {
            visible: !!root.model && root.model.kit.error === ""
            titleColor: root.model && root.model.kit.stale ? root.bar.urgent : root.bar.foreground
            ask: root.model && root.model.kit.stale ? "kit" : ""
            title: root.model ? strings.t("kit.ages")
              .arg(Commons.I18n.formatNumber(root.model.kit.recovery))
              .arg(Commons.I18n.formatNumber(root.model.kit.personal)) : ""
          }
        }
      }
    }
  }

  component Label: PlainText {
    property bool dim: false
    color: root.bar.foreground
    opacity: dim ? 0.6 : 1
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    width: Math.min(implicitWidth, parent ? parent.width : implicitWidth)
  }

  component Header: PanelSectionHeader {
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
  }

  // A section's error, as the collector wrote it.
  component Problem: Label {
    visible: text !== ""
    color: root.bar.urgent
    width: parent ? parent.width : implicitWidth
  }

  // Title with an optional right-hand note and a second, dimmer line; a row
  // with a url opens it on click, one with an ask word asks for a walk-through.
  component Entry: Item {
    id: entry
    property string title: ""
    property string side: ""
    property string detail: ""
    property string url: ""
    property string ask: ""
    property string stem: ""
    property color titleColor: root.bar.foreground

    width: parent ? parent.width : 0
    implicitHeight: lines.implicitHeight

    Rectangle {
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      radius: Style.cornerRadius
      color: root.bar.foreground
      opacity: hover.containsMouse ? 0.08 : 0
    }

    Column {
      id: lines
      width: parent.width
      spacing: Style.space(2)

      Item {
        width: parent.width
        implicitHeight: titleText.implicitHeight

        Label {
          id: titleText
          width: parent.width - (sideText.text !== "" ? sideText.width + Style.space(10) : 0)
          text: entry.title
          color: entry.titleColor
        }

        Label {
          id: sideText
          anchors.right: parent.right
          dim: true
          text: entry.side
        }
      }

      Label {
        visible: text !== ""
        width: parent.width
        dim: true
        font.pixelSize: Style.font.caption
        text: entry.detail
      }
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      enabled: entry.url !== "" || entry.ask !== ""
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: entry.url !== "" ? root.openUrl(entry.url) : root.ask(entry.ask, entry.stem)
    }
  }
}

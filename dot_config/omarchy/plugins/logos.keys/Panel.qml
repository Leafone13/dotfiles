import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Logic.js" as Logic

// A bar button and a panel: pick a title, a local command copies what belongs
// to it. The panel only ever holds titles. The command, its list and what it
// copies live in ~/.local/bin/keys, outside this public repo.
Panel {
  id: root
  moduleName: "logos.keys"
  ipcTarget: "logos.keys"

  property var list: null
  property string query: ""
  property string errorKey: ""

  readonly property var shown: list ? Logic.filter(list.groups, query) : []
  // The title Enter copies.
  readonly property string marked: Logic.first(shown)
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  onOpenedChanged: {
    if (!opened) return
    query = ""
    errorKey = ""
    if (!listProc.running) listProc.running = true
  }

  // Only a title the list command printed is ever sent back, and only as "$1",
  // which bash expands without reading it as shell.
  function copy(title) {
    if (copyProc.running || title === "" || !list) return
    if (!list.groups.some(function(group) { return group.items.indexOf(title) >= 0 })) return
    errorKey = ""
    copyProc.command = ["bash", "-c", 'exec timeout 30 "$HOME/.local/bin/keys" --copy "$1"', "bash", title]
    copyProc.running = true
  }

  // bash rather than the command itself, so a missing command still ends as a
  // process that exits and reports below.
  Process {
    id: listProc
    command: ["bash", "-c", 'exec timeout 30 "$HOME/.local/bin/keys" --list']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.list = Logic.parse(text)
        if (!root.list) root.errorKey = "error.list"
      }
    }
  }

  Process {
    id: copyProc
    onExited: function(exitCode) {
      if (exitCode !== 0) { root.errorKey = "error.copy"; return }
      root.close()  // the paste goes elsewhere; the command's own notification confirms the copy
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: strings.t("tooltip")
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent ? panel.loadedContent.field : null
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      property alias field: field
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      blocked: field.activeFocus
      onCloseRequested: root.close()
      onReturnRequested: root.copy(root.marked)
      Component.onCompleted: Qt.callLater(function() { field.forceActiveFocus() })

      Connections {
        target: root
        function onOpenedChanged() { if (root.opened) { field.text = ""; field.forceActiveFocus() } }
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: scroll.width
          spacing: Style.space(8)

          // shortcut: Enter takes the top match and the mouse any row; add an Up/Down cursor if the filter is not enough
          TextField {
            id: field
            width: column.width
            maximumLength: 40
            placeholderText: strings.t("filter.placeholder")
            foreground: root.foreground
            font.family: root.fontFamily
            onTextChanged: root.query = text

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.copy(root.marked)
                event.accepted = true
              }
            }
          }

          PlainText {
            visible: text !== ""
            width: column.width
            wrapMode: Text.Wrap
            maximumLineCount: 3
            text: root.errorKey !== "" ? strings.t(root.errorKey)
              : !root.list ? strings.t("loading")
              : root.shown.length === 0 ? strings.t("none") : ""
            color: root.errorKey !== "" ? Commons.Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.shown

            Column {
              id: group
              required property var modelData
              width: column.width
              spacing: Style.space(2)

              PanelSectionHeader {
                text: group.modelData.name
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: group.modelData.items

                Item {
                  id: row
                  required property string modelData
                  width: group.width
                  implicitHeight: title.implicitHeight + Style.space(8)

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: root.foreground
                    opacity: hover.containsMouse ? 0.14 : (row.modelData === root.marked ? 0.08 : 0)
                  }

                  PlainText {
                    id: title
                    anchors.verticalCenter: parent.verticalCenter
                    x: Style.space(8)
                    width: parent.width - 2 * x
                    text: row.modelData
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copy(row.modelData)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

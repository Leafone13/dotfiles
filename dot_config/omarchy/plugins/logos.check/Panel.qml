import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Logic.js" as Logic

// A bar button and a panel: type a code, see what the check command prints
// for it; a second button asks the same command for the item's intercom
// calls. The command and what it checks in detail live in
// ~/.local/bin/logos-check, outside this public repo.
Panel {
  id: root
  moduleName: "logos.check"

  property bool running: false
  property string errorKey: ""
  property var result: null
  property string code: ""       // the validated code the result is for
  property bool intercom: false  // the running command is the deeper check
  property var extra: null       // its result, shown under the main one

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function tint(state) {
    if (state === "bad") return Commons.Color.urgent
    if (state === "warn") return "#E5C736"  // literal: themes have no warning color
    if (state === "unknown") return root.dim
    return root.foreground
  }

  function run(text, intercom) {
    if (proc.running) return
    var code = String(text).trim()
    extra = null
    if (!intercom) result = null
    if (!Logic.validCode(code)) { errorKey = "error.invalid"; return }
    errorKey = ""
    running = true
    root.intercom = !!intercom
    if (!intercom) root.code = code
    // The code only ever lands in "$1", which bash expands without reading it
    // as shell. bash rather than the command itself, so a missing command
    // still ends as a process that exits and reports through stdout below.
    proc.command = ["bash", "-c", 'exec timeout 120 "$HOME/.local/bin/logos-check" --json ' + (intercom ? "--intercom " : "") + '-- "$1"', "bash", code]
    proc.running = true
  }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Logic.parse(text)
        if (root.intercom) root.extra = parsed
        else root.result = parsed
        root.errorKey = parsed ? "" : "error.failed"
        root.running = false
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
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
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      property alias field: field
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      blocked: field.activeFocus
      onCloseRequested: root.close()
      onReturnRequested: root.run(field.text)
      Component.onCompleted: Qt.callLater(function() { field.forceActiveFocus() })

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

          Row {
            spacing: Style.space(6)

            TextField {
              id: field
              width: Style.space(200)
              maximumLength: 12
              placeholderText: strings.t("input.placeholder")
              foreground: root.foreground
              font.family: root.fontFamily

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.close()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.run(text)
                  event.accepted = true
                }
              }
            }

            Button {
              text: strings.t("run")
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.run(field.text)
            }

            Button {
              text: strings.t("all")
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.run("all")
            }
          }

          Text {
            visible: text !== ""
            textFormat: Text.PlainText
            text: root.running ? strings.t("running") : (root.errorKey !== "" ? strings.t(root.errorKey) : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.result ? root.result.lines : []

            ResultLine {
              required property var modelData
              width: column.width
              label: modelData.label
              stateText: strings.t("state." + modelData.state)
              detail: modelData.detail
              tint: root.tint(modelData.state)
              dim: root.dim
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              labelWidth: Style.space(80)
              stateWidth: Style.space(40)
              spacing: Style.space(8)
            }
          }

          Text {
            visible: root.result !== null
            width: column.width
            textFormat: Text.PlainText
            text: root.result ? root.result.code + ": " + root.result.verdict : ""
            wrapMode: Text.Wrap
            color: root.result ? root.tint(root.result.state) : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Button {
            visible: Logic.single(root.code, root.result)
            text: strings.t("intercom")
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.run(root.code, true)
          }

          Repeater {
            model: Logic.flat(root.extra)

            ResultLine {
              required property var modelData
              width: column.width
              label: modelData.label
              stateText: strings.t("state." + modelData.state)
              detail: modelData.detail
              tint: root.tint(modelData.state)
              dim: root.dim
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              labelWidth: Style.space(80)
              stateWidth: Style.space(40)
              spacing: Style.space(8)
            }
          }
        }
      }
    }
  }
}

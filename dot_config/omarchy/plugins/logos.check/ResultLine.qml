import QtQuick

// One line of the result: label, state word, detail. All three strings come
// from command output, so every Text here is plain text. QtQuick only, so the
// test can load it without the shell.
Row {
  id: root

  property string label: ""
  property string stateText: ""
  property string detail: ""
  property color tint: "white"
  property color dim: "gray"
  property string fontFamily: "monospace"
  property int fontSize: 12
  property real labelWidth: 80
  property real stateWidth: 40

  spacing: 8

  Text {
    objectName: "label"
    textFormat: Text.PlainText
    text: root.label
    width: root.labelWidth
    elide: Text.ElideRight
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  Text {
    objectName: "state"
    textFormat: Text.PlainText
    text: root.stateText
    width: root.stateWidth
    color: root.tint
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  Text {
    objectName: "detail"
    textFormat: Text.PlainText
    text: root.detail
    width: Math.max(0, root.width - root.labelWidth - root.stateWidth - root.spacing * 2)
    wrapMode: Text.Wrap
    color: root.tint
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }
}

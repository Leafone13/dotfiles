import QtQuick

// Every title and group name goes through this: they come from command output,
// and a default (AutoText) Text would render markup in them.
Text {
  textFormat: Text.PlainText
  elide: Text.ElideRight
  maximumLineCount: 1
}

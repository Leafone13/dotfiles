import QtQuick

// Every string from the cache file goes through this: PR and meeting titles are
// written by others, and a default (AutoText) Text would render their markup.
Text {
  textFormat: Text.PlainText
  elide: Text.ElideRight
  maximumLineCount: 1
}

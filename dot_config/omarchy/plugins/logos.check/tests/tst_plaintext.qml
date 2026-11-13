import QtQuick
import QtTest
import ".."
import "../Logic.js" as Logic

// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/
// Markup-shaped command output must stay plain text, and bad input must not
// reach the command.
Item {
  width: 400
  height: 200

  readonly property string markup: "<img src=\"https://example.invalid/t.png\"><b>x</b>"
  readonly property string fixture: JSON.stringify({
    code: markup, state: "<b>", verdict: markup, hint: markup,
    lines: [{ label: markup, state: "bad", detail: markup }, null, { label: 1, state: "nope" }]
  })

  ResultLine { id: line; width: 400 }

  // What a rich-text sink would make of the same string.
  Text { id: rich; textFormat: Text.RichText; text: "<b>x</b>"; font: plain.font }  // no img: the test stays offline
  Text { id: plain; textFormat: Text.PlainText; text: parent.markup; font.family: line.fontFamily; font.pixelSize: line.fontSize }

  TestCase {
    name: "Check"
    when: windowShown

    function test_markup_stays_plain_text() {
      var result = Logic.parse(fixture)
      line.label = result.lines[0].label
      line.stateText = result.lines[0].state
      line.detail = result.lines[0].detail
      var count = 0
      for (var i = 0; i < line.children.length; i++) {
        var item = line.children[i]
        if (item.textFormat === undefined) continue
        count++
        compare(item.textFormat, Text.PlainText, item.objectName)
      }
      compare(count, 3)
      var detail = line.children[2]
      compare(detail.objectName, "detail")
      compare(detail.text, markup)
      // Shown as its literal characters: as wide as the plain reference, not
      // collapsed into one bold letter like the rich one.
      detail.wrapMode = Text.NoWrap
      compare(detail.implicitWidth, plain.implicitWidth)
      verify(rich.implicitWidth < plain.implicitWidth / 4)
    }

    function test_parse_bounds() {
      var result = Logic.parse(fixture)
      compare(result.code.length, 12)
      compare(result.state, "unknown")
      compare(result.lines.length, 3)
      compare(result.lines[1].detail, "")
      compare(result.lines[2].label, "")
      compare(result.lines[2].state, "unknown")
      compare(Logic.parse("not json"), null)
      compare(Logic.parse("[]"), null)
      compare(Logic.parse("{\"lines\": 1}"), null)
      var many = []
      for (var i = 0; i < 100; i++) many.push({ label: "a", state: "ok", detail: new Array(1000).join("x") })
      result = Logic.parse(JSON.stringify({ lines: many }))
      compare(result.lines.length, 60)
      compare(result.lines[0].detail.length, 400)
    }

    function test_code_validation() {
      var good = ["all", "ABC", "a-1", "A23456789012"]
      var bad = ["", "-h", "--json", "a b", "a;id", "$(id)", "`id`", "a'b", "<b>", "A234567890123", "a\nb"]
      for (var i = 0; i < good.length; i++) verify(Logic.validCode(good[i]), good[i])
      for (var j = 0; j < bad.length; j++) verify(!Logic.validCode(bad[j]), bad[j])
    }
  }
}

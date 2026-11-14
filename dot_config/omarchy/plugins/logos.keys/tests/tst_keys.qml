import QtQuick
import QtTest
import "../Logic.js" as Logic
import ".."

// Run with tests/run.sh. Markup-shaped titles from the command stay plain
// text, the list is bounded, and the filter picks what Enter copies.
TestCase {
  id: test
  name: "keys"

  readonly property string markup: "<img src=\"https://example.invalid/t.png\"><b>x</b>"
  readonly property string fixture: JSON.stringify({
    clear_after: 60,
    groups: [
      { name: "First", items: ["alpha one", "Beta two", markup, 7, ""] },
      null,
      { name: markup, items: ["gamma: beta_three"] }
    ]
  })

  Component { id: plain; PlainText {} }
  Component { id: rich; Text {} }

  function test_markup_stays_plain() {
    var list = Logic.parse(fixture)
    var item = plain.createObject(test, { text: list.groups[0].items[2] })
    compare(item.textFormat, Text.PlainText)
    compare(item.text, markup)
    // Shown as its literal characters, not collapsed into one bold letter.
    var richItem = rich.createObject(test, { text: "<b>x</b>", font: item.font })
    verify(richItem.implicitWidth < item.implicitWidth / 4)
  }

  function test_parse_bounds() {
    var list = Logic.parse(fixture)
    compare(list.clearAfter, 60)
    compare(list.groups.length, 3)
    compare(list.groups[0].items.length, 3)
    compare(list.groups[1].items.length, 0)
    compare(list.groups[2].name.length, 40)
    compare(Logic.parse("not json"), null)
    compare(Logic.parse("[]"), null)
    compare(Logic.parse("{\"groups\": 1}"), null)
    compare(Logic.parse("{\"groups\": [], \"clear_after\": \"<b>\"}").clearAfter, 0)
    var many = []
    for (var i = 0; i < 100; i++) many.push(new Array(200).join("x"))
    list = Logic.parse(JSON.stringify({ groups: [{ name: "a", items: many }] }))
    compare(list.groups[0].items.length, 50)
    compare(list.groups[0].items[0].length, 80)
  }

  function test_filter() {
    var groups = Logic.parse(fixture).groups
    compare(Logic.first(Logic.filter(groups, "")), "alpha one")
    compare(Logic.first(Logic.filter(groups, "BETA")), "Beta two")
    compare(Logic.first(Logic.filter(groups, "three beta")), "gamma: beta_three")
    compare(Logic.filter(groups, "beta").length, 2)
    compare(Logic.filter(groups, "nothing").length, 0)
    compare(Logic.first([]), "")
  }
}

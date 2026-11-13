import QtQuick
import QtTest
import "../Model.js" as Model
import ".."

// Run with tests/run.sh. Proves that markup-shaped values from the cache file
// stay plain text, that only the one host's links survive, and that sizes are
// bounded.
TestCase {
  id: test
  name: "today"

  property var model: null
  Component { id: plain; PlainText {} }
  Component { id: rich; Text {} }

  function readFixture() {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("fixture.json"), false)
    request.send()
    return request.responseText
  }

  function initTestCase() {
    model = Model.parse(readFixture())
    verify(model !== null)
  }

  function dynamicStrings() {
    var out = []
    function take(item) { for (var key in item) if (typeof item[key] === "string") out.push(item[key]) }
    model.reminders.items.forEach(take)
    model.reminders.timers.forEach(take)
    model.ado.items.forEach(take)
    take(model.calendar.next)
    out.push(model.ado.error)
    return out
  }

  function test_markup_stays_plain() {
    var strings = dynamicStrings()
    verify(strings.some(function(s) { return s.indexOf("<img") >= 0 }))
    strings.forEach(function(s) {
      var item = plain.createObject(test, { text: s })
      compare(item.textFormat, Text.PlainText)
      compare(item.text, s)
      item.destroy()
    })
  }

  // The same string in a default Text is interpreted (the tags vanish from the
  // layout), in PlainText it is laid out as written.
  function test_plain_differs_from_default_text() {
    var s = model.reminders.items[0].description
    verify(s.indexOf("<b>") === 0)
    var a = plain.createObject(test, { text: s }), b = rich.createObject(test, { text: s })
    verify(a.implicitWidth > b.implicitWidth)
    a.destroy(); b.destroy()
  }

  function test_only_ado_links() {
    var urls = model.ado.items.map(function(i) { return i.url })
    compare(urls, ["https://dev.azure.com/example-org/example-project/_git/example-repo/pullrequest/1", "", "", ""])
    verify(!Model.isAdoUrl("http://dev.azure.com/x"))
    verify(!Model.isAdoUrl("https://dev.azure.com"))
    verify(!Model.isAdoUrl("https://dev.azure.com/a b"))
    verify(!Model.isAdoUrl("https://dev.azure.com/" + "x".repeat(600)))
    verify(!Model.isAdoUrl(null))
  }

  function test_counts() {
    compare(Model.attention(model), 2 + 4 + 1 + 1)  // + the fixture's one failed section
    compare(Model.attention(null), 0)
    verify(model.ado.items[3].approval)
    verify(!Model.stale(model, model.generated + 60))
    verify(Model.stale(model, model.generated + 21 * 60))
    verify(Model.stale(null, 0))
  }

  function test_bounds_and_garbage() {
    var many = []
    for (var i = 0; i < 50; i++) many.push({ title: "x".repeat(999), due: 7, description: null })
    var big = Model.parse(JSON.stringify({ generated: "soon", reminders: { items: many, later: "<b>" }, ado: { items: "nope" }, calendar: { next: "now" }, kit: [] }))
    compare(big.reminders.items.length, Model.MAX_ITEMS)
    compare(big.reminders.items[0].title.length, Model.MAX_TEXT)
    compare(big.reminders.items[0].due, "")
    compare(big.reminders.later, 0)
    compare(big.generated, 0)
    compare(big.ado.items, [])
    compare(big.calendar.next, null)
    compare(big.kit.stale, false)
    compare(Model.parse("<html>"), null)
    compare(Model.parse("[1]"), null)
    compare(Model.parse(""), null)
    compare(Model.parse('{"reminders":{"items":[null,"x",3]}}').reminders.items.length, 3)
  }

  function test_local_date() {
    var d = Model.localDate("2026-01-02T14:05")
    compare([d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), d.getMinutes()], [2026, 0, 2, 14, 5])
    compare(Model.localDate("tomorrow"), null)
  }
}

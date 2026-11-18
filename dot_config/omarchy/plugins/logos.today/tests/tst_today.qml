import QtQuick
import QtTest
import "../Model.js" as Model
import ".."

// Run with tests/run.sh. Proves that markup-shaped values from the cache file
// stay plain text, that only the review host's links and ticket-page links
// survive (each in its own section), and that sizes are bounded.
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
    model.plane.items.forEach(take)
    model.plane.hiddenItems.forEach(take)
    take(model.calendar.next)
    out.push(model.ado.error)
    return out
  }

  function test_markup_stays_plain() {
    var strings = dynamicStrings()
    verify(strings.some(function(s) { return s.indexOf("<img") >= 0 }))
    verify(model.plane.items[0].title.indexOf("<img") >= 0 && model.plane.items[0].state.indexOf("<b>") === 0)
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
    compare(urls, ["https://dev.azure.com/example-org/example-project/_git/example-repo/pullrequest/1", "", "", "", ""])
    verify(!Model.isAdoUrl("http://dev.azure.com/x"))
    verify(!Model.isAdoUrl("https://dev.azure.com"))
    verify(!Model.isAdoUrl("https://dev.azure.com/a b"))
    verify(!Model.isAdoUrl("https://dev.azure.com/" + "x".repeat(600)))
    verify(!Model.isAdoUrl(null))
  }

  function test_only_ticket_links() {
    compare(model.plane.items.map(function(i) { return i.url }),
            ["http://tracker.example.invalid:8090/example-space/browse/EX-1/", "", "", "", ""])
    compare(model.plane.more, 4)
    compare(model.plane.hidden, 3)
    compare(model.plane.hiddenItems.map(function(i) { return [i.id, i.started, i.url !== ""] }),
            [["EX-7", true, true], ["EX-8", false, false]])  // only a real true counts, and only a ticket link opens
    verify(Model.isTicketUrl("https://tracker.example.invalid/example-space/browse/EX-12/"))
    verify(!Model.isTicketUrl("file:///example-space/browse/EX-1/"))
    verify(!Model.isTicketUrl("http://tracker.example.invalid/example-space/browse/EX-1/\n"))
    verify(!Model.isTicketUrl("http://tracker.example.invalid/example-space/browse/EX-1/?x=1"))
    verify(!Model.isTicketUrl("http:///example-space/browse/EX-1/"))
    verify(!Model.isTicketUrl(null))
  }

  // A list kept from an earlier run: shown and counted, never opened; skipped is not a failure.
  function test_stale_tickets() {
    var data = JSON.parse(readFixture())
    data.plane.skipped = true
    var skipped = Model.parse(JSON.stringify(data))
    compare(skipped.plane.items.map(function(i) { return i.url }), ["", "", "", "", ""])
    compare(skipped.plane.items[0].title, model.plane.items[0].title)
    compare(Model.attention(skipped), Model.attention(model))
    data.plane.skipped = false
    data.plane.error = "<img src=https://example.invalid/p>"
    var failed = Model.parse(JSON.stringify(data))
    compare(failed.plane.items[0].url, "")
    compare(Model.attention(failed), Model.attention(model) + 1)
    var item = plain.createObject(test, { text: failed.plane.error })
    compare(item.text, failed.plane.error)
    item.destroy()
  }

  // Hidden tickets never reach the file's items: the badge follows the list, not total or hidden.
  function test_badge_counts_listed_tickets() {
    var data = JSON.parse(readFixture())
    data.plane.items = data.plane.items.slice(0, 2)
    data.plane.hidden = 40
    data.plane.total = 2
    compare(Model.attention(Model.parse(JSON.stringify(data))), Model.attention(model) - 3)
  }

  function test_kit_strings() {  // the panel builds these keys as "kit." + "recovery" / "personal"
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../i18n/en.json"), false)
    request.send()
    var strings = JSON.parse(request.responseText)
    verify(strings["kit.recovery"].indexOf("%1") >= 0 && strings["kit.personal"].indexOf("%1") >= 0 && !!strings["kit.remake"])
  }

  function test_stems() {
    compare(model.reminders.items.map(function(i) { return i.stem }), ["", "remind-water-plants", ""])
    compare(model.reminders.timers[0].stem, "")
    verify(!Model.isStem("../x") && !Model.isStem("a b") && !Model.isStem("A") && !Model.isStem("a\n") && !Model.isStem("") && !Model.isStem(null))
    verify(!Model.isStem("a".repeat(101)))
  }

  function test_counts() {
    compare(Model.attention(model), 3 + 5 + 5 + 1 + 1)  // + the fixture's one failed section
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
    compare(big.plane, { error: "", skipped: false, items: [], more: 0, hidden: 0, hiddenItems: [] })  // a cache file from before the tickets section
    compare(big.calendar.next, null)
    compare(big.kit.stale, false)
    compare(big.kit.staleKits, [])
    compare(model.kit.staleKits, ["recovery"])  // unknown names from the cache file are dropped
    compare(Model.parse("<html>"), null)
    compare(Model.parse("[1]"), null)
    compare(Model.parse(""), null)
    compare(Model.parse('{"reminders":{"items":[null,"x",3]}}').reminders.items.length, 3)
  }

  function test_days_off() {
    compare(model.calendar.off.length, 3)  // the "<b>" range is dropped
    function f(date, pattern) { return Qt.formatDate(date, pattern) }
    var texts = model.calendar.off.map(function(range) { return Model.offText(range, f) })
    compare(texts[0], Qt.formatDate(new Date(2026, 0, 7), "ddd d") + " – " + Qt.formatDate(new Date(2026, 0, 8), "ddd d MMM"))
    verify(texts[1].indexOf("MMM") < 0 && texts[1].split(" – ").length === 2)  // across months: both sides name the month
    compare(texts[2], Qt.formatDate(new Date(2026, 1, 10), "ddd d MMM"))
  }

  function test_local_date() {
    var d = Model.localDate("2026-01-02T14:05")
    compare([d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), d.getMinutes()], [2026, 0, 2, 14, 5])
    compare(Model.localDate("tomorrow"), null)
  }
}

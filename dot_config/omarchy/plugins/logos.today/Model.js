.pragma library

// The cache file is written by a script outside this repo. Everything read
// from it is bounded and typed here before the panel shows it.

var MAX_ITEMS = 20
var MAX_HIDDEN = 50
var MAX_TEXT = 200
var STALE_SECONDS = 20 * 60

function str(value) { return typeof value === "string" ? value.slice(0, MAX_TEXT) : "" }
function num(value) { value = Number(value); return isFinite(value) ? Math.floor(value) : 0 }
function obj(value) { return value && typeof value === "object" ? value : {} }
function list(value, each, max) {
  return Array.isArray(value) ? value.slice(0, max || MAX_ITEMS).map(function(item) { return each(obj(item)) }) : []
}

// The only links the panel opens: the review host, and ticket pages.
function isAdoUrl(url) {
  return typeof url === "string" && url.length <= 500 && /^https:\/\/dev\.azure\.com\/[\x21-\x7e]*$/.test(url)
}

// A ticket page on whatever host the collector names (a self-hosted tracker, so
// the host is not fixed here and plain http is accepted): only this exact shape,
// only for the tickets section, and only while that section's data is current.
function isTicketUrl(url) {
  return typeof url === "string" && url.length <= 200
    && /^https?:\/\/[a-z0-9.-]+(:\d{1,5})?\/[a-z0-9-]+\/browse\/[A-Z][A-Z0-9]*-\d+\/$/.test(url)
}

// A reminder's file stem, passed as an argument to the ask command.
function isStem(stem) { return typeof stem === "string" && /^[a-z0-9-]{1,100}$/.test(stem) }

function parse(text) {
  var data
  try { data = JSON.parse(text) } catch (e) { return null }
  if (!data || typeof data !== "object" || Array.isArray(data)) return null
  var reminders = obj(data.reminders), ado = obj(data.ado), calendar = obj(data.calendar), kit = obj(data.kit)
  var plane = obj(data.plane)
  function dated(item) {
    return { title: str(item.title), due: str(item.due), description: str(item.description),
             stem: isStem(item.stem) ? item.stem : "" }
  }
  // A list kept from an earlier run (the source was skipped or failed) is shown, but its links are not opened.
  var current = plane.skipped !== true && str(plane.error) === ""
  function ticket(item) {
    return { id: str(item.id), title: str(item.title), state: str(item.state), priority: str(item.priority),
             url: current && isTicketUrl(item.url) ? item.url : "", started: item.started === true }
  }
  var tickets = list(plane.items, ticket)
  return {
    generated: num(data.generated),
    reminders: {
      error: str(reminders.error),
      items: list(reminders.items, dated),
      timers: list(reminders.timers, dated),
      later: num(reminders.later),
      undated: num(reminders.undated)
    },
    ado: {
      enabled: ado.enabled !== false,
      error: str(ado.error),
      items: list(ado.items, function(item) {
        return { approval: item.kind === "approval", title: str(item.title), where: str(item.where),
                 url: isAdoUrl(item.url) ? item.url : "" }
      })
    },
    plane: { error: str(plane.error), skipped: plane.skipped === true, items: tickets,
             more: Math.max(0, num(plane.total) - tickets.length), hidden: Math.max(0, num(plane.hidden)),
             hiddenItems: list(plane.hidden_items, ticket, MAX_HIDDEN) },
    calendar: {
      error: str(calendar.error),
      next: calendar.next && typeof calendar.next === "object"
        ? { start: str(calendar.next.start), end: str(calendar.next.end), title: str(calendar.next.title) } : null
    },
    kit: { error: str(kit.error), stale: kit.stale === true, recovery: num(kit.recovery), personal: num(kit.personal) }
  }
}

// What the badge counts: due reminders, reviews and approvals waiting, open tickets (the collector has
// already left out the hidden ones), a stale backup, and one per section that failed, so a broken
// source never reads as all clear. A skipped section is not a failure.
function attention(model) {
  if (!model) return 0
  var failed = [model.reminders, model.ado, model.plane, model.calendar, model.kit].filter(function (s) { return s.error }).length
  return model.reminders.items.length + model.ado.items.length + model.plane.items.length + (model.kit.stale ? 1 : 0) + failed
}

function stale(model, nowSeconds) { return !model || nowSeconds - model.generated > STALE_SECONDS }

// "2026-11-13T14:00" as local time, built by parts: Date's own parsing of a
// zoneless string differs between engines. null when it isn't one.
function localDate(iso) {
  var m = /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d)/.exec(String(iso))
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5])) : null
}

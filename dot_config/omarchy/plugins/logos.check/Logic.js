.pragma library

// The typed code is untrusted: it must match this before it becomes an argument.
function validCode(text) {
  return /^[A-Za-z0-9][A-Za-z0-9-]{0,11}$/.test(String(text))
}

var states = ["ok", "warn", "bad", "unknown"]

function state(value) { return states.indexOf(value) >= 0 ? value : "unknown" }
function str(value, max) { return typeof value === "string" ? value.slice(0, max) : "" }

// The command's JSON, bounded. null when it is not the expected object.
function parse(text) {
  var data
  try { data = JSON.parse(text) } catch (e) { return null }
  if (!data || typeof data !== "object" || !Array.isArray(data.lines)) return null
  return {
    code: str(data.code, 12),
    state: state(data.state),
    verdict: str(data.verdict, 400),
    hint: str(data.hint, 600),
    lines: data.lines.slice(0, 60).map(function(line) {
      line = line || {}
      return { label: str(line.label, 24), state: state(line.state), detail: str(line.detail, 400) }
    })
  }
}

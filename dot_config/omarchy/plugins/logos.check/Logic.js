.pragma library

// The typed code is untrusted: it must match this before it becomes an argument.
function validCode(text) {
  return /^[A-Za-z0-9][A-Za-z0-9-]{0,11}$/.test(String(text))
}

var states = ["ok", "warn", "bad", "unknown"]

function state(value) { return states.indexOf(value) >= 0 ? value : "unknown" }
function str(value, max) { return typeof value === "string" ? value.slice(0, max) : "" }

// True when the result is one item's own check: only then the deeper check applies.
function single(code, result) {
  return !!result && result.lines.length > 0 && validCode(code) && String(code).toLowerCase() !== "all"
}

// A result as lines only, verdict last, so it all renders through ResultLine.
// The command's hint field is deliberately not shown.
function flat(result) {
  if (!result) return []
  return result.lines.concat([{ label: result.code, state: result.state, detail: result.verdict }])
}

// The command's JSON, bounded. null when it is not the expected object.
function parse(text) {
  var data
  try { data = JSON.parse(text) } catch (e) { return null }
  if (!data || typeof data !== "object" || !Array.isArray(data.lines)) return null
  return {
    code: str(data.code, 12),
    state: state(data.state),
    verdict: str(data.verdict, 400),
    lines: data.lines.slice(0, 60).map(function(line) {
      line = line || {}
      return { label: str(line.label, 24), state: state(line.state), detail: str(line.detail, 400) }
    })
  }
}

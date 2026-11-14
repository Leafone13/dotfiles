.pragma library

function str(value, max) { return typeof value === "string" ? value.slice(0, max) : "" }

// The list command's JSON, bounded. null when it is not the expected object.
function parse(text) {
  var data
  try { data = JSON.parse(text) } catch (e) { return null }
  if (!data || typeof data !== "object" || !Array.isArray(data.groups)) return null
  var seconds = Number(data.clear_after)
  return {
    clearAfter: seconds >= 1 && seconds <= 3600 ? Math.round(seconds) : 0,
    groups: data.groups.slice(0, 10).map(function(group) {
      group = group || {}
      var items = Array.isArray(group.items) ? group.items : []
      return {
        name: str(group.name, 40),
        items: items.slice(0, 50).map(function(title) { return str(title, 80) }).filter(function(title) { return title !== "" })
      }
    })
  }
}

// Groups with only the titles that hold every typed word, any case; empty groups dropped.
function filter(groups, query) {
  var words = String(query).toLowerCase().split(/\s+/).filter(function(word) { return word !== "" })
  return groups.map(function(group) {
    return {
      name: group.name,
      items: group.items.filter(function(title) {
        var low = title.toLowerCase()
        return words.every(function(word) { return low.indexOf(word) >= 0 })
      })
    }
  }).filter(function(group) { return group.items.length > 0 })
}

function first(groups) { return groups.length > 0 ? groups[0].items[0] : "" }

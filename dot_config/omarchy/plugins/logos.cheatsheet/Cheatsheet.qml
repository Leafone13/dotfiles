import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

// Fullscreen tmux cheatsheet in the Launchpad style: blurred wallpaper with a
// theme wash, the sections laid out in columns, type-to-search. The text comes
// from `tmux-cheatsheet --print` (lines "keys → description", "── SECTION ──").
// Summon with `omarchy-shell shell toggle logos.cheatsheet` (CTRL+SHIFT+grave).
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  // [{ title, rows: [{ keys, desc }] }] as parsed, and after the filter.
  property var sections: []
  readonly property var shownSections: root.filterSections(root.sections, root.filterText)
  property real reveal: 0
  readonly property bool shown: root.opened || root.reveal > 0.001

  readonly property string home: Quickshell.env("HOME")
  readonly property string blurredWallpaper: "file://" + (Quickshell.env("XDG_CACHE_HOME") || (root.home + "/.cache")) + "/omarchy-launchpad/blur.jpg"
  readonly property color themeBg: Color.background
  readonly property color themeFg: Color.foreground
  readonly property bool lightTheme: root.luma(Color.background) > root.luma(Color.foreground)
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int rowHeight: 27
  readonly property int fontSize: 15

  function luma(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  function fgA(a) { return Qt.rgba(root.themeFg.r, root.themeFg.g, root.themeFg.b, a) }
  function bgA(a) { return Qt.rgba(root.themeBg.r, root.themeBg.g, root.themeBg.b, a) }

  NumberAnimation {
    id: revealAnim
    target: root
    property: "reveal"
    duration: 220
    easing.type: Easing.OutCubic
  }

  function pluginId() {
    return (root.manifest && root.manifest.id) || "logos.cheatsheet"
  }

  function open(payloadJson) {
    root.filterText = ""
    root.jumpTo(0)
    root.opened = true
    source.running = true
    revealAnim.stop()
    revealAnim.to = 1
    revealAnim.start()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    revealAnim.stop()
    revealAnim.to = 0
    revealAnim.start()
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId())
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function parse(text) {
    var out = []
    var current = { title: "", rows: [] }
    var lines = String(text || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (!line.trim()) continue
      var parts = line.split("→")
      var left = parts[0].trim()
      var right = parts.slice(1).join("→").trim()
      var header = left.match(/^──\s*(.*?)\s*──$/)
      if (header) {
        if (current.rows.length) out.push(current)
        current = { title: header[1], rows: [] }
      } else {
        current.rows.push({ keys: left, desc: right })
      }
    }
    if (current.rows.length) out.push(current)
    // The untitled block at the top is the prefix and basics.
    if (out.length && !out[0].title) out[0].title = "ОСНОВНОЕ"
    root.sections = out
  }

  function filterSections(sections, text) {
    var q = String(text || "").trim().toLowerCase()
    if (!q) return sections
    var out = []
    for (var i = 0; i < sections.length; i++) {
      var rows = []
      var titleHit = sections[i].title.toLowerCase().indexOf(q) !== -1
      for (var j = 0; j < sections[i].rows.length; j++) {
        var r = sections[i].rows[j]
        if (titleHit || r.keys.toLowerCase().indexOf(q) !== -1 || r.desc.toLowerCase().indexOf(q) !== -1) rows.push(r)
      }
      if (rows.length) out.push({ title: sections[i].title, rows: rows })
    }
    return out
  }

  // Whole sections into columns of about equal height, in reading order.
  function columnsFor(sections, count) {
    var total = 0
    for (var i = 0; i < sections.length; i++) total += sections[i].rows.length + 2
    var target = total / count
    var cols = [[]], h = 0
    for (var k = 0; k < sections.length; k++) {
      var sh = sections[k].rows.length + 2
      if (h > 0 && h + sh / 2 > target && cols.length < count) { cols.push([]); h = 0 }
      cols[cols.length - 1].push(sections[k])
      h += sh
    }
    return cols
  }

  function setFilter(text) {
    root.filterText = text
    root.jumpTo(0)
  }

  // Scrolling, the Launchpad paging principles applied to a continuous list
  // (see ~/Work/omarchy-launchpad/research/paging-analysis.md):
  // - two fingers move the text 1:1 (same gain as the Launchpad pages);
  // - past an end the overflow goes through an iOS rubber band;
  // - on lift the visible velocity (a 50 ms fit times the rubber slope) goes
  //   into momentum that decays like a flick, or a spring back at an end;
  // - a whole silent frame after fast motion counts as the lift, because
  //   ScrollEnd arrives 6-107 ms late; motion resuming re-takes the text;
  // - fingers resting 150+ ms before lift-off mean no flick;
  // - the mouse wheel and keys glide to a target instead of jumping.
  property real scrollY: 0
  readonly property real maxScroll: Math.max(0, root.contentHeight - scroller.height)
  readonly property real contentHeight: columns.height + Math.round(panel.height * 0.06)
  readonly property real swipeGain: 0.28
  // "end" = no gesture, "drag" = fingers moving, "released" = settling
  // early before ScrollEnd.
  property string dragState: "end"
  property real dragRaw: 0
  property var dragSamples: []
  property real lastMotion: 0

  readonly property real rubberC: 0.55
  function rubberD() { return Math.max(60, scroller.height * 0.12) }
  function rubberB(x) { var d = root.rubberD(); return (1 - 1 / (x * root.rubberC / d + 1)) * d }
  function rubberInv(y) { var d = root.rubberD(); return (1 / (1 - Math.min(0.999, y / d)) - 1) * d / root.rubberC }
  function rubberSlope(x) { var k = x * root.rubberC / root.rubberD() + 1; return 1 / (k * k) }
  function softClamp(x) {
    if (x < 0) return -root.rubberB(-x)
    if (x > root.maxScroll) return root.maxScroll + root.rubberB(x - root.maxScroll)
    return x
  }
  function softSlope(x) {
    if (x < 0) return root.rubberSlope(-x)
    if (x > root.maxScroll) return root.rubberSlope(x - root.maxScroll)
    return 1
  }
  function unclamp(y) {
    if (y < 0) return -root.rubberInv(-y)
    if (y > root.maxScroll) return root.maxScroll + root.rubberInv(y - root.maxScroll)
    return y
  }

  // Least-squares slope (px/ms) of samples newer than windowMs before `at`.
  function fitSlope(samples, at, windowMs) {
    var n = 0, st = 0, sx = 0, stt = 0, stx = 0
    for (var i = 0; i < samples.length; i++) {
      var p = samples[i]
      if (at - p.t > windowMs) continue
      var t = p.t - at
      n++; st += t; sx += p.x; stt += t * t; stx += t * p.x
    }
    var den = n * stt - st * st
    if (n < 3 || den === 0) return 0
    return (n * stx - st * sx) / den
  }
  // Strongest 3-sample fit in the last 80 ms: is this a flick at all.
  function commitVelocity() {
    var s = root.dragSamples, best = 0
    for (var i = 2; i < s.length; i++) {
      if (root.lastMotion - s[i].t > 80) continue
      var v = root.fitSlope(s.slice(i - 2, i + 1), s[i].t, 1000)
      if (Math.abs(v) > Math.abs(best)) best = v
    }
    return best
  }
  // 50 ms fit, without a final lift-off event much slower than the one before.
  function launchVelocity() {
    var s = root.dragSamples.slice()
    if (s.length >= 3) {
      var a = s[s.length - 1], b = s[s.length - 2], c = s[s.length - 3]
      var last = (a.x - b.x) / Math.max(1, a.t - b.t), prev = (b.x - c.x) / Math.max(1, b.t - c.t)
      if (Math.abs(last) < 0.6 * Math.abs(prev)) s.pop()
    }
    return root.fitSlope(s, s.length ? s[s.length - 1].t : 0, 50)
  }

  function handleWheel(wheel) {
    var touchpad = wheel.phase !== Qt.NoScrollPhase || wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0
    if (!touchpad) {
      root.glideBy(-wheel.angleDelta.y / 120 * root.rowHeight * 3)
      return
    }
    var now = Date.now()
    if (wheel.phase === Qt.ScrollBegin || root.dragState === "end") {
      motion.stop()
      root.dragState = "drag"
      root.dragRaw = root.unclamp(root.scrollY)
      root.dragSamples = [{ t: now, x: root.dragRaw }]
      root.lastMotion = now
      if (wheel.phase === Qt.ScrollBegin) return
    }
    if (wheel.phase === Qt.ScrollEnd) {
      // An early release already started the settle; keep it running.
      if (root.dragState !== "released") root.release()
      root.dragState = "end"
      return
    }
    if (root.dragState === "released") {
      // The fingers were still on the pad: take the text back where it is.
      motion.stop()
      root.dragState = "drag"
      root.dragRaw = root.unclamp(root.scrollY)
      root.dragSamples = [{ t: now - 1, x: root.dragRaw }]
    }
    var dy = wheel.angleDelta.y
    root.dragRaw -= dy * root.swipeGain
    root.scrollY = root.softClamp(root.dragRaw)
    if (dy !== 0) root.lastMotion = now
    var samples = root.dragSamples.concat([{ t: now, x: root.dragRaw }])
    while (samples.length > 3 && now - samples[0].t > 150) samples.shift()
    root.dragSamples = samples
  }

  function release() {
    var rested = Date.now() - root.lastMotion > 150
    // px/s of what is on screen: near an end the text barely moves.
    var v = rested ? 0 : root.launchVelocity() * root.softSlope(root.dragRaw) * 1000
    root.settle(v)
  }

  // From the current position and velocity (px/s): spring back if past an
  // end, otherwise coast.
  function settle(v) {
    motion.stop()
    if (root.scrollY < 0 || root.scrollY > root.maxScroll) {
      root.springTo(root.scrollY < 0 ? 0 : root.maxScroll, v)
    } else if (Math.abs(v) > 30) {
      motion.mode = "coast"
      motion.v = v
      motion.start()
    }
  }

  // Critically damped spring to `target`, starting at velocity v0 (px/s);
  // toward the target capped so the landing overshoots at most ~2%.
  function springTo(target, v0) {
    var x0 = root.scrollY - target
    var v = v0 || 0
    var cap = 1.3 * motion.omega * Math.abs(x0)
    if (x0 !== 0 && v * -Math.sign(x0) > cap) v = -Math.sign(x0) * cap
    motion.mode = "spring"
    motion.target = target
    motion.x0 = x0
    motion.v0 = v
    motion.t = 0
    motion.start()
  }

  // Wheel and keys: glide toward a target that further notches extend.
  function glideBy(delta) {
    if (motion.mode !== "glide" || !motion.running) motion.target = root.scrollY
    root.glideTo(motion.target + delta)
  }
  function glideTo(y) {
    root.dragState = "end"
    motion.stop()
    motion.mode = "glide"
    motion.target = Math.max(0, Math.min(root.maxScroll, y))
    motion.start()
  }

  function jumpTo(y) {
    motion.stop()
    root.dragState = "end"
    root.scrollY = Math.max(0, Math.min(root.maxScroll, y))
  }

  FrameAnimation {
    id: motion
    property string mode: ""
    // coast
    property real v: 0
    // spring: x(t) = T + (x0 + (v0 + w*x0) t) e^(-w t), the Launchpad's ω
    readonly property real omega: 34
    property real target: 0
    property real x0: 0
    property real v0: 0
    property real t: 0
    onTriggered: {
      var dt = Math.min(0.05, frameTime)
      if (mode === "coast") {
        // Flick deceleration 0.997 per ms (GNOME's projection rate).
        v *= Math.pow(0.997, dt * 1000)
        root.scrollY += v * dt
        if (root.scrollY < 0 || root.scrollY > root.maxScroll) {
          // Hit an end: bounce off it with the speed left.
          root.springTo(root.scrollY < 0 ? 0 : root.maxScroll, v)
          return
        }
        if (Math.abs(v) < 8) stop()
      } else if (mode === "spring") {
        t += dt
        var e = Math.exp(-omega * t)
        var x = (x0 + (v0 + omega * x0) * t) * e
        var vel = (v0 - omega * (v0 + omega * x0) * t) * e
        if (Math.abs(x) < 0.3 && Math.abs(vel) < 5) { root.scrollY = target; stop(); return }
        root.scrollY = target + x
      } else if (mode === "glide") {
        var diff = target - root.scrollY
        if (Math.abs(diff) < 0.5) { root.scrollY = target; stop(); return }
        root.scrollY += diff * (1 - Math.exp(-dt / 0.07))
      } else {
        stop()
      }
    }
  }

  // Early release: see the scrolling notes above.
  FrameAnimation {
    running: root.dragState === "drag"
    onTriggered: {
      if (Date.now() - root.lastMotion < 17) return
      if (Math.abs(root.commitVelocity() * 1000) < 300) return
      root.release()
      root.dragState = "released"
    }
  }

  Process {
    id: source
    command: [root.home + "/.local/bin/tmux-cheatsheet", "--print"]
    stdout: StdioCollector { onStreamFinished: root.parse(this.text) }
  }
  Component.onCompleted: source.running = true

  // Kept mapped so opening does not wait for the surface; while hidden it
  // draws nothing and takes no input.
  PanelWindow {
    id: panel
    visible: true
    mask: root.shown ? null : emptyMask
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-cheatsheet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Region { id: emptyMask }

    // The Launchpad's pre-blurred wallpaper (it keeps the cache current).
    Image {
      anchors.fill: parent
      source: root.blurredWallpaper
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      opacity: root.reveal
      visible: opacity > 0
    }

    // Theme wash; a bit stronger than the Launchpad's, for dense text.
    Rectangle {
      anchors.fill: parent
      color: root.themeBg
      opacity: (root.lightTheme ? 0.72 : 0.62) * root.reveal
      visible: opacity > 0
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
      onWheel: function(wheel) { root.handleWheel(wheel) }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.setFilter("")
          else root.dismiss()
        } else if (event.key === Qt.Key_Down) {
          root.glideBy(root.rowHeight * 3)
        } else if (event.key === Qt.Key_Up) {
          root.glideBy(-root.rowHeight * 3)
        } else if (event.key === Qt.Key_PageDown) {
          root.glideBy(scroller.height * 0.9)
        } else if (event.key === Qt.Key_PageUp) {
          root.glideBy(-scroller.height * 0.9)
        } else if (event.key === Qt.Key_Home && !root.filterText) {
          root.glideTo(0)
        } else if (event.key === Qt.Key_End && !root.filterText) {
          root.glideTo(root.maxScroll)
        } else if (Util.editsFilter(event, root.filterText)) {
          root.setFilter(Util.editedFilter(event, root.filterText))
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) > 32 && event.text.charCodeAt(0) !== 127) {
          root.setFilter(root.filterText + event.text)
        } else if (event.key === Qt.Key_Space && root.filterText) {
          root.setFilter(root.filterText + " ")
        } else {
          return
        }
        event.accepted = true
      }
    }

    Item {
      id: content
      anchors.fill: parent
      visible: opacity > 0
      opacity: Math.max(0, Math.min(1, (root.reveal - 0.1) / 0.6))
      scale: 1.06 - 0.06 * root.reveal

      // Search, the same as the Launchpad's (Omarchy menu header style).
      Item {
        id: search
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(panel.height * 0.06)
        width: Math.min(420, panel.width * 0.4)
        height: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: root.filterText || "tmux · Search…"
          color: Color.menu.text
          opacity: root.filterText ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideRight
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.spacing.hairline
          color: root.fgA(0.2)
        }
      }

      // Scroll viewport; root.scrollY moves the text (wheel / two fingers on
      // the background MouseArea, and ↑ ↓ PgUp PgDn Home End).
      Item {
        id: scroller
        anchors.top: search.bottom
        anchors.topMargin: 36
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true

      Item {
        width: scroller.width
        height: root.contentHeight
        y: -root.scrollY

      Row {
        id: columns
        readonly property int count: panel.width >= 1500 ? 3 : 2
        readonly property real colWidth: Math.min(620, (panel.width - 120 - (count - 1) * spacing) / count)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 56

        Repeater {
          model: root.columnsFor(root.shownSections, columns.count)

          delegate: Column {
            required property var modelData
            width: columns.colWidth
            spacing: 18

            Repeater {
              model: modelData

              delegate: Column {
                id: sectionBlock
                required property var modelData
                width: columns.colWidth

                Text {
                  text: sectionBlock.modelData.title
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: 13
                  font.bold: true
                  font.letterSpacing: 1
                  bottomPadding: 6
                }
                Rectangle {
                  width: parent.width
                  height: Style.spacing.hairline
                  color: root.fgA(0.15)
                }

                Repeater {
                  model: sectionBlock.modelData.rows

                  delegate: Item {
                    required property var modelData
                    width: columns.colWidth
                    height: Math.max(root.rowHeight, descText.implicitHeight + 6)

                    Text {
                      id: keysText
                      width: Math.round(columns.colWidth * 0.40)
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: modelData.keys
                      color: Color.menu.text
                      font.family: root.fontFamily
                      font.pixelSize: root.fontSize
                      font.bold: true
                      elide: Text.ElideRight
                    }
                    Text {
                      id: descText
                      anchors.left: keysText.right
                      anchors.leftMargin: 12
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: modelData.desc
                      color: Color.menu.text
                      opacity: 0.75
                      font.family: root.fontFamily
                      font.pixelSize: root.fontSize
                      wrapMode: Text.WordWrap
                    }
                  }
                }
              }
            }
          }
        }
      }

      }
      }

      Text {
        anchors.centerIn: parent
        visible: root.shownSections.length === 0 && root.sections.length > 0
        textFormat: Text.PlainText
        text: "Nothing matches “" + root.filterText + "”"
        color: Color.menu.text
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: 18
      }
    }
  }
}

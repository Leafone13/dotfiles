import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons

// Mac-style Launchpad: the blurred wallpaper fades in over the windows, and a
// grid zooms in. Four sections swipe like pages: DevPods (~/.local/bin/pod; a
// devpod tile opens its actions), Remote Control (the AnyDesk list of
// ~/.local/bin/hotel, SUPER+SHIFT+A), Work (pinned apps) and Apps (all apps). Remote Control and Apps each have type-to-search. Summon with `omarchy-shell shell toggle logos.launchpad`, or live
// from the Hyprland 4-finger pinch (input.lua writes progress to gestureFile).
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  // Selection inside the current section's list.
  property int selectedIndex: 0
  property var apps: []
  // Sections: 0 DevPods, 1 Remote Control, 2 Work, 3 Apps. `section` is the one being
  // shown or headed to; the last one is remembered across opens (sectionFile).
  readonly property var sectionNames: ["DevPods", "Remote Control", "Work", "Apps"]
  readonly property int podsSection: 0
  readonly property int remoteSection: 1
  readonly property int workSection: 2
  readonly property int appsSection: 3
  property int section: 0
  property int lastSection: 0
  property var hotels: []
  property var work: []
  readonly property var workIds: ["slack", "WhatsApp", "Outlook", "chromium", "obsidian"]
  property var resetItem: ({ kind: "reset", name: "Reset AnyDesk", icon: "", mono: "↻" })
  readonly property string hotelScript: Quickshell.env("HOME") + "/.local/bin/hotel"
  // DevPods: `pod list` rows; openPod is the devpod whose actions are shown (null: the list).
  readonly property string podScript: Quickshell.env("HOME") + "/.local/bin/pod"
  property var pods: []
  property var openPod: null
  // Vertical scroll of the Apps grid in px (it does not fit on one screen).
  property real appsScroll: 0
  // Desktop ids Omarchy's own launcher hides (launcher.hides + NoDisplay/OnlyShowIn scan).
  property var configuredHidden: ({})
  property var scannedHidden: ({})
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

  // 0 = hidden, 1 = fully shown. Everything visual is driven from this.
  // While a pinch is live it tracks the fingers 1:1, otherwise finishAnim runs.
  property real reveal: 0
  property bool live: false
  readonly property bool shown: root.opened || root.live || root.reveal > 0.001
  // One cursor for keys and mouse, like Omarchy's menus: arrows move it, the
  // pointer moving over a tile takes it. Hidden until either is used.
  property bool cursorActive: false
  // The pointer put the cursor there, so leaving the tile hides it again.
  property bool cursorByMouse: false
  property string blurredWallpaper: ""

  // Finish like GNOME's swipeTracker: ease-out cubic leaves at 3x its average
  // speed, so duration = 3 * distance / velocity makes it start exactly at the
  // release velocity, with no stall and no overshoot. Clamped to 100-400 ms.
  NumberAnimation {
    id: finishAnim
    target: root
    property: "reveal"
    easing.type: Easing.OutCubic
    onFinished: if (!root.shown && root.bgHold <= 0) { blurJob.running = true; root.releaseCapture() }
  }

  function animateTo(target, velocity, baseDuration) {
    finishAnim.stop()
    var distance = Math.abs(target - root.reveal)
    var duration = baseDuration || 300
    if (velocity !== undefined) {
      // Speed toward the target; moving away (or barely moving) gets a floor.
      var toward = (target > root.reveal ? 1 : -1) * velocity
      if (toward < 0.002) toward = 0.002
      duration = Math.max(100, Math.min(400, 3 * distance / toward))
    }
    if (distance < 0.001) {
      root.reveal = target
      // No animation means no onFinished, so release the capture here.
      if (!root.shown && root.bgHold <= 0) root.releaseCapture()
      return
    }
    finishAnim.from = root.reveal
    finishAnim.to = target
    finishAnim.duration = duration
    finishAnim.start()
  }

  // Launch handoff: the grid leaves at once, but the blurred background holds
  // until Hyprland reports the app's window (or a focus/workspace change), at
  // least 140 ms and at most 600 ms after the click, then fades with the
  // window's own popin, so the app comes out of the blur instead of the old
  // desktop flashing in between. bgHold only draws; it never takes input.
  property real bgHold: 0
  property bool holding: false
  property bool releaseRequested: false
  property real launchAt: 0
  property string activeBefore: ""
  property string lastActive: ""

  NumberAnimation {
    id: bgHoldFade
    target: root
    property: "bgHold"
    to: 0
    duration: 200
    easing.type: Easing.InOutQuad
    onFinished: if (!root.shown) { blurJob.running = true; root.releaseCapture() }
  }
  Timer { id: holdFloor; interval: 140; onTriggered: root.tryReleaseHold() }
  Timer { id: holdCap; interval: 600; onTriggered: { root.releaseRequested = true; root.tryReleaseHold() } }

  function startHold() {
    bgHoldFade.stop()
    root.bgHold = 1
    root.holding = true
    root.releaseRequested = false
    root.launchAt = Date.now()
    root.activeBefore = root.lastActive
    holdFloor.restart()
    holdCap.restart()
  }
  function tryReleaseHold() {
    if (!root.holding || !root.releaseRequested || Date.now() - root.launchAt < 140) return
    root.holding = false
    holdCap.stop()
    bgHoldFade.start()
  }
  function cancelHold() {
    root.holding = false
    holdFloor.stop()
    holdCap.stop()
    bgHoldFade.stop()
    root.bgHold = 0
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      var data = String(event && event.data !== undefined ? event.data : "")
      if (name === "activewindowv2") {
        var addr = data.trim()
        // Focus falling back to the window that was active before is not the app.
        if (root.holding && addr && addr !== root.activeBefore) { root.releaseRequested = true; root.tryReleaseHold() }
        if (addr) root.lastActive = addr
      } else if (root.holding && (name === "openwindow" || name === "workspacev2")) {
        root.releaseRequested = true
        root.tryReleaseHold()
      }
    }
  }

  // Blur ramp: at the start of a pinch the desktop is captured once (our layer
  // has drawn nothing yet) and blurred progressively, so the windows soften
  // instead of showing sharp under a translucent smear; the pre-blurred
  // wallpaper takes over once the capture is fully blurred. Closing never
  // unblurs the old frame, it fades out.
  property bool capRequested: false
  property bool capClosing: false
  property real capFade: 0
  NumberAnimation { id: capFadeIn; target: root; property: "capFade"; from: 0; to: 1; duration: 90 }

  function beginCapture() {
    capFadeIn.stop()
    root.capFade = 0
    root.capClosing = false
    root.capRequested = true
    // Reset first so a frame from the previous gesture can never flash.
    capture.captureSource = null
    capture.captureSource = panel.screen
    capture.captureFrame()
  }
  function releaseCapture() {
    root.capRequested = false
    capFadeIn.stop()
    root.capFade = 0
    capture.captureSource = null
  }
  // Blur amount of the captured desktop: eases in, full by p = 0.4.
  function capBlur(p) {
    if (root.capClosing) return 1
    var t = Math.max(0, Math.min(1, p / 0.4))
    return 1 - (1 - t) * (1 - t)
  }
  // Wallpaper: late when the blurred capture covers the start, earlier when
  // there is no capture; blended by capFade so a late frame does not jump.
  function wallpaperOpacity(p) {
    var withCap = root.smoothstep(0.35, 0.85, p)
    var without = root.smoothstep(0.2, 0.7, p)
    return root.capFade * withCap + (1 - root.capFade) * without
  }

  function smoothstep(a, b, x) {
    var t = Math.max(0, Math.min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
  }

  // Paging. pageOffset is the scroll position in pages (0 = first page) and
  // drives the ListView directly; the ListView itself takes no input.
  // Two-finger touchpad swipes move it 1:1, held to the neighbouring pages by
  // soft walls; release hands the visible motion to a critically damped
  // spring. The mouse wheel and keys flip a whole page.
  property real pageOffset: 0
  // Logical px of page travel per angleDelta unit (Hyprland scroll_factor 0.4).
  readonly property real swipeGain: 0.28
  property real dragRaw: 0
  property int dragStartPage: 0
  // "" = axis not locked yet, "x" = paging, "y" = vertical flip, "done",
  // "released" = settling early before ScrollEnd, "end" = gesture over.
  property string dragAxis: ""
  property real dragVertical: 0
  property real dragHorizontal: 0
  property real dragAxisAccum: 0
  property var dragSamples: []
  property real lastMotion: 0
  readonly property int shownPage: Math.max(0, Math.min(root.pageCount - 1, Math.round(root.pageOffset)))

  // Critically damped spring, x(t) = T + (x0 + (v0 + w*x0) t) e^(-w t), one
  // write per frame. QML's SpringAnimation cannot take an initial velocity.
  FrameAnimation {
    id: spring
    property real target: 0
    property real x0: 0
    property real v0: 0
    property real t: 0
    readonly property real omega: 34
    onTriggered: {
      t += frameTime
      var e = Math.exp(-omega * t)
      var x = (x0 + (v0 + omega * x0) * t) * e
      var v = (v0 - omega * (v0 + omega * x0) * t) * e
      if (Math.abs(x) < 0.0005 && Math.abs(v) < 0.01) { root.pageOffset = target; stop(); return }
      root.pageOffset = target + x
    }
  }

  // v0 in pages per second (signed), the visible speed at hand-over.
  function springTo(target, v0) {
    spring.stop()
    var x0 = root.pageOffset - target
    var v = v0 || 0
    // Toward the target, cap the speed so the landing overshoots at most ~2%
    // (a strict no-overshoot cap brakes short flicks).
    var cap = 1.3 * spring.omega * Math.abs(x0)
    var toward = -Math.sign(x0)
    if (x0 !== 0 && v * toward > cap) v = toward * cap
    spring.target = target
    spring.x0 = x0
    spring.v0 = v
    spring.t = 0
    if (Math.abs(x0) < 0.0005 && Math.abs(v) < 0.01) { root.pageOffset = target; return }
    spring.start()
  }

  // Soft walls only at the first and last section: past them the overflow
  // goes through an iOS rubber band (c = 0.55, d = 0.25 page). Between
  // sections a long swipe runs freely, so one gesture can cross two.
  readonly property real rubberK: 0.55 / 0.25
  function rubberB(x) { return (1 - 1 / (x * root.rubberK + 1)) * 0.25 }
  function rubberInv(y) { return (1 / (1 - Math.min(0.999, y / 0.25)) - 1) / root.rubberK }
  function rubberSlope(x) { return 1 / ((x * root.rubberK + 1) * (x * root.rubberK + 1)) }
  function dragLo() { return 0 }
  function dragHi() { return root.pageCount - 1 }
  function softClamp(x) {
    var lo = root.dragLo(), hi = root.dragHi()
    if (x < lo) return lo - root.rubberB(lo - x)
    if (x > hi) return hi + root.rubberB(x - hi)
    return x
  }
  // How fast the visible page moves per unit of finger travel at raw x.
  function softSlope(x) {
    var lo = root.dragLo(), hi = root.dragHi()
    if (x < lo) return root.rubberSlope(lo - x)
    if (x > hi) return root.rubberSlope(x - hi)
    return 1
  }
  // Inverse of softClamp: the raw position that shows offset y.
  function unclamp(y) {
    var lo = root.dragLo(), hi = root.dragHi()
    if (y < lo) return lo - root.rubberInv(lo - y)
    if (y > hi) return hi + root.rubberInv(y - hi)
    return y
  }

  onPageOffsetChanged: pages.contentX = pages.originX + root.pageOffset * pages.width

  function setPage(page, velocity, animate) {
    var p = Math.max(0, Math.min(root.pageCount - 1, page))
    pages.currentIndex = p
    if (p !== root.section) {
      root.section = p
      root.selectedIndex = 0
      root.openPod = null
      // Each section's search starts empty.
      if (root.filterText) { root.filterText = ""; root.appsScroll = 0; root.rebuild() }
    }
    if (p !== root.lastSection) {
      root.lastSection = p
      sectionFile.setText(p + "\n")
    }
    if (animate === false) {
      spring.stop()
      root.pageOffset = p
      // An unchanged pageOffset sends no change signal; place the view anyway.
      pages.contentX = pages.originX + p * pages.width
    }
    else root.springTo(p, velocity || 0)
  }

  // Least-squares slope of raw position over time (pages/ms) for samples
  // newer than `windowMs` before `at`.
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

  // Release velocities (pages/ms), both taken at the last motion:
  // commit = the strongest 3-sample fit in the last 80 ms, so the slowdown
  // just before lift-off cannot cancel a flick; launch = a 50 ms fit without
  // a final lift-off event that is much slower than the one before it.
  function commitVelocity() {
    var s = root.dragSamples, best = 0
    for (var i = 2; i < s.length; i++) {
      if (root.lastMotion - s[i].t > 80) continue
      var v = root.fitSlope(s.slice(i - 2, i + 1), s[i].t, 1000)
      if (Math.abs(v) > Math.abs(best)) best = v
    }
    return best
  }
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
      // Mouse wheel: scrolls the Apps grid (a row per notch); elsewhere, or
      // sideways, one section per notch-group.
      var horizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)
      if (!horizontal && root.section === root.appsSection && root.appsMaxScroll > 0) {
        root.scrollApps(-wheel.angleDelta.y / 120 * root.cellH)
        return
      }
      var d = horizontal ? wheel.angleDelta.x : wheel.angleDelta.y
      bg.wheelAccum += d
      if (bg.wheelAccum <= -240) { root.goToPage(pages.currentIndex + 1); bg.wheelAccum = 0 }
      else if (bg.wheelAccum >= 240) { root.goToPage(pages.currentIndex - 1); bg.wheelAccum = 0 }
      return
    }
    var now = Date.now()
    // Hyprland sends ScrollEnd twice. The second one must not start a new
    // gesture: that stopped the settle and snapped back to the nearest page,
    // which cancelled fast flicks (they are released before mid-page).
    if (wheel.phase === Qt.ScrollEnd && root.dragAxis === "end") return
    if (wheel.phase === Qt.ScrollBegin || root.dragAxis === "end") {
      spring.stop()
      root.dragAxis = ""
      root.dragAxisAccum = 0
      root.dragHorizontal = 0
      root.dragVertical = 0
      root.dragRaw = root.pageOffset
      // Count from the page we are already heading to (setPage keeps it in
      // currentIndex), so quick successive flicks chain instead of hitting
      // the soft wall around the page just left.
      root.dragStartPage = pages.currentIndex
      root.dragSamples = [{ t: now, x: root.dragRaw }]
      root.lastMotion = now
      if (wheel.phase === Qt.ScrollBegin) return
    }
    if (wheel.phase === Qt.ScrollEnd) {
      // An early release already started the settle; keep it running.
      if (root.dragAxis !== "released") root.endSwipe()
      root.dragAxis = "end"
      return
    }

    var dx = wheel.angleDelta.x, dy = wheel.angleDelta.y
    if (root.dragAxis === "released") {
      // The fingers were still on the pad: take the page back where it is.
      spring.stop()
      root.dragAxis = "x"
      root.dragRaw = root.unclamp(root.pageOffset)
      root.dragSamples = [{ t: now - 1, x: root.dragRaw }]
    }
    if (root.dragAxis === "") {
      // Lock the axis after ~40 units of travel; vertical only when clearly so.
      root.dragAxisAccum += Math.abs(dx) + Math.abs(dy)
      root.dragVertical += dy
      root.dragHorizontal += dx
      root.dragRaw -= dx * root.swipeGain / Math.max(1, pages.width)
      if (root.dragAxisAccum < 40) return
      // Vertical only means something on Apps (it scrolls); elsewhere any
      // swipe pages, so a diagonal one is not swallowed.
      root.dragAxis = root.dragStartPage === root.appsSection && Math.abs(root.dragVertical) > 1.5 * Math.abs(root.dragHorizontal) ? "y" : "x"
      if (root.dragAxis === "y") {
        root.dragRaw = root.pageOffset
        // The travel spent locking the axis still scrolls.
        dy = root.dragVertical
      } else dy = 0
      dx = 0
    }
    if (root.dragAxis === "y") {
      // Vertical two-finger scroll moves the Apps grid 1:1 (natural, like the
      // pages); Remote Control and Work fit on one screen, so it does nothing there.
      if (root.dragStartPage === root.appsSection) root.scrollApps(-dy * root.swipeGain)
      return
    }
    if (root.dragAxis !== "x") return
    // Natural scrolling: fingers left (negative) pull the next page in.
    root.dragRaw -= dx * root.swipeGain / Math.max(1, pages.width)
    root.pageOffset = root.softClamp(root.dragRaw)
    if (dx !== 0) root.lastMotion = now
    var samples = root.dragSamples.concat([{ t: now, x: root.dragRaw }])
    while (samples.length > 3 && now - samples[0].t > 150) samples.shift()
    root.dragSamples = samples
  }

  function endSwipe() {
    if (root.dragAxis === "x") {
      // Fingers resting for 150+ ms before lift-off mean no flick.
      var commitV = Date.now() - root.lastMotion > 150 ? 0 : root.commitVelocity()
      // Hand over the visible speed: near a wall the page barely moves.
      var launchV = root.launchVelocity() * root.softSlope(root.dragRaw)
      // A deliberate flick (>= 0.8 pages/s) goes one section in its
      // direction, or two once the page is already 1.5+ sections along
      // (measured: neighbour flicks release at 0.3-0.7, cross-two drags at
      // 1.1-3.7 raw); otherwise land on the nearest section.
      var target
      if (Math.abs(commitV * 1000) >= 0.8) {
        var dir = Math.sign(commitV)
        var along = (root.pageOffset - root.dragStartPage) * dir
        if (along > 0) target = root.dragStartPage + dir * (along >= 1.5 ? 2 : 1)
        // Dragged out, then flicked back: the next section that way.
        else target = dir > 0 ? Math.floor(root.pageOffset) + 1 : Math.ceil(root.pageOffset) - 1
      } else {
        target = Math.round(root.pageOffset)
      }
      target = Math.max(0, Math.min(root.pageCount - 1, target))
      root.setPage(target, launchV * 1000)
    } else if (root.dragAxis === "") {
      root.setPage(Math.round(root.pageOffset))
    }
  }


  // ScrollEnd often arrives 30-110 ms after the fingers lift, while
  // the page stands still. A full frame without motion right after a fast
  // segment counts as the lift and starts the settle now.
  FrameAnimation {
    running: root.dragAxis === "x"
    onTriggered: {
      if (Date.now() - root.lastMotion < 17) return
      if (Math.abs(root.commitVelocity() * 1000) < 1.5) return
      root.endSwipe()
      root.dragAxis = "released"
    }
  }

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

  // Theme: chrome follows the Omarchy theme (colours, corner radius, font);
  // motion, blur and the grid stay Mac. Light vs dark is decided by luminance.
  readonly property color textColor: Color.menu.text
  readonly property color themeBg: Color.background
  readonly property color themeFg: Color.foreground
  readonly property bool lightTheme: root.luma(Color.background) > root.luma(Color.foreground)
  readonly property int radius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  // Icon style: "duotone" (gradient-mapped to the theme, default) or "brand"
  // (vendor colours). Persisted in iconStyleFile; Ctrl+T inside the Launchpad toggles it.
  property string iconStyle: "duotone"
  readonly property bool duotone: root.iconStyle === "duotone"

  function luma(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  function fgA(a) { return Qt.rgba(root.themeFg.r, root.themeFg.g, root.themeFg.b, a) }
  function bgA(a) { return Qt.rgba(root.themeBg.r, root.themeBg.g, root.themeBg.b, a) }

  function toggleIconStyle() {
    root.iconStyle = root.duotone ? "brand" : "duotone"
    iconStyleFile.setText(root.iconStyle + "\n")
  }

  // Grid geometry, sized from the screen like macOS (7 x 5 on a laptop).
  readonly property int columns: Math.max(4, Math.min(8, Math.floor(panel.width / 190)))
  readonly property int rows: Math.max(3, Math.min(6, Math.floor((panel.height - 220) / 170)))
  readonly property int pageCount: 4
  readonly property int iconSize: Math.round(Math.min(96, Math.max(56, panel.height / 12)))
  readonly property real cellW: pages.width / root.columns
  readonly property real cellH: Math.min(pages.height / root.rows, root.iconSize + 70)
  readonly property real appsContentH: Math.ceil(root.apps.length / root.columns) * root.cellH
  readonly property real appsMaxScroll: Math.max(0, root.appsContentH - pages.height)
  // 1 on the Apps section, fading out over the swipe to Work.
  readonly property real appsVis: Math.max(0, Math.min(1, 1 - Math.abs(root.pageOffset - root.appsSection)))
  // The search field: on Remote Control and Apps, gone on Work.
  readonly property real searchVis: Math.max(root.appsVis, Math.max(0, Math.min(1, 1 - Math.abs(root.pageOffset - root.remoteSection))))
  // The open devpod's name in the search field's place, fading with the swipe.
  readonly property real podTitleVis: root.openPod ? Math.max(0, Math.min(1, 1 - Math.abs(root.pageOffset - root.podsSection))) : 0
  function hasSearch(i) { return i === root.remoteSection || i === root.appsSection }

  function sectionItems(i) {
    if (i === root.podsSection) return root.openPod ? root.podActions(root.openPod) : root.pods
    if (i === root.remoteSection) return root.filterHotels([root.resetItem].concat(root.hotels), i === root.section ? root.filterText : "")
    if (i === root.workSection) return root.work
    return root.apps
  }

  // `pod list`: name, label, context, state. The tile shows the label's
  // initials (a "(...)" part left out) and the state under them.
  function parsePods(text) {
    var out = []
    var lines = String(text || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var cols = lines[i].split("\t")
      var name = (cols[0] || "").trim()
      if (!name) continue
      var label = (cols[1] || name).trim()
      var state = (cols[3] || "").trim()
      var mono = label.replace(/\s*\(.*\)\s*/g, " ").trim().split(/[\s-]+/).map(function(w) { return w.charAt(0).toUpperCase() }).join("").slice(0, 3)
      out.push({ kind: "pod", pod: name, name: label, icon: "", mono: mono, state: state,
                 role: state === "Running" ? "running" : state === "NotFound" ? "not created" : "stopped" })
    }
    root.pods = out
    if (root.openPod) {
      var again = out.filter(function(x) { return x.pod === root.openPod.pod })
      root.openPod = again.length ? again[0] : null
    }
  }

  // Enter starts the devpod first when it is not running; Turn off only when it is.
  function podActions(pod) {
    var running = pod.state === "Running"
    var out = [{ kind: "podAction", action: "enter", pod: pod.pod, name: running ? "Enter" : "Start & enter", icon: "", mono: "\u25B6" }]
    out.push({ kind: "podAction", action: "recreate", pod: pod.pod, name: "Recreate", icon: "", mono: "\u21BB" })
    if (running) out.push({ kind: "podAction", action: "stop", pod: pod.pod, name: "Turn off", icon: "", mono: "\u23FB" })
    out.push({ kind: "podBack", name: "Back", icon: "", mono: "\u2039" })
    return out
  }

  function openPodActions(pod) {
    root.openPod = pod
    root.selectedIndex = 0
  }
  readonly property var currentItems: root.sectionItems(root.section)

  function scrollApps(delta) {
    root.appsScroll = Math.max(0, Math.min(root.appsMaxScroll, root.appsScroll + delta))
  }
  // Scroll the Apps grid so the selected row is in view.
  function revealSelection() {
    if (root.section !== root.appsSection) return
    var top = Math.floor(root.selectedIndex / root.columns) * root.cellH
    if (top < root.appsScroll) root.appsScroll = top
    else if (top + root.cellH > root.appsScroll + pages.height) root.scrollApps(top + root.cellH - pages.height - root.appsScroll)
  }

  // Tile code and short label per hotels.tsv alias stem, from launchpad.tsv
  // next to it (kept out of this file, which is in the public dotfiles).
  // Unknown aliases fall back to the stem and the description.
  property var hotelCodes: ({})
  property var hotelNames: ({})
  property string hotelsText: ""

  function parseHotelMeta(text) {
    var codes = ({}), names = ({})
    var lines = String(text || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].trim() || lines[i].trim().charAt(0) === "#") continue
      var cols = lines[i].split("\t")
      var stem = (cols[0] || "").trim()
      if (!stem) continue
      if (cols[1] && cols[1].trim() !== "-") codes[stem] = cols[1].trim()
      if (cols[2] && cols[2].trim()) names[stem] = cols[2].trim()
    }
    root.hotelCodes = codes
    root.hotelNames = names
    root.parseHotels(root.hotelsText)
  }

  // hotels.tsv: alias, ID, description, ... (tab-separated, "#" comments).
  // File order is kept (cctv is last on purpose). The tile shows the hotel
  // code, the label the description without its "(host)" part.
  // Name matches first (prefix before substring), then alias/description.
  function filterHotels(items, text) {
    var q = String(text || "").trim().toLowerCase()
    if (!q) return items
    var scored = []
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      var lname = it.name.toLowerCase()
      var extra = ((it.alias || "") + " " + (it.desc || "")).toLowerCase()
      var score = lname.indexOf(q) === 0 ? 3 : lname.indexOf(q) !== -1 ? 2 : extra.indexOf(q) !== -1 ? 1 : 0
      if (score) scored.push({ item: it, score: score, order: i })
    }
    scored.sort(function(a, b) { return (b.score - a.score) || (a.order - b.order) })
    return scored.map(function(x) { return x.item })
  }

  function parseHotels(text) {
    var out = []
    var lines = String(text || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (!line.trim() || line.trim().charAt(0) === "#") continue
      var cols = line.split("\t")
      var alias = (cols[0] || "").trim()
      if (!alias) continue
      var desc = (cols[2] || alias).trim()
      var stem = alias.split("-")[0]
      var label = root.hotelNames[stem] || desc.replace(/\s*\(.*\)\s*$/, "").split(",")[0].trim() || alias
      var code = root.hotelCodes[stem] || stem.toUpperCase()
      var role = /-(client|server)$/.test(alias) ? alias.split("-").pop() : ""
      out.push({ kind: "hotel", alias: alias, name: label, desc: desc + " " + code, icon: "", mono: code.split("-").pop(), role: role })
    }
    root.hotels = out
  }

  function pluginId() {
    return (root.manifest && root.manifest.id) || "logos.launchpad"
  }

  function prepare() {
    root.filterText = ""
    root.openPod = null
    podList.running = true
    root.cursorActive = false
    root.appsScroll = 0
    root.rebuild()
    root.setPage(root.lastSection, undefined, false)
    root.selectedIndex = 0
  }

  function open(payloadJson, velocity) {
    root.cancelHold()
    if (!root.opened && !root.live && root.reveal < 0.001) root.beginCapture()
    root.capClosing = false
    if (!root.opened && !root.live) root.prepare()
    root.live = false
    root.opened = true
    root.animateTo(1, velocity)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close(velocity) {
    root.capClosing = true
    root.live = false
    root.opened = false
    root.animateTo(0, velocity)
  }

  // Gesture protocol, one line: "live <0..1>" while fingers move,
  // "end <1|0> <progress per ms>" to commit open / cancel or close.
  function handleGesture(line) {
    var parts = String(line || "").trim().split(/\s+/)
    if (parts[0] === "begin") { if (!root.opened && root.reveal < 0.001) root.beginCapture(); return }
    // The gesture ended without ever going live (a spread, or a pinch too small).
    if (parts[0] === "cancel") {
      if (root.live) root.close(0)
      else if (!root.shown && root.bgHold <= 0) root.releaseCapture()
      return
    }
    if (parts.length < 2) return
    var value = Math.max(0, Math.min(1, parseFloat(parts[1]) || 0))
    if (parts[0] === "live") {
      if (root.holding || root.bgHold > 0) root.cancelHold()
      if (!root.live && !root.opened) root.prepare()
      if (!root.live) {
        // A spread from open lifts the blur like fog; a pinch from closed
        // blurs a fresh capture (if "begin" was missed, capture now).
        root.capClosing = root.opened
        if (!root.opened && !root.capRequested) root.beginCapture()
      }
      finishAnim.stop()
      root.live = true
      root.reveal = value
    } else if (parts[0] === "end") {
      var velocity = parts.length > 2 ? (parseFloat(parts[2]) || 0) : undefined
      if (value >= 1) root.open("{}", velocity)
      else root.close(velocity)
    }
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId())
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Apps come straight from Quickshell's DesktopEntries (the same source the
  // shell's AppLibrary uses); the scoped plugin API does not hand menus to
  // third-party plugins reliably, so the plugin does not depend on it.
  function iconFor(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    var themed = Quickshell.iconPath(value, true)
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  function idSet(rawText) {
    var out = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = lines[i].trim()
      if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
      if (id) out[id] = true
    }
    return out
  }

  function rebuild() {
    var values = DesktopEntries.applications.values || []
    var q = root.filterText.trim().toLowerCase()
    var out = []
    var byId = ({})
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry) continue
      var id = String(entry.id || "")
      var name = String(entry.name || "")
      if (!id || !name) continue
      byId[id] = entry
      if (entry.noDisplay) continue
      if (root.configuredHidden[id] || root.scannedHidden[id]) continue
      var score = 0
      if (q) {
        var lname = name.toLowerCase()
        var extra = (String(entry.genericName || "") + " " + String(entry.comment || "") + " " + id).toLowerCase()
        try { if (entry.keywords && entry.keywords.join) extra += " " + entry.keywords.join(" ").toLowerCase() } catch (e) { }
        if (lname.indexOf(q) === 0) score = 3
        else if (lname.indexOf(q) !== -1) score = 2
        else if (extra.indexOf(q) !== -1) score = 1
        else continue
      }
      out.push({ kind: "app", id: id, name: name, icon: root.iconFor(entry.icon), score: score })
    }
    out.sort(function(a, b) { return (b.score - a.score) || a.name.localeCompare(b.name) })
    root.apps = out
    // Work: fixed order, never filtered by search or the hidden lists.
    var work = []
    for (var w = 0; w < root.workIds.length; w++) {
      var e = byId[root.workIds[w]]
      if (e) work.push({ kind: "app", id: String(e.id), name: String(e.name), icon: root.iconFor(e.icon) })
    }
    root.work = work
    var anydesk = byId["anydesk"]
    root.resetItem = { kind: "reset", name: "Reset AnyDesk", alias: "reset", desc: "anydesk new id", icon: anydesk ? root.iconFor(anydesk.icon) : "", mono: "↻" }
    if (root.selectedIndex >= root.currentItems.length) root.selectedIndex = Math.max(0, root.currentItems.length - 1)
  }

  // Remote Control and Apps search their own list; typing on Work switches
  // to Apps, so pinch, type, Enter works there too.
  function setFilter(text) {
    if (!root.hasSearch(root.section)) root.setPage(root.appsSection)
    root.filterText = text
    root.selectedIndex = 0
    root.rebuild()
    root.appsScroll = 0
  }

  function launch(index) {
    var items = root.currentItems
    if (index < 0 || index >= items.length) return
    var app = items[index]
    // Inside DevPods a tile can open the actions or go back; the Launchpad stays.
    if (app.kind === "pod") { root.openPodActions(app); return }
    if (app.kind === "podBack") { root.openPod = null; root.selectedIndex = 0; return }
    root.startHold()
    root.capClosing = true
    // The grid leaves a little faster than a plain dismiss (Mac hint).
    root.live = false
    root.opened = false
    root.animateTo(0, undefined, 220)
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId())
    if (app.kind === "podAction") {
      // Enter and Recreate open a terminal; Turn off reports by notification.
      Quickshell.execDetached([root.podScript, app.action, app.pod])
    } else if (app.kind === "hotel" || app.kind === "reset") {
      // Menu mode: notifications, and the Windows password goes to the clipboard.
      Quickshell.execDetached([root.hotelScript, "--menu", app.kind === "reset" ? "reset" : app.alias])
    } else {
      // Same launch path as Omarchy's AppLibrary: a uwsm scope via gtk-launch.
      Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", app.id + ".desktop"])
    }
  }

  // Left/Right run on into the neighbouring section, like Mac pages.
  function moveSelection(delta) {
    var count = root.currentItems.length
    root.cursorByMouse = false
    if (!root.cursorActive) { root.cursorActive = true; return }
    var next = root.selectedIndex + delta
    if (next < 0 && delta === -1 && root.section > 0) {
      root.setPage(root.section - 1)
      root.selectedIndex = Math.max(0, root.currentItems.length - 1)
    } else if (next >= count && delta === 1 && root.section < root.pageCount - 1) {
      root.setPage(root.section + 1)
    } else {
      root.selectedIndex = Math.max(0, Math.min(count - 1, next))
    }
    root.revealSelection()
  }

  function goToPage(page) {
    var p = Math.max(0, Math.min(root.pageCount - 1, page))
    if (p === pages.currentIndex && Math.abs(root.pageOffset - p) < 0.001) return
    root.setPage(p)
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    onLoaded: root.configuredHidden = root.idSet(text())
    onFileChanged: reload()
  }

  Process {
    id: hiddenScan
    running: true
    command: ["bash", root.omarchyPath + "/shell/services/hidden-entries.sh",
      [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(function(v) { return String(v || "").length > 0 }).join(":")]
    stdout: StdioCollector { onStreamFinished: root.scannedHidden = root.idSet(this.text) }
  }

  // Live pinch progress from Hyprland (see ~/.config/hypr/input.lua).
  FileView {
    id: gestureFile
    path: root.runtimeDir + "/omarchy-launchpad-gesture"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.handleGesture(text())
  }

  FileView {
    id: iconStyleFile
    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy-launchpad/icon-style"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.iconStyle = text().trim() === "brand" ? "brand" : "duotone"
  }

  Process {
    id: podList
    command: [root.podScript, "list"]
    stdout: StdioCollector { onStreamFinished: root.parsePods(this.text) }
  }

  // Last shown section; read once, written by setPage.
  FileView {
    id: sectionFile
    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy-launchpad/section"
    printErrors: false
    onLoaded: {
      var s = parseInt(text().trim())
      if (s >= 0 && s < root.pageCount) root.lastSection = s
    }
  }

  // The same directory `hotel --menu` (SUPER+SHIFT+A) lists.
  FileView {
    path: Quickshell.env("HOME") + "/Work/Yaya/anydesk/hotels.tsv"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.hotelsText = text(); root.parseHotels(root.hotelsText) }
  }

  FileView {
    path: Quickshell.env("HOME") + "/Work/Yaya/anydesk/launchpad.tsv"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseHotelMeta(text())
  }

  // Tells the Hyprland side whether a pinch should open or close.
  FileView {
    id: stateFile
    path: root.runtimeDir + "/omarchy-launchpad-open"
    printErrors: false
  }
  onOpenedChanged: stateFile.setText(root.opened ? "1\n" : "0\n")
  Component.onCompleted: {
    stateFile.setText("0\n")
    gestureFile.setText("end 0\n")
    blurJob.running = true
  }

  // Pre-blurred wallpaper (regenerated only when the wallpaper changes).
  Process {
    id: blurJob
    command: ["bash", Qt.resolvedUrl("blur-wallpaper.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      onStreamFinished: {
        var path = this.text.trim()
        if (path) root.blurredWallpaper = "file://" + path + "?t=" + Date.now()
      }
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      hiddenScan.running = true
      if (root.opened) root.rebuild()
    }
  }

  // Kept mapped at all times so the first gesture frame does not wait for the
  // surface to appear; while hidden it draws nothing and takes no input.
  PanelWindow {
    id: panel
    visible: true
    mask: root.shown ? null : emptyMask
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-launchpad"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Region { id: emptyMask }

    // While open, ask Hyprland to suspend binds and gestures (the 3-finger
    // workspace swipe / overview) so a spread meant to close the Launchpad
    // cannot switch workspaces; the pinch gesture sets disable_inhibit.
    ShortcutInhibitor {
      window: panel
      enabled: root.opened
    }

    // Captured desktop, blurred at half resolution (cheaper, and matches the
    // pre-blurred wallpaper's strength once scaled back up).
    Item {
      id: capLayer
      width: Math.ceil(panel.width / 2)
      height: Math.ceil(panel.height / 2)
      transformOrigin: Item.TopLeft
      scale: 2
      // Only while the Launchpad is shown: a stray capture never covers the desktop.
      opacity: root.shown ? root.capFade * (root.capClosing ? root.smoothstep(0, 0.35, root.reveal) : 1) : 0
      visible: opacity > 0

      ScreencopyView {
        id: capture
        anchors.fill: parent
        live: false
        visible: false
        onHasContentChanged: if (hasContent && root.capRequested) capFadeIn.restart()
      }

      MultiEffect {
        anchors.fill: parent
        source: capture
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blurMultiplier: 0
        blur: root.capBlur(root.reveal)
        saturation: -0.25 * root.capBlur(root.reveal)
      }
    }

    // Background: the blurred wallpaper fades in over the windows (they are
    // gone once it is opaque), with a mild darkening on top.
    Image {
      anchors.fill: parent
      source: root.blurredWallpaper
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      smooth: true
      opacity: Math.max(root.wallpaperOpacity(root.reveal), root.bgHold)
      visible: opacity > 0
    }

    // Wash in the theme background: frosted dark glass on dark themes,
    // frosted paper on light ones.
    Rectangle {
      anchors.fill: parent
      color: root.themeBg
      opacity: (root.lightTheme ? 0.60 : 0.45) * Math.max(root.reveal, root.bgHold)
      visible: opacity > 0
    }

    // Click on empty space closes; wheel / two-finger swipe flips pages.
    MouseArea {
      id: bg
      anchors.fill: parent
      onClicked: root.dismiss()
      property real wheelAccum: 0
      onWheel: function(wheel) {
        root.handleWheel(wheel)
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_T && event.modifiers === Qt.ControlModifier) {
          root.toggleIconStyle()
        } else if (event.nativeScanCode === 49 && (event.modifiers & Qt.MetaModifier)) {
          // SUPER+` opens it (bindings.lua), but Hyprland binds are inhibited
          // while it is open, so the same keys close it here.
          root.dismiss()
        } else if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.setFilter("")
          else if (root.openPod && root.section === root.podsSection) { root.openPod = null; root.selectedIndex = 0 }
          else root.dismiss()
        } else if (Util.editsFilter(event, root.filterText)) {
          root.setFilter(Util.editedFilter(event, root.filterText))
        } else if (event.key === Qt.Key_Left) {
          root.moveSelection(-1)
        } else if (event.key === Qt.Key_Right) {
          root.moveSelection(1)
        } else if (event.key === Qt.Key_Up) {
          root.moveSelection(-root.columns)
        } else if (event.key === Qt.Key_Down) {
          root.moveSelection(root.columns)
        } else if (event.key === Qt.Key_PageUp) {
          root.goToPage(pages.currentIndex - 1)
        } else if (event.key === Qt.Key_PageDown) {
          root.goToPage(pages.currentIndex + 1)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.launch(root.selectedIndex)
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

    // Everything zooms in from slightly larger and fades in, like macOS.
    // The grid moves as one layer: it fades in early (so the midpoint is not a
    // muddy double transparency) and its scale follows the fingers linearly.
    Item {
      id: content
      anchors.fill: parent
      visible: opacity > 0
      opacity: root.smoothstep(0.1, 0.7, root.reveal)
      scale: 1.15 - 0.15 * root.reveal

      // Search, styled like the Omarchy menu header: plain prompt text at
      // heading size (dimmed until typed into) over a hairline divider.
      // It belongs to Apps and fades with the swipe away from it.
      Item {
        id: search
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(panel.height * 0.06)
        width: Math.min(360, panel.width * 0.4)
        height: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
        opacity: root.searchVis
        visible: opacity > 0

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: root.filterText || "Search…"
          color: root.textColor
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

      Text {
        anchors.centerIn: search
        opacity: root.podTitleVis
        visible: opacity > 0
        textFormat: Text.PlainText
        text: root.openPod ? root.openPod.name : ""
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      // DevPods with no devpod folders found.
      Text {
        anchors.centerIn: pages
        visible: root.section === root.podsSection && !root.openPod && root.pods.length === 0
        opacity: 0.7
        textFormat: Text.PlainText
        text: "No devpods in ~/Work/devpods"
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 18
      }

      ListView {
        id: pages
        anchors.top: search.bottom
        anchors.topMargin: 40
        anchors.bottom: dots.top
        anchors.bottomMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(panel.width - 80, root.columns * 190)
        orientation: ListView.Horizontal
        highlightFollowsCurrentItem: false
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        // Position comes from root.pageOffset; input is handled by bg.
        interactive: false
        // Keep the neighbouring pages built so the first drag frame does not hitch.
        cacheBuffer: Math.max(0, width)
        onWidthChanged: contentX = originX + root.pageOffset * width
        model: root.pageCount

        // One page per section. Apps scrolls vertically (appsScroll) when it
        // does not fit; the others are centred.
        delegate: Item {
          id: pageItem
          required property int index
          readonly property var items: root.sectionItems(index)
          width: pages.width
          height: pages.height
          clip: true

          Grid {
            id: grid
            anchors.horizontalCenter: parent.horizontalCenter
            y: height <= pageItem.height ? Math.round((pageItem.height - height) / 2) : -root.appsScroll
            columns: root.columns

            Repeater {
              model: pageItem.items

              delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool selected: root.cursorActive && pageItem.index === root.section && index === root.selectedIndex
                width: root.cellW
                height: root.cellH

                Rectangle {
                  anchors.centerIn: parent
                  width: root.iconSize + 36
                  height: parent.height - 6
                  radius: root.radius
                  color: cell.selected ? Color.menu.selectedBackground : "transparent"
                  border.width: 1
                  border.color: cell.selected ? Color.menu.selectedBorder : "transparent"
                  Behavior on color { ColorAnimation { duration: 60 } }
                }

                Column {
                  anchors.centerIn: parent
                  spacing: 8

                  Item {
                    width: root.iconSize
                    height: root.iconSize
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Drawn by one of the two effects below, never directly.
                    Image {
                      id: icon
                      anchors.fill: parent
                      source: cell.modelData.icon
                      sourceSize.width: root.iconSize * 2
                      sourceSize.height: root.iconSize * 2
                      fillMode: Image.PreserveAspectFit
                      smooth: true
                      mipmap: true
                      asynchronous: true
                      visible: false
                    }

                    // Brand colours with a subtle shadow so dark icons survive
                    // black themes and white ones light themes. Icons darken
                    // while pressed; no hover effect.
                    MultiEffect {
                      anchors.fill: icon
                      source: icon
                      visible: !root.duotone && icon.status === Image.Ready
                      brightness: hover.pressed ? -0.35 : 0
                      shadowEnabled: true
                      shadowBlur: 0.4
                      shadowOpacity: root.lightTheme ? 0.25 : 0.35
                      shadowColor: root.lightTheme ? root.themeFg : "black"
                      shadowVerticalOffset: 2
                      shadowHorizontalOffset: 0
                    }

                    // Duotone: icon luminance mapped from a background/accent
                    // blend to the text colour.
                    ShaderEffect {
                      anchors.fill: icon
                      visible: root.duotone && icon.status === Image.Ready
                      opacity: hover.pressed ? 0.65 : 1
                      property variant source: icon
                      property color low: Qt.tint(root.themeBg, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.55))
                      property color high: root.themeFg
                      fragmentShader: Qt.resolvedUrl("duotone.frag.qsb")
                    }

                    // Monogram tile: hotels (RIET, HEG) and apps that ship no
                    // usable icon (their first letter).
                    Rectangle {
                      anchors.fill: parent
                      visible: icon.status !== Image.Ready
                      radius: root.radius
                      color: root.fgA(hover.pressed ? 0.2 : 0.12)
                      readonly property string mono: cell.modelData.mono || (cell.modelData.name || "?").charAt(0).toUpperCase()
                      Column {
                        anchors.centerIn: parent
                        Text {
                          anchors.horizontalCenter: parent.horizontalCenter
                          text: parent.parent.mono
                          color: root.textColor
                          font.family: root.fontFamily
                          font.pixelSize: root.iconSize * (parent.parent.mono.length <= 1 ? 0.45 : parent.parent.mono.length <= 3 ? 0.32 : parent.parent.mono.length === 4 ? 0.26 : 0.21)
                          font.bold: true
                        }
                        // client / server for hotels with two PCs, running / stopped for devpods.
                        Text {
                          anchors.horizontalCenter: parent.horizontalCenter
                          visible: !!cell.modelData.role
                          text: cell.modelData.role || ""
                          color: root.textColor
                          opacity: 0.7
                          font.family: root.fontFamily
                          font.pixelSize: Math.round(root.iconSize * 0.15)
                        }
                      }
                    }
                  }

                  Text {
                    width: Math.max(root.iconSize + 40, root.cellW - 24)
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: cell.modelData.name
                    color: cell.selected ? Color.menu.selectedText : root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    // Halo in the theme background keeps labels readable over
                    // busy wallpapers on light and dark themes alike.
                    style: Text.Outline
                    styleColor: root.bgA(0.4)
                  }
                }

                MouseArea {
                  id: hover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  // Only real pointer motion: a tile that slides under a still
                  // pointer (opening, paging) does not take the cursor.
                  onPositionChanged: {
                    if (pageItem.index !== root.section) return
                    root.cursorActive = true
                    root.cursorByMouse = true
                    root.selectedIndex = cell.index
                  }
                  onExited: if (root.cursorByMouse && cell.selected) root.cursorActive = false
                  onClicked: {
                    if (pageItem.index !== root.section) return
                    root.launch(cell.index)
                  }
                }
              }
            }
          }
        }
      }

      // "No results" hint
      Text {
        anchors.centerIn: pages
        visible: root.hasSearch(root.section) && root.currentItems.length === 0 && root.searchVis > 0
        opacity: 0.7 * root.searchVis
        textFormat: Text.PlainText
        text: (root.section === root.remoteSection ? "No remote PCs" : "No apps") + (root.filterText ? " match “" + root.filterText + "”" : " found")
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 18
      }

      // Section labels, styled like the bar's workspaces: the current one
      // carries the focused-workspace glyph, the others are dimmed.
      Row {
        id: dots
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(panel.height * 0.06)
        spacing: Style.space(14)

        Repeater {
          model: root.sectionNames
          delegate: Item {
            id: dot
            required property int index
            required property string modelData
            readonly property bool current: index === root.shownPage
            width: pageLabel.implicitWidth + 16
            height: pageLabel.implicitHeight + 12

            Row {
              id: pageLabel
              anchors.centerIn: parent
              spacing: Style.space(6)
              opacity: dot.current ? 1 : 0.5

              Text {
                text: "\uDB85\uDCFB"
                color: root.textColor
                opacity: dot.current ? 1 : 0
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: dot.modelData
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.goToPage(dot.index)
            }
          }
        }
      }
    }
  }
}

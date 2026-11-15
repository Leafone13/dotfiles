import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// A wallpaper comes alive when ~/.local/share/elune-breath/<its file name>.mask.png exists (made by
// mask.sh, with .life.png for a creature, .petals.png for falling petals and .sway.png for a bough beside it). This layer then
// redraws the whole picture over the stock wallpaper, moving. No mask, no layer.
Item {
  id: root
  property var shell: null
  property real period: 6.5    // seconds per breath
  property real strength: 0.1  // peak opacity of the breath
  property real haloLag: 0.25  // the halo follows the lines this share of a breath later (1.6 s), 0 = all at once
  property real waveEvery: 4       // breaths between two lights climbing the tree
  property real waveStrength: 0.35
  property real rippleStrength: 0.15 // how much brighter the scene's own lights get as that light passes on to the moon
  property real mistStrength: 10   // mask pixels the sky travels in 45 s
  property real creatureRipple: 0.25 // the share of that the creature takes: in full the owl flares
  property real moteStrength: 0.3  // any strength at 0 switches that effect off
  property real owlPeriod: 4.5     // seconds per breath of the creature, if the wallpaper has one
  property real owlStrength: 0.006 // how far its body swells, as a share of its distance from its feet
  property real petalStrength: 0.45 // peak opacity of the falling petals, if the wallpaper has any
  property real swayStrength: 0.003 // radians the bough turns in a gust, if the wallpaper has one: 1 px at a twig's tip
  property real blinkEvery: 7      // seconds between chances to blink; it takes about half of them
  property int fps: 20
  // to see where each effect lives: echo "4 6" > ~/.local/state/logos-breath-demo makes everything
  // 4 times stronger and 6 times faster, at once; echo "1 1" goes back
  readonly property var demoWords: demoFile.text().trim().split(/\s+/)
  readonly property real demo: parseFloat(demoWords[0]) || 1
  readonly property real demoSpeed: parseFloat(demoWords[1]) || 1

  property real breathPhase: 0
  property real wave: 2
  property real t: 0
  property int ticks: 0
  property real owl: 0
  property real blink: 0
  property string wallpaper: ""
  readonly property string maskUrl: wallpaper ? "file://" + home + "/.local/share/elune-breath/" + wallpaper.split("/").pop() + ".mask.png" : ""
  // asked once here, not per screen: a screen that goes away must not stop the clock
  readonly property bool masked: probe.status === Image.Ready
  readonly property string home: Quickshell.env("HOME")
  readonly property bool fullscreen: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.hasFullscreen : false

  // for ~/.local/bin/breath-check, which tells a quiet wallpaper from a dead one
  ShellIpc {
    target: "logos.breath"
    function state(): string {
      var drawn = 0  // screens whose picture is loaded and on show
      for (var panel of screens.instances) if (panel.drawing) drawn += 1
      return JSON.stringify({ wallpaper: root.wallpaper, masked: root.masked, drawn: drawn, ticks: root.ticks,
                              paused: root.fullscreen ? "fullscreen" : root.unseen ? "unseen" : "" })
    }
  }

  Image { id: probe; source: root.maskUrl; visible: false }

  FileView {
    id: demoFile
    path: root.home + "/.local/state/logos-breath-demo"
    watchChanges: true; printErrors: false
    onFileChanged: reload()
  }

  // shortcut: the shell tells plugins nothing about a wallpaper change, so Omarchy's wallpaper daemon is
  // asked every second which picture is up and whether anyone can see it; replace when the shell does
  property bool unseen: false
  Process {
    id: status
    command: ["owe", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var now = ({})
        try { now = JSON.parse(text) } catch (e) {}
        root.wallpaper = now.source_path || ""
        root.unseen = !!(now.locked || now.monitors_off)
      }
    }
  }
  Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: status.running = true }

  // Hyprland's workspace list does not follow fullscreen on its own
  Connections {
    target: Hyprland
    function onRawEvent(event) { if (event && event.name === "fullscreen") Hyprland.refreshWorkspaces() }
  }

  Timer {
    interval: 1000 / root.fps; repeat: true
    running: root.masked && !root.fullscreen && !root.unseen
    // from the clock, so a late tick never shifts the rhythm
    onTriggered: {
      var now = Date.now() / 1000 * root.demoSpeed
      root.breathPhase = (now % root.period) / root.period
      // leaves the foot as an inhale begins and takes a breath and a half to reach the crown
      root.wave = (now % (root.period * root.waveEvery)) / (root.period * 1.5)
      root.t = now % 3600
      root.ticks += 1
      root.owl = 0.5 - 0.5 * Math.cos(2 * Math.PI * (now % root.owlPeriod) / root.owlPeriod)
      // a third of a second, in the slots a fixed scramble of the slot's number picks
      var slot = Date.now() / 1000 / root.blinkEvery, into = (slot % 1) * root.blinkEvery / 0.33
      var picked = Math.abs(Math.sin(Math.floor(slot) * 12.9898) * 43758.5453) % 1 > 0.5
      root.blink = picked && into < 1 ? Math.sin(Math.PI * into) : 0
    }
  }

  Variants {
    id: screens
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.masked
      readonly property bool drawing: visible && artImage.status === Image.Ready && light.status !== ShaderEffect.Error
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}   // clicks fall through to the desktop
      // redraws the picture above the stock wallpaper: two surfaces on the background layer have no fixed order
      WlrLayershell.namespace: "logos-breath"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Image {
        id: maskImage
        visible: false
        source: root.maskUrl
      }
      Image { id: lifeImage; visible: false; source: root.maskUrl.replace(".mask.png", ".life.png") }
      Image { id: petalImage; visible: false; source: root.maskUrl.replace(".mask.png", ".petals.png") }
      Image { id: swayImage; visible: false; source: root.maskUrl.replace(".mask.png", ".sway.png") }
      Image {
        id: artImage
        visible: false
        source: root.masked ? "file://" + root.wallpaper : ""
        // decoded at the size this screen shows, as the stock wallpaper is
        sourceSize: Qt.size(Math.ceil(parent.width * screen.devicePixelRatio), Math.ceil(parent.height * screen.devicePixelRatio))
      }
      ShaderEffect {
        id: light
        // covers the screen the way the wallpaper does (aspect crop, centred)
        readonly property real fit: Math.max(parent.width / Math.max(1, maskImage.implicitWidth), parent.height / Math.max(1, maskImage.implicitHeight))
        width: maskImage.implicitWidth * fit; height: maskImage.implicitHeight * fit
        anchors.centerIn: parent
        property var mask: maskImage
        property var art: artImage
        property var life: lifeImage
        readonly property bool alive: lifeImage.status === Image.Ready
        property real owl: alive ? root.owl * root.owlStrength * root.demo : 0
        property real blink: alive ? root.blink : 0
        property real creatureRipple: alive ? root.creatureRipple : 1
        property var petals: petalImage
        property var sway: swayImage
        property real swayStrength: swayImage.status === Image.Ready ? root.swayStrength * root.demo : 0
        property real petalStrength: petalImage.status === Image.Ready ? Math.min(1, root.petalStrength * root.demo) : 0
        visible: artImage.status === Image.Ready
        property real breathPhase: root.breathPhase
        property real haloLag: root.haloLag
        property real strength: root.strength * root.demo
        property real wave: root.wave
        property real waveStrength: root.waveStrength * root.demo
        property real rippleStrength: root.rippleStrength * root.demo
        property real t: root.t
        property real mistStrength: root.mistStrength * root.demo
        property real moteStrength: root.moteStrength * root.demo
        fragmentShader: Qt.resolvedUrl("light.frag.qsb")
      }
    }
  }
}

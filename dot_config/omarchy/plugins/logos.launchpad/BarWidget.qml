import QtQuick
import qs.Ui

// Bar button for the Launchpad, so a mouse alone can open it (the pinch needs
// the touchpad, SUPER+` the keyboard).
BarWidget {
  id: root
  moduleName: "logos.launchpad"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: "Launchpad"
    onPressed: function(button) {
      if (root.bar) root.bar.run("omarchy-shell shell toggle logos.launchpad")
    }
  }
}

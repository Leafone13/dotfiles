import QtQuick
import qs.Ui

// Click: clear -> frosted -> original for bar and windows together (cycle.sh).
BarWidget {
  id: root
  moduleName: "logos.glass"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰂵"
    tooltipText: "Clear / frosted / original"
    onPressed: function(button) {
      if (root.bar) root.bar.run("$HOME/.config/omarchy/plugins/logos.glass/cycle.sh")
    }
  }
}

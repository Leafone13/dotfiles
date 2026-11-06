import QtQuick
import qs.Ui

// The list lives in ~/.local/bin/keys, outside this public repo.
BarWidget {
  id: root
  moduleName: "logos.keys"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: "Keys"
    onPressed: function(button) {
      if (root.bar) root.bar.run("$HOME/.local/bin/keys")
    }
  }
}

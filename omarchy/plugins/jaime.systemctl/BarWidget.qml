import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "jaime.systemctl"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function launchUser() {
    if (root.bar)
      root.bar.run("omarchy-launch-or-focus-tui --app-id=org.omarchy.systemctl-tui systemctl-tui")
  }

  function launchSystem() {
    if (root.bar)
      root.bar.run("omarchy-launch-or-focus-tui --app-id=org.omarchy.systemctl-tui-sudo sudo systemctl-tui")
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰒓"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Left: user services | Right: system services (sudo)"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.launchSystem()
      else root.launchUser()
    }
  }
}

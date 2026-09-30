import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "lazymusic.player"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  property bool opened: false
  property bool popoutSwitchClosing: false

  function open() {
    var wasOpen = opened
    opened = true
    if (!wasOpen && service) service.refreshCurrentView(false)
  }
  onServiceChanged: if (opened && service) service.refreshCurrentView(false)
  function close() {
    opened = false
    if (service) service.cancelSetup()
  }
  function toggle() { if (opened) close(); else open() }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰎆"
    tooltipText: root.service && root.service.song && root.service.song.title
      ? root.service.song.title + (root.service.song.artist ? " · " + root.service.song.artist : "")
      : "Lazy Music"
    useActiveColor: false
    foreground: root.bar ? root.bar.barForeground : Color.foreground
    onPressed: function(b) {
      if (b === Qt.RightButton && root.service) root.service.togglePlayback()
      else if (b === Qt.MiddleButton && root.service) root.service.next()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: kpanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: kpanel.fittedContentWidth(Style.space(380))
    contentHeight: kpanel.fittedContentHeight(contentLoader.item ? contentLoader.item.implicitHeight : Style.space(300))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: contentLoader.item ? contentLoader.item.searchFocused : false
      onCloseRequested: root.close()

      Loader {
        id: contentLoader
        anchors.fill: parent
        source: "Panel.qml"
        onLoaded: {
          if (!item) return
          item.widget = root
          item.bar = root.bar
        }
      }
    }
  }

  IpcHandler {
    target: "lazymusic.player"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function setup(): void {
      if (root.service) root.service.beginSetup()
      root.open()
    }
  }
}

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

  MusicIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    musicService: root.service
    text: "󰎆"
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
    focusTarget: contentLoader.item ? contentLoader.item.keyboardFocusTarget : panelHost
    contentWidth: kpanel.fittedContentWidth(Style.space(380))
    contentHeight: kpanel.fittedContentHeight(contentLoader.item ? contentLoader.item.implicitHeight : Style.space(300))

    Item {
      id: panelHost
      anchors.fill: parent
      Keys.onEscapePressed: root.close()

      Loader {
        id: contentLoader
        anchors.fill: parent
        source: "Panel.qml"
        onLoaded: {
          if (!item) return
          item.widget = root
          item.bar = root.bar
          if (root.opened) Qt.callLater(item.focusKeyboard)
        }
      }
    }
  }

  IpcHandler {
    target: "lazymusic.player"
    function keyboardState(): string {
      var item = contentLoader.item
      return JSON.stringify({
        playbackKey: "Space",
        opened: root.opened,
        mapped: kpanel.backingWindowVisible,
        focused: kpanel.focusTarget ? kpanel.focusTarget.activeFocus : false,
        setup: item ? item.setupMode : false,
        loading: root.service ? root.service.loading : false,
        entries: item ? item.entries.length : 0
      })
    }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function previous(): void { if (root.service) root.service.previous() }
    function next(): void { if (root.service) root.service.next() }
    function playPause(): void {
      if (!root.service) return
      if (root.opened && contentLoader.item) contentLoader.item.playSelection()
      else root.service.togglePlayback()
    }
    function setup(): void {
      if (root.service) root.service.beginSetup()
      root.open()
    }
  }
}

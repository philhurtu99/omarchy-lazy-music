import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

Item {
  id: setup
  property var service: null
  property var widget: null
  property QtObject bar: null
  property string kind: service ? service.serverKind : "subsonic"
  property bool allowHttp: false
  property bool passwordVisible: false
  property bool confirmDisconnect: false
  property string localError: ""
  readonly property Item keyboardFocusTarget: serverField
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: Style.space(380)
  implicitHeight: form.implicitHeight

  Keys.onEscapePressed: if (setup.widget) setup.widget.close()

  onServiceChanged: {
    if (!service) return
    serverField.text = service.serverUrl || ""
    userField.text = service.username || ""
    allowHttp = serverField.text.startsWith("http://")
  }

  Connections {
    target: setup.service
    function onConfiguredChanged() {
      if (setup.service && !setup.service.configured) {
        serverField.text = ""
        userField.text = ""
        passwordField.text = ""
        setup.passwordVisible = false
        setup.confirmDisconnect = false
        setup.allowHttp = false
        setup.localError = ""
      }
    }
  }

  Connections {
    target: setup.widget
    function onOpenedChanged() {
      if (setup.widget && !setup.widget.opened) {
        passwordField.text = ""
        setup.passwordVisible = false
        setup.confirmDisconnect = false
      }
    }
  }

  Column {
    id: form
    width: parent.width
    spacing: Style.space(12)

    Row {
      spacing: Style.space(8)
      Text {
        textFormat: Text.PlainText
        text: setup.service && setup.service.configured ? "CHANGE SERVER" : "CONNECT SERVER"
        color: setup.fg
        font.family: setup.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
      Button {
        focusable: true
        visible: setup.service && setup.service.configured
        text: "CANCEL"
        foreground: setup.fg
        fontFamily: setup.fontFamily
        onClicked: if (setup.service) setup.service.cancelSetup()
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: setup.service && setup.service.configured
        ? "Enter the new server address and credentials. Your current connection stays active until the new login succeeds."
        : "Connect to your music library. Your password is used once to create a local session."
      color: setup.dim
      font.family: setup.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Style.space(6)
      Button {
        focusable: true
        text: "NAVIDROME / SUBSONIC"
        selected: setup.kind === "subsonic"
        foreground: setup.fg
        fontFamily: setup.fontFamily
        onClicked: setup.kind = "subsonic"
      }
      Button {
        focusable: true
        text: "JELLYFIN"
        selected: setup.kind === "jellyfin"
        foreground: setup.fg
        fontFamily: setup.fontFamily
        onClicked: setup.kind = "jellyfin"
      }
      Button {
        focusable: true
        text: "EMBY"
        selected: setup.kind === "emby"
        foreground: setup.fg
        fontFamily: setup.fontFamily
        onClicked: setup.kind = "emby"
      }
    }

    Text {
      textFormat: Text.PlainText
      text: "SERVER URL"
      color: setup.dim
      font.family: setup.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Controls.TextField {
      id: serverField
      width: parent.width
      height: Style.space(34)
      placeholderText: "https://music.example.com"
      color: setup.fg
      placeholderTextColor: setup.dim
      font.family: setup.fontFamily
      font.pixelSize: Style.font.bodySmall
      selectByMouse: true
      background: Rectangle {
        radius: Style.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: setup.dim
        opacity: 0.55
      }
      Keys.onEscapePressed: if (setup.widget) setup.widget.close()
    }

    Text {
      textFormat: Text.PlainText
      text: "USERNAME"
      color: setup.dim
      font.family: setup.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Controls.TextField {
      id: userField
      width: parent.width
      height: Style.space(34)
      color: setup.fg
      font.family: setup.fontFamily
      font.pixelSize: Style.font.bodySmall
      selectByMouse: true
      background: Rectangle {
        radius: Style.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: setup.dim
        opacity: 0.55
      }
      Keys.onEscapePressed: if (setup.widget) setup.widget.close()
    }

    Text {
      textFormat: Text.PlainText
      text: "PASSWORD"
      color: setup.dim
      font.family: setup.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Controls.TextField {
      id: passwordField
      width: parent.width
      height: Style.space(34)
      rightPadding: Style.space(40)
      echoMode: setup.passwordVisible ? TextInput.Normal : TextInput.Password
      color: setup.fg
      font.family: setup.fontFamily
      font.pixelSize: Style.font.bodySmall
      selectByMouse: true
      background: Rectangle {
        radius: Style.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: setup.dim
        opacity: 0.55
      }
      Keys.onEscapePressed: if (setup.widget) setup.widget.close()

      Button {
        id: passwordEye
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(34)
        height: parent.height
        iconText: setup.passwordVisible ? "󰈈" : "󰈉"
        tooltipText: setup.passwordVisible ? "Hide password" : "Show password"
        foreground: setup.fg
        fontFamily: setup.fontFamily
        horizontalPadding: 0
        verticalPadding: 0
        focusable: true
        onClicked: setup.passwordVisible = !setup.passwordVisible
        Keys.onEscapePressed: if (setup.widget) setup.widget.close()
      }
    }

    Button {
      focusable: true
      text: "Allow HTTP for a trusted local server"
      selected: setup.allowHttp
      foreground: setup.fg
      fontFamily: setup.fontFamily
      onClicked: setup.allowHttp = !setup.allowHttp
    }

    Button {
      focusable: true
      text: setup.service && setup.service.setupBusy ? "Connecting…"
        : setup.service && setup.service.configured ? "Switch server" : "Connect"
      foreground: setup.fg
      fontFamily: setup.fontFamily
      bordered: true
      enabled: setup.service && !setup.service.setupBusy && !setup.service.disconnectBusy
      onClicked: {
        setup.localError = ""
        if (!serverField.text.trim() || !userField.text.trim() || !passwordField.text) {
          setup.localError = "Enter a server URL, username and password"
          return
        }
        setup.service.configure({ kind: setup.kind, serverUrl: serverField.text.trim(),
                                  username: userField.text.trim(), password: passwordField.text,
                                  allowHttp: setup.allowHttp })
        passwordField.text = ""
        setup.passwordVisible = false
      }
    }

    Text {
      width: parent.width
      visible: setup.confirmDisconnect
      textFormat: Text.PlainText
      text: "Disconnect stops playback and removes the saved login from this computer."
      color: setup.dim
      font.family: setup.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Row {
      visible: setup.service && setup.service.configured
      spacing: Style.space(6)
      Button {
        focusable: true
        text: setup.service && setup.service.disconnectBusy ? "Disconnecting…"
          : setup.confirmDisconnect ? "Confirm disconnect" : "Disconnect"
        foreground: setup.fg
        fontFamily: setup.fontFamily
        enabled: setup.service && !setup.service.setupBusy && !setup.service.disconnectBusy
        onClicked: {
          setup.localError = ""
          if (!setup.confirmDisconnect) setup.confirmDisconnect = true
          else if (setup.service) setup.service.disconnect()
        }
      }
      Button {
        focusable: true
        visible: setup.confirmDisconnect
        text: "Keep connected"
        foreground: setup.fg
        fontFamily: setup.fontFamily
        onClicked: setup.confirmDisconnect = false
      }
    }

    Text {
      width: parent.width
      visible: !!setup.localError || (setup.service && !!setup.service.setupError)
      textFormat: Text.PlainText
      text: setup.localError || (setup.service ? setup.service.setupError : "")
      color: setup.dim
      font.family: setup.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
  }
}

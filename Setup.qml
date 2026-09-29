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
  property string localError: ""
  readonly property bool formFocused: serverField.activeFocus || userField.activeFocus || passwordField.activeFocus
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: Style.space(380)
  implicitHeight: form.implicitHeight

  Connections {
    target: setup.widget
    function onOpenedChanged() {
      if (setup.widget && !setup.widget.opened) passwordField.text = ""
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
        text: "CONNECT SERVER"
        color: setup.fg
        font.family: setup.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
      Button {
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
      text: "Connect to your music library. Your password is used once to create a local session."
      color: setup.dim
      font.family: setup.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Style.space(6)
      Button {
        text: "NAVIDROME / SUBSONIC"
        selected: setup.kind === "subsonic"
        foreground: setup.fg
        fontFamily: setup.fontFamily
        onClicked: setup.kind = "subsonic"
      }
      Button {
        text: "JELLYFIN"
        selected: setup.kind === "jellyfin"
        foreground: setup.fg
        fontFamily: setup.fontFamily
        onClicked: setup.kind = "jellyfin"
      }
      Button {
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
      echoMode: TextInput.Password
      color: setup.fg
      font.family: setup.fontFamily
      font.pixelSize: Style.font.bodySmall
      background: Rectangle {
        radius: Style.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: setup.dim
        opacity: 0.55
      }
      Keys.onEscapePressed: if (setup.widget) setup.widget.close()
    }

    Button {
      text: "Allow HTTP for a trusted local server"
      selected: setup.allowHttp
      foreground: setup.fg
      fontFamily: setup.fontFamily
      onClicked: setup.allowHttp = !setup.allowHttp
    }

    Button {
      text: setup.service && setup.service.setupBusy ? "Connecting…" : "Connect"
      foreground: setup.fg
      fontFamily: setup.fontFamily
      bordered: true
      enabled: setup.service && !setup.service.setupBusy
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

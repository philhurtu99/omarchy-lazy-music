import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

Item {
  id: panel
  property var widget: null
  property QtObject bar: null
  readonly property var service: widget ? widget.service : null
  readonly property bool setupMode: service && service.configChecked && (!service.configured || service.setupOpen)
  readonly property bool waitMode: !service || !service.configChecked
  readonly property bool searchFocused: searchField.activeFocus || (setupLoader.item && setupLoader.item.formFocused)
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var currentSong: service ? service.song : null
  readonly property bool hasSong: !!currentSong

  implicitWidth: Style.space(380)
  implicitHeight: setupMode ? (setupLoader.item ? setupLoader.item.implicitHeight : Style.space(300))
    : waitMode ? Style.space(100) : content.implicitHeight

  function timeText(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    return Math.floor(value / 60) + ":" + (value % 60 < 10 ? "0" : "") + (value % 60)
  }

  Timer {
    id: searchDelay
    interval: 350
    onTriggered: if (panel.service) panel.service.search(searchField.text)
  }

  Text {
    visible: panel.waitMode
    textFormat: Text.PlainText
    text: "Loading Lazy Music…"
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Loader {
    id: setupLoader
    width: parent.width
    active: panel.setupMode
    visible: panel.setupMode
    source: "Setup.qml"
    onLoaded: {
      if (!item) return
      item.service = panel.service
      item.bar = panel.bar
      item.widget = panel.widget
    }
  }

  Column {
    id: content
    width: parent.width
    visible: !panel.setupMode && !panel.waitMode
    spacing: Style.space(12)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: "LAZY MUSIC"
        color: panel.fg
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }

      Button {
        text: "SERVER"
        tooltipText: "Change server address or disconnect"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: {
          searchDelay.stop()
          if (panel.service) panel.service.beginSetup()
        }
      }

      Text {
        textFormat: Text.PlainText
        text: panel.service && panel.service.playing ? "●" : "○"
        color: panel.service && panel.service.playing ? Color.accent : panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(3)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: panel.hasSong ? (panel.currentSong.title || "Untitled track") : "Nothing playing"
        color: panel.fg
        font.family: panel.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: panel.hasSong ? [panel.currentSong.artist, panel.currentSong.album].filter(Boolean).join(" · ") : "Music library"
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: panel.hasSong && panel.service && panel.service.duration > 0

      Rectangle {
        id: progressTrack
        width: parent.width
        height: Style.space(3)
        radius: height / 2
        color: panel.dim

        Rectangle {
          width: parent.width * Math.max(0, Math.min(1, panel.service ? panel.service.position / Math.max(1, panel.service.duration) : 0))
          height: parent.height
          radius: parent.radius
          color: Color.accent
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (panel.service && panel.service.duration > 0)
              panel.service.seek(mouse.x / width * panel.service.duration)
          }
        }
      }

      Row {
        width: parent.width
        Text {
          textFormat: Text.PlainText
          text: panel.service ? panel.timeText(panel.service.position) : "0:00"
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Item { width: parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth; height: 1 }
        Text {
          textFormat: Text.PlainText
          text: panel.service ? panel.timeText(panel.service.duration) : "0:00"
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Row {
      spacing: Style.space(6)
      Button {
        iconText: "󰒮"
        tooltipText: "Previous"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: if (panel.service) panel.service.previous()
      }
      Button {
        iconText: panel.service && panel.service.playing ? "󰏤" : "󰐊"
        tooltipText: panel.service && panel.service.playing ? "Pause" : "Play"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        bordered: true
        onClicked: if (panel.service) panel.service.togglePlayback()
      }
      Button {
        iconText: "󰒭"
        tooltipText: "Next"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: if (panel.service) panel.service.next()
      }
      Button {
        iconText: "󰓛"
        tooltipText: "Stop"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: if (panel.service) panel.service.stop()
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: panel.dim
      opacity: 0.35
    }

    Row {
      spacing: Style.space(5)
      Button {
        text: "ALBUMS"
        selected: panel.service && (panel.service.view === "home" || panel.service.view === "album")
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: {
          searchDelay.stop()
          searchField.text = ""
          if (panel.service) panel.service.home()
        }
      }
      Button {
        text: "ARTISTS"
        selected: panel.service && (panel.service.view === "artists" || panel.service.view === "artist")
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: {
          searchDelay.stop()
          searchField.text = ""
          if (panel.service) panel.service.showArtists()
        }
      }
      Button {
        text: "PLAYLISTS"
        selected: panel.service && (panel.service.view === "playlists" || panel.service.view === "playlist")
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: {
          searchDelay.stop()
          searchField.text = ""
          if (panel.service) panel.service.showPlaylists()
        }
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Button {
        visible: panel.service && (panel.service.view === "album" || panel.service.view === "artist" || panel.service.view === "playlist")
        iconText: "󰁍"
        tooltipText: "Back"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: {
          if (!panel.service) return
          searchDelay.stop()
          panel.service.back(searchField.text)
        }
      }

      Controls.TextField {
        id: searchField
        width: parent.width - (panel.service && (panel.service.view === "album" || panel.service.view === "artist" || panel.service.view === "playlist") ? parent.children[0].implicitWidth + parent.spacing : 0)
        height: Style.space(34)
        placeholderText: "Search artists, albums, songs…"
        color: panel.fg
        placeholderTextColor: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        selectByMouse: true
        background: Rectangle {
          radius: Style.cornerRadius
          color: "transparent"
          border.width: 1
          border.color: panel.dim
          opacity: 0.55
        }
        onTextEdited: searchDelay.restart()
        Keys.onEscapePressed: if (panel.widget) panel.widget.close()
        Keys.onReturnPressed: {
          searchDelay.stop()
          if (panel.service) panel.service.search(text)
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: panel.service && panel.service.view === "album"
        ? panel.service.albumName + (panel.service.albumArtist ? " · " + panel.service.albumArtist : "")
        : panel.service && panel.service.view === "artist" ? panel.service.artistName
        : panel.service && panel.service.view === "artists" ? "ARTISTS"
        : panel.service && panel.service.view === "playlist" ? panel.service.playlistName
        : panel.service && panel.service.view === "playlists" ? "PLAYLISTS"
        : panel.service && panel.service.view === "search" ? "SEARCH RESULTS" : "RECENT ALBUMS"
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
    }

    Button {
      visible: panel.service && (panel.service.view === "home" || panel.service.view === "artists" || panel.service.view === "playlists")
      text: panel.service && panel.service.shuffleBusy ? "Preparing shuffle…" : "Shuffle library"
      iconText: "󰒝"
      selected: panel.service && panel.service.radioMode
      foreground: panel.fg
      fontFamily: panel.fontFamily
      bordered: true
      enabled: panel.service && !panel.service.shuffleBusy
      onClicked: if (panel.service) panel.service.shuffleLibrary()
    }

    Row {
      visible: panel.service && panel.service.view === "artists"
      width: parent.width
      spacing: Style.space(6)

      Button {
        text: "‹"
        tooltipText: "Previous page"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        opacity: panel.service && panel.service.artistOffset > 0 ? 1 : 0.4
        onClicked: if (panel.service && panel.service.artistOffset > 0)
          panel.service.artistsPage(Math.max(0, panel.service.artistOffset - 100))
      }

      Text {
        textFormat: Text.PlainText
        text: panel.service && panel.service.artistTotal > 0
          ? String(panel.service.artistOffset + 1) + "–" +
            String(Math.min(panel.service.artistOffset + panel.service.artists.length, panel.service.artistTotal)) +
            " of " + String(panel.service.artistTotal)
          : "0 artists"
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      Button {
        text: "›"
        tooltipText: "Next page"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        opacity: panel.service && panel.service.artistOffset + panel.service.artists.length < panel.service.artistTotal ? 1 : 0.4
        onClicked: if (panel.service && panel.service.artistOffset + panel.service.artists.length < panel.service.artistTotal)
          panel.service.artistsPage(panel.service.artistOffset + 100)
      }

      Button {
        text: "Refresh artists"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: if (panel.service) panel.service.refreshArtists()
      }
    }

    Button {
      visible: panel.service && ((panel.service.view === "album" && panel.service.songs.length > 0) ||
        (panel.service.view === "artist" && panel.service.albums.length > 0))
      text: panel.service && panel.service.shuffleBusy ? "Preparing shuffle…" : "Shuffle play"
      iconText: "󰒝"
      foreground: panel.fg
      fontFamily: panel.fontFamily
      bordered: true
      enabled: panel.service && !panel.service.shuffleBusy
      onClicked: {
        if (!panel.service) return
        if (panel.service.view === "artist") panel.service.playArtistShuffled()
        else panel.service.playAlbumShuffled()
      }
    }

    Text {
      width: parent.width
      visible: panel.service && (!!panel.service.error || !!panel.service.playbackError)
      textFormat: Text.PlainText
      text: panel.service ? (panel.service.error || panel.service.playbackError) : ""
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Button {
      visible: panel.service && panel.service.view === "playlist" && panel.service.songs.length > 0
      text: panel.service && panel.service.shuffleBusy ? "Preparing shuffle…" : "Shuffle play"
      iconText: "󰒝"
      selected: panel.service && panel.service.shuffled
      foreground: panel.fg
      fontFamily: panel.fontFamily
      bordered: true
      enabled: panel.service && !panel.service.shuffleBusy
      onClicked: if (panel.service) panel.service.playPlaylistShuffled()
    }

    Row {
      visible: panel.service && panel.service.view === "playlist"
      spacing: Style.space(6)
      Button {
        text: "Refresh playlist"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: if (panel.service) panel.service.refreshPlaylist()
      }
      Text {
        visible: panel.service && panel.service.loading
        textFormat: Text.PlainText
        text: "Loading playlist…"
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Row {
      visible: panel.service && panel.service.view === "playlist" && panel.service.playlistTotal > 0
      width: parent.width
      spacing: Style.space(6)

      Button {
        text: "‹"
        tooltipText: "Previous page"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        opacity: panel.service && panel.service.playlistOffset > 0 ? 1 : 0.4
        onClicked: if (panel.service && panel.service.playlistOffset > 0)
          panel.service.playlistPage(Math.max(0, panel.service.playlistOffset - 100))
      }

      Text {
        textFormat: Text.PlainText
        text: panel.service
          ? String(panel.service.playlistOffset + 1) + "–" +
            String(Math.min(panel.service.playlistOffset + panel.service.songs.length, panel.service.playlistTotal)) +
            " of " + String(panel.service.playlistTotal)
          : ""
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      Button {
        text: "›"
        tooltipText: "Next page"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        opacity: panel.service && panel.service.playlistOffset + panel.service.songs.length < panel.service.playlistTotal ? 1 : 0.4
        onClicked: if (panel.service && panel.service.playlistOffset + panel.service.songs.length < panel.service.playlistTotal)
          panel.service.playlistPage(panel.service.playlistOffset + 100)
      }
    }

    Flickable {
      width: parent.width
      height: Style.space(270)
      contentWidth: width
      contentHeight: listing.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: listing
        width: parent.width
        spacing: Style.space(3)

        Repeater {
          model: panel.service && (panel.service.view === "search" || panel.service.view === "artists") ? panel.service.artists : []
          delegate: Item {
            required property var modelData
            width: listing.width
            height: Style.space(43)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: artistMouse.containsMouse ? Color.accent : "transparent"
              opacity: artistMouse.containsMouse ? 0.13 : 0
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.name || "Artist"
                color: panel.fg
                font.family: panel.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.albumCount === null || modelData.albumCount === undefined
                  ? "Artist" : String(modelData.albumCount) + " albums"
                color: panel.dim
                font.family: panel.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            MouseArea {
              id: artistMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                searchDelay.stop()
                if (panel.service) panel.service.openArtist(modelData.id)
              }
            }
          }
        }

        Repeater {
          model: panel.service && (panel.service.view === "home" || panel.service.view === "search" || panel.service.view === "artist") ? panel.service.albums : []
          delegate: Item {
            required property var modelData
            width: listing.width
            height: Style.space(43)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: albumMouse.containsMouse ? Color.accent : "transparent"
              opacity: albumMouse.containsMouse ? 0.13 : 0
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.name || "Album"
                color: panel.fg
                font.family: panel.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.artist || ""
                color: panel.dim
                font.family: panel.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
            MouseArea {
              id: albumMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                searchDelay.stop()
                if (panel.service) panel.service.openAlbum(modelData.id)
              }
            }
          }
        }

        Repeater {
          model: panel.service && panel.service.view === "playlists" ? panel.service.playlists : []
          delegate: Item {
            required property var modelData
            width: listing.width
            height: Style.space(43)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: playlistMouse.containsMouse ? Color.accent : "transparent"
              opacity: playlistMouse.containsMouse ? 0.13 : 0
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.name || "Playlist"
                color: panel.fg
                font.family: panel.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: String(modelData.songCount || 0) + " tracks"
                color: panel.dim
                font.family: panel.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            MouseArea {
              id: playlistMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                searchDelay.stop()
                if (panel.service) panel.service.openPlaylist(modelData.id)
              }
            }
          }
        }

        Repeater {
          model: panel.service && (panel.service.view === "album" || panel.service.view === "playlist" || panel.service.view === "search") ? panel.service.songs : []
          delegate: Item {
            required property var modelData
            required property int index
            width: listing.width
            height: Style.space(43)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: songMouse.containsMouse ? Color.accent : "transparent"
              opacity: songMouse.containsMouse ? 0.13 : 0
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.title || "Untitled track"
                color: panel.fg
                font.family: panel.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.artist || modelData.album || ""
                color: panel.dim
                font.family: panel.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
            MouseArea {
              id: songMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                searchDelay.stop()
                if (panel.service) panel.service.playAt(index)
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: panel.service && !panel.service.error && !panel.service.playbackError && (panel.service.loading ||
            ((panel.service.view === "playlists" ? panel.service.playlists.length === 0 :
              panel.service.view === "home" ? panel.service.albums.length === 0 :
              panel.service.view === "artists" ? panel.service.artists.length === 0 :
              panel.service.view === "search" ? panel.service.artists.length === 0 && panel.service.albums.length === 0 && panel.service.songs.length === 0 :
              panel.service.view === "artist" ? panel.service.albums.length === 0 :
              panel.service.songs.length === 0)))
          textFormat: Text.PlainText
          text: panel.service && panel.service.loading ? "Loading…" : "No results"
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}

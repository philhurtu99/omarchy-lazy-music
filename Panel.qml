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
  readonly property Item keyboardFocusTarget: setupMode && setupLoader.item
    ? setupLoader.item.keyboardFocusTarget : waitMode ? panel : catalog
  readonly property var entries: catalogEntries()
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var currentSong: service ? service.song : null
  readonly property bool hasSong: !!currentSong
  readonly property var selectedEntry: catalog.currentIndex >= 0 && catalog.currentIndex < entries.length
    ? entries[catalog.currentIndex] : null
  readonly property bool newSongSelected: selectedEntry && selectedEntry.kind === "song"
    && (!currentSong || String(selectedEntry.data.id) !== String(currentSong.id))

  implicitWidth: Style.space(380)
  implicitHeight: setupMode ? (setupLoader.item ? setupLoader.item.implicitHeight : Style.space(300))
    : waitMode ? Style.space(100) : content.implicitHeight

  function catalogEntries() {
    if (!service) return []
    var rows = []
    function append(kind, items) {
      for (var i = 0; i < items.length; ++i)
        rows.push({ kind: kind, data: items[i], songIndex: i })
    }
    if (service.view === "search" || service.view === "artists") append("artist", service.artists)
    if (service.view === "home" || service.view === "search" || service.view === "artist") append("album", service.albums)
    if (service.view === "playlists") append("playlist", service.playlists)
    if (service.view === "album" || service.view === "playlist" || service.view === "search") append("song", service.songs)
    return rows
  }

  function focusKeyboard() {
    if (widget && widget.opened && keyboardFocusTarget) keyboardFocusTarget.forceActiveFocus()
  }

  function focusResults() {
    if (searchDelay.running) {
      searchDelay.stop()
      if (service) service.search(searchField.text)
    }
    catalog.forceActiveFocus()
  }

  function moveSelection(delta) {
    if (!entries.length || !service || service.loading) return
    catalog.currentIndex = Math.max(0, Math.min(entries.length - 1, catalog.currentIndex + delta))
    catalog.positionViewAtIndex(catalog.currentIndex, ListView.Contain)
  }

  function activateEntry(index, playSong) {
    if (!service || service.loading || index < 0 || index >= entries.length) return
    searchDelay.stop()
    var entry = entries[index]
    if (entry.kind === "artist") service.openArtist(entry.data.id)
    else if (entry.kind === "album") service.openAlbum(entry.data.id)
    else if (entry.kind === "playlist") service.openPlaylist(entry.data.id)
    else if (playSong) service.playAt(entry.songIndex)
    // Keyboard activation only selects songs; Space or Play starts them.
  }

  function playSelection() {
    if (!service) return
    if (selectedEntry && selectedEntry.kind === "song") {
      if (service.loading) return
      if (newSongSelected) service.playAt(selectedEntry.songIndex)
      else service.togglePlayback()
    } else {
      service.togglePlayback()
    }
  }

  function goBack() {
    if (!service || (service.view !== "album" && service.view !== "artist" && service.view !== "playlist")) return
    searchDelay.stop()
    service.back(searchField.text)
    catalog.forceActiveFocus()
  }

  onSetupModeChanged: Qt.callLater(focusKeyboard)
  onWaitModeChanged: Qt.callLater(focusKeyboard)

  // Unhandled keys bubble here from buttons and the list. Text fields keep
  // their editing keys, and buttons handle their own Enter/Space activation.
  Keys.onPressed: function(event) {
    var mediaModifiers = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier)
    if (!mediaModifiers && (event.key === Qt.Key_F5 || event.key === Qt.Key_MediaPrevious)) {
      if (!event.isAutoRepeat && panel.service) panel.service.previous()
    } else if (!mediaModifiers && (event.key === Qt.Key_F6 || event.key === Qt.Key_MediaPlay
      || event.key === Qt.Key_MediaPause || event.key === Qt.Key_MediaTogglePlayPause)) {
      if (!event.isAutoRepeat) panel.playSelection()
    } else if (!mediaModifiers && (event.key === Qt.Key_F7 || event.key === Qt.Key_MediaNext)) {
      if (!event.isAutoRepeat && panel.service) panel.service.next()
    } else if (event.key === Qt.Key_Escape) {
      if (panel.widget) panel.widget.close()
    } else if (panel.setupMode || panel.waitMode) {
      return
    } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
      searchField.forceActiveFocus()
      searchField.selectAll()
    } else if (searchField.activeFocus) {
      return
    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
      panel.focusResults()
      panel.moveSelection(event.key === Qt.Key_Down ? 1 : -1)
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backspace) {
      panel.goBack()
    } else if (event.key === Qt.Key_Space) {
      panel.playSelection()
    } else {
      return
    }
    event.accepted = true
  }

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
      Qt.callLater(panel.focusKeyboard)
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
        focusable: true
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
        focusable: true
        iconText: "󰒮"
        tooltipText: "Previous"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: if (panel.service) panel.service.previous()
      }
      Button {
        focusable: true
        iconText: !panel.newSongSelected && panel.service && panel.service.playing ? "󰏤" : "󰐊"
        tooltipText: panel.newSongSelected ? "Play selected track"
          : panel.service && panel.service.playing ? "Pause" : "Play"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        bordered: true
        onClicked: panel.playSelection()
      }
      Button {
        focusable: true
        iconText: "󰒭"
        tooltipText: "Next"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: if (panel.service) panel.service.next()
      }
      Button {
        focusable: true
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
        focusable: true
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
        focusable: true
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
        focusable: true
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
        focusable: true
        visible: panel.service && (panel.service.view === "album" || panel.service.view === "artist" || panel.service.view === "playlist")
        iconText: "󰁍"
        tooltipText: "Back"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: {
          panel.goBack()
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
        function submitSearch() {
          searchDelay.stop()
          if (panel.service) panel.service.search(text)
          panel.focusResults()
        }
        Keys.onReturnPressed: submitSearch()
        Keys.onEnterPressed: submitSearch()
        Keys.onDownPressed: panel.focusResults()
        Keys.onUpPressed: panel.focusResults()
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
      focusable: true
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
        focusable: true
        text: "‹"
        tooltipText: "Previous page"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        opacity: panel.service && panel.service.artistOffset > 0 ? 1 : 0.4
        enabled: panel.service && !panel.service.loading && panel.service.artistOffset > 0
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
        focusable: true
        text: "›"
        tooltipText: "Next page"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        opacity: panel.service && panel.service.artistOffset + panel.service.artists.length < panel.service.artistTotal ? 1 : 0.4
        enabled: panel.service && !panel.service.loading && panel.service.artistOffset + panel.service.artists.length < panel.service.artistTotal
        onClicked: if (panel.service && panel.service.artistOffset + panel.service.artists.length < panel.service.artistTotal)
          panel.service.artistsPage(panel.service.artistOffset + 100)
      }

      Button {
        focusable: true
        text: "Refresh artists"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        onClicked: if (panel.service) panel.service.refreshArtists()
      }
    }

    Button {
      focusable: true
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
      focusable: true
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
        focusable: true
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
        focusable: true
        text: "‹"
        tooltipText: "Previous page"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        opacity: panel.service && panel.service.playlistOffset > 0 ? 1 : 0.4
        enabled: panel.service && !panel.service.loading && panel.service.playlistOffset > 0
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
        focusable: true
        text: "›"
        tooltipText: "Next page"
        foreground: panel.fg
        fontFamily: panel.fontFamily
        opacity: panel.service && panel.service.playlistOffset + panel.service.songs.length < panel.service.playlistTotal ? 1 : 0.4
        enabled: panel.service && !panel.service.loading && panel.service.playlistOffset + panel.service.songs.length < panel.service.playlistTotal
        onClicked: if (panel.service && panel.service.playlistOffset + panel.service.songs.length < panel.service.playlistTotal)
          panel.service.playlistPage(panel.service.playlistOffset + 100)
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "↑↓ Select · Enter Open · Space Play/pause · Esc Close"
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    ListView {
      id: catalog
      width: parent.width
      height: Style.space(270)
      clip: true
      spacing: Style.space(3)
      boundsBehavior: Flickable.StopAtBounds
      activeFocusOnTab: true
      keyNavigationEnabled: false
      model: panel.entries
      onModelChanged: {
        currentIndex = panel.entries.length ? 0 : -1
        Qt.callLater(function() {
          if (catalog.currentIndex >= 0) catalog.positionViewAtIndex(catalog.currentIndex, ListView.Beginning)
          else catalog.contentY = 0
        })
      }
      onActiveFocusChanged: {
        if (activeFocus && currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
          panel.moveSelection(event.key === Qt.Key_Down ? 1 : -1)
        } else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
          panel.moveSelection(event.key === Qt.Key_Home ? -panel.entries.length : panel.entries.length)
        } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
          var pageSize = Math.max(1, Math.floor(height / (Style.space(43) + spacing)))
          panel.moveSelection(event.key === Qt.Key_PageDown ? pageSize : -pageSize)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
          panel.activateEntry(currentIndex)
        } else {
          return
        }
        event.accepted = true
      }

      delegate: Item {
        id: entryRow
        required property var modelData
        required property int index
        readonly property var record: modelData.data
        readonly property string kind: modelData.kind
        readonly property bool selected: catalog.activeFocus && catalog.currentIndex === index
        width: catalog.width
        height: Style.space(43)

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Color.accent
          opacity: entryRow.selected ? 0.22 : entryMouse.containsMouse ? 0.13 : 0
          border.width: entryRow.selected ? 1 : 0
          border.color: Color.accent
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: entryRow.kind === "song" ? (entryRow.record.title || "Untitled track")
              : entryRow.record.name || (entryRow.kind === "artist" ? "Artist" : entryRow.kind === "album" ? "Album" : "Playlist")
            color: panel.fg
            font.family: panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: entryRow.kind === "artist"
              ? (entryRow.record.albumCount === null || entryRow.record.albumCount === undefined
                ? "Artist" : String(entryRow.record.albumCount) + " albums")
              : entryRow.kind === "playlist" ? String(entryRow.record.songCount || 0) + " tracks"
              : entryRow.kind === "song" ? (entryRow.record.artist || entryRow.record.album || "")
              : entryRow.record.artist || ""
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
        MouseArea {
          id: entryMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            catalog.currentIndex = entryRow.index
            catalog.forceActiveFocus()
            panel.activateEntry(entryRow.index, true)
          }
        }
      }

      footer: Item {
        width: catalog.width
        implicitHeight: catalogStatus.visible ? catalogStatus.implicitHeight : 0
        Text {
          id: catalogStatus
          width: parent.width
          visible: panel.service && !panel.service.error && !panel.service.playbackError
            && (panel.service.loading || panel.entries.length === 0)
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

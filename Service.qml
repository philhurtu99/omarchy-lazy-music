import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string helper: Qt.resolvedUrl("backend.py").toString().replace(/^file:\/\//, "")
  property var albums: []
  property var artists: []
  property var playlists: []
  property var songs: []
  property string view: "home"
  property string albumName: ""
  property string artistName: ""
  property string albumArtist: ""
  property string playlistName: ""
  property string playlistId: ""
  property int playlistTotal: 0
  property int playlistOffset: 0
  property int artistTotal: 0
  property int artistOffset: 0
  property string currentArtistId: ""
  property string currentAlbumId: ""
  property string albumReturnView: "home"
  property bool shuffleBusy: false
  property bool loading: false
  property string error: ""
  property var song: null
  property bool playing: false
  property bool paused: false
  property real position: 0
  property real duration: 0
  property int queueLength: 0
  property bool shuffled: false
  property bool radioMode: false
  property string playbackError: ""
  property bool configured: false
  property bool configChecked: false
  property bool setupOpen: false
  property bool setupBusy: false
  property string setupError: ""
  property string serverKind: "subsonic"
  property var pendingCatalog: null
  property var activeCatalog: null

  function request(kind, argument) {
    if (!configured) return
    pendingCatalog = { kind: kind, argument: String(argument || "") }
    loading = true
    error = ""
    runCatalog()
  }

  function runCatalog() {
    if (catalogProcess.running || !pendingCatalog) return
    activeCatalog = pendingCatalog
    pendingCatalog = null
    catalogProcess.command = ["python3", helper, activeCatalog.kind, activeCatalog.argument]
    catalogProcess.running = true
  }

  function home() {
    view = "home"
    albumName = ""
    songs = []
    request("albums", "")
  }

  function showPlaylists() {
    view = "playlists"
    songs = []
    request("playlists", "")
  }

  function showArtists(offset) {
    view = "artists"
    albums = []
    songs = []
    var start = Math.max(0, Number(offset || 0))
    request(start ? "artistsPage" : "artists", String(start))
  }

  function artistsPage(offset) {
    if (view !== "artists") return
    request("artistsPage", String(offset))
  }

  function refreshArtists() {
    if (view !== "artists") return
    request("artistsRefresh", "")
  }

  function search(query) {
    var value = String(query || "").trim()
    if (value === "") { home(); return }
    view = "search"
    albums = []
    artists = []
    songs = []
    request("search", value)
  }

  function openAlbum(id) {
    if (!id) return
    albumReturnView = view
    currentAlbumId = id
    view = "album"
    songs = []
    request("album", id)
  }

  function openArtist(id) {
    if (!id) return
    currentArtistId = id
    view = "artist"
    albums = []
    songs = []
    request("artist", id)
  }

  function back(query) {
    var value = String(query || "").trim()
    if (view === "playlist") showPlaylists()
    else if (view === "album" && albumReturnView === "artist" && currentArtistId) openArtist(currentArtistId)
    else if (value) search(value)
    else if (view === "artist" || (view === "album" && albumReturnView === "artists")) showArtists(artistOffset)
    else home()
  }

  function openPlaylist(id) {
    if (!id) return
    view = "playlist"
    playlistId = id
    songs = []
    request("playlist", id)
  }

  function playlistPage(offset) {
    if (view !== "playlist" || !playlistId) return
    request("playlistPage", JSON.stringify({ id: playlistId, offset: offset }))
  }

  function refreshPlaylist() {
    if (view !== "playlist" || !playlistId) return
    request("playlistRefresh", playlistId)
  }

  function playPlaylistShuffled() {
    if (view !== "playlist" || songs.length === 0 || shuffleProcess.running) return
    shuffleBusy = true
    error = ""
    shuffleProcess.command = ["python3", helper, "playPlaylist", JSON.stringify({ id: playlistId })]
    shuffleProcess.running = true
  }

  function playAlbumShuffled() {
    if (view !== "album" || !currentAlbumId || songs.length === 0 || shuffleProcess.running) return
    shuffleBusy = true
    error = ""
    shuffleProcess.command = ["python3", helper, "playAlbum", currentAlbumId]
    shuffleProcess.running = true
  }

  function playArtistShuffled() {
    if (view !== "artist" || !currentArtistId || albums.length === 0 || shuffleProcess.running) return
    shuffleBusy = true
    error = ""
    shuffleProcess.command = ["python3", helper, "playArtist", currentArtistId]
    shuffleProcess.running = true
  }

  function shuffleLibrary() {
    if (shuffleProcess.running) return
    shuffleBusy = true
    error = ""
    shuffleProcess.command = ["python3", helper, "playRandom"]
    shuffleProcess.running = true
  }

  function beginSetup() {
    setupError = ""
    setupOpen = true
  }

  function cancelSetup() {
    if (configured) setupOpen = false
  }

  function configure(payload) {
    if (setupProcess.running || setupBusy) return
    setupError = ""
    setupBusy = true
    setupProcess.secret = JSON.stringify(payload)
    setupProcess.running = true
  }

  function playAt(index) {
    if (index < 0 || index >= songs.length) return
    if (view === "playlist")
      Quickshell.execDetached(["python3", helper, "playPlaylistAt", JSON.stringify({ id: playlistId, index: playlistOffset + index })])
    else
      Quickshell.execDetached(["python3", helper, "play", JSON.stringify({ songs: songs, index: index, shuffle: false })])
    song = songs[index]
    playing = true
    paused = false
    shuffled = false
    playbackError = ""
    position = 0
    queueLength = view === "playlist" ? playlistTotal : songs.length
  }

  function control(action, argument) {
    var command = ["python3", helper, action]
    if (argument !== undefined) command.push(String(argument))
    Quickshell.execDetached(command)
  }
  function togglePlayback() { control("toggle") }
  function next() { control("next") }
  function previous() { control("previous") }
  function stop() { control("stop") }
  function seek(seconds) { control("seek", seconds) }

  Process {
    id: configProcess
    command: ["python3", root.helper, "configStatus"]
    stdout: StdioCollector { id: configOutput; waitForEnd: true }
    onExited: {
      try {
        var result = JSON.parse(configOutput.text)
        root.configured = result.configured === true
        root.serverKind = result.kind || "subsonic"
        root.setupError = result.error || ""
        if (root.configured) root.home()
      } catch (e) {
        root.setupError = "Could not read server configuration"
      }
      root.configChecked = true
    }
  }

  Process {
    id: setupProcess
    property string secret: ""
    command: ["python3", root.helper, "configure"]
    stdinEnabled: true
    stdout: StdioCollector { id: setupOutput; waitForEnd: true }
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
    onExited: {
      secret = ""
      try {
        var result = JSON.parse(setupOutput.text)
        if (!result.ok) root.setupError = result.error || "Could not connect to the server"
        else {
          root.configured = true
          root.serverKind = result.kind || "subsonic"
          root.setupOpen = false
          root.home()
        }
      } catch (e) {
        root.setupError = "Could not complete server setup"
      }
      root.setupBusy = false
    }
  }

  Process {
    id: shuffleProcess
    stdout: StdioCollector { id: shuffleOutput; waitForEnd: true }
    onExited: {
      try {
        var result = JSON.parse(shuffleOutput.text)
        if (!result.ok) root.error = result.error || "Shuffle failed"
        else {
          root.song = result.song || null
          root.shuffled = result.shuffled === true
          root.radioMode = result.radioMode === true
          root.playbackError = result.playbackError || ""
        }
      } catch (e) {
        root.error = "Shuffle failed"
      }
      root.shuffleBusy = false
    }
  }

  Process {
    id: catalogProcess
    stdout: StdioCollector { id: catalogOutput; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        var result = JSON.parse(catalogOutput.text)
        if (!result.ok) {
          root.error = result.error || "Server unavailable"
        } else if (root.activeCatalog && result.kind === root.activeCatalog.kind && !root.pendingCatalog) {
          if (result.kind === "albums" || result.kind === "search" || result.kind === "artist") root.albums = result.albums || []
          if (result.kind === "search" || result.kind === "artists" || result.kind === "artistsPage" || result.kind === "artistsRefresh") root.artists = result.artists || []
          if (result.kind === "artists" || result.kind === "artistsPage" || result.kind === "artistsRefresh") {
            root.artistTotal = Number(result.totalArtists || 0)
            root.artistOffset = Number(result.offset || 0)
          }
          if (result.kind === "playlists") root.playlists = result.playlists || []
          if (result.kind === "search" || result.kind === "album" || result.kind === "playlist" || result.kind === "playlistPage" || result.kind === "playlistRefresh") root.songs = result.songs || []
          if (result.kind === "album") {
            root.albumName = result.name || "Album"
            root.albumArtist = result.artist || ""
          }
          if (result.kind === "artist") root.artistName = result.name || "Artist"
          if (result.kind === "playlist" || result.kind === "playlistPage" || result.kind === "playlistRefresh") {
            root.playlistName = result.name || "Playlist"
            root.playlistTotal = Number(result.totalSongs || 0)
            root.playlistOffset = Number(result.offset || 0)
          }
        }
      } catch (e) {
        root.error = "Unreadable server response"
      }
      root.loading = root.pendingCatalog !== null
      root.activeCatalog = null
      Qt.callLater(root.runCatalog)
    }
  }

  Process {
    id: statusProcess
    command: ["python3", root.helper, "status"]
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    onExited: {
      try {
        var result = JSON.parse(statusOutput.text)
        if (!result.ok) return
        root.song = result.song || null
        root.playing = result.playing === true
        root.paused = result.paused === true
        root.position = Number(result.position || 0)
        root.duration = Number(result.duration || 0)
        root.queueLength = Number(result.queueLength || 0)
        root.shuffled = result.shuffled === true
        root.radioMode = result.radioMode === true
        root.playbackError = result.playbackError || ""
      } catch (e) { }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.configured
    triggeredOnStart: true
    onTriggered: if (!statusProcess.running) statusProcess.running = true
  }

  Component.onCompleted: configProcess.running = true
}

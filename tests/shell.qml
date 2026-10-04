import QtQuick
import QtTest
import Quickshell
import "../" as Lazy

ShellRoot {
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 500
    implicitHeight: 1100

    QtObject {
      id: music
      property bool configChecked: true
      property bool configured: true
      property bool setupOpen: false
      property bool setupBusy: false
      property bool disconnectBusy: false
      property string setupError: ""
      property string serverKind: "subsonic"
      property string serverUrl: "https://music.example.com"
      property string username: "test"
      property string view: "home"
      property var albums: []
      property var artists: []
      property var playlists: []
      property var songs: []
      property var song: null
      property bool playing: false
      property bool loading: false
      property bool shuffleBusy: false
      property bool radioMode: false
      property bool shuffled: false
      property real position: 0
      property real duration: 0
      property int artistOffset: 0
      property int artistTotal: 0
      property int playlistOffset: 0
      property int playlistTotal: 0
      property string albumName: "Album"
      property string albumArtist: "Artist"
      property string artistName: "Artist"
      property string playlistName: "Playlist"
      property string error: ""
      property string playbackError: ""
      property string action: ""
      property var argument: null

      function home() { view = "home"; action = "home" }
      function showArtists() { view = "artists"; action = "artists" }
      function showPlaylists() { view = "playlists"; action = "playlists" }
      function openAlbum(id) { view = "album"; action = "album"; argument = id }
      function openArtist(id) { view = "artist"; action = "artist"; argument = id }
      function openPlaylist(id) { view = "playlist"; action = "playlist"; argument = id }
      function back(query) { view = "home"; action = "back"; argument = query }
      function search(query) { view = query ? "search" : "home"; action = "search"; argument = query }
      function playAt(index) { action = "play"; argument = index; song = songs[index] }
      function togglePlayback() { action = "toggle" }
      function previous() { action = "previous" }
      function next() { action = "next" }
      function stop() { action = "stop" }
      function beginSetup() { setupOpen = true }
      function cancelSetup() { setupOpen = false }
      function artistsPage(offset) { artistOffset = offset; action = "artistsPage" }
      function playlistPage(offset) { playlistOffset = offset; action = "playlistPage" }
    }

    QtObject {
      id: fakeWidget
      property var service: music
      property bool opened: true
      function close() { opened = false }
    }

    Lazy.Panel {
      id: panel
      widget: fakeWidget
      width: 380
      height: implicitHeight
    }

    QtObject {
      id: tooltipBar
      property bool vertical: false
      property int barSize: 32
      property string fontFamily: "sans-serif"
      property color barForeground: "white"
      property color urgent: "red"
      property bool foregroundAnimationEnabled: false
      property string tooltip: ""
      property int showCount: 0
      function registerClickTarget(target) {}
      function unregisterClickTarget(target) {}
      function showTooltip(target, text) { tooltip = text; showCount += 1 }
      function hideTooltip(target) { tooltip = "" }
    }

    Lazy.MusicIconButton {
      id: musicIcon
      x: 420
      y: 20
      width: implicitWidth
      height: implicitHeight
      text: "󰎆"
      bar: tooltipBar
      musicService: music
    }

    TestCase {
      id: tests
      name: "LazyMusicKeyboard"
      when: ready
      property bool ready: false

      function buttons(item) {
        var found = []
        if (item.focusable !== undefined) found.push(item)
        for (var i = 0; i < item.children.length; ++i)
          found = found.concat(buttons(item.children[i]))
        return found
      }

      function button(text) {
        var all = buttons(panel)
        for (var i = 0; i < all.length; ++i)
          if (all[i].text === text && all[i].visible) return all[i]
        fail("Missing visible button: " + text)
      }

      function init() {
        mouseMove(panel, 5, 5)
        music.setupOpen = false
        music.loading = false
        music.song = null
        music.view = "home"
        music.albums = [{ id: "a", name: "Album A" }, { id: "b", name: "Album B" }]
        music.artists = [{ id: "artist", name: "Artist" }]
        music.playlists = [{ id: "playlist", name: "Playlist", songCount: 2 }]
        music.songs = [{ id: "s1", title: "Song 1" }, { id: "s2", title: "Song 2" }]
        music.artistOffset = 0
        music.artistTotal = 200
        fakeWidget.opened = true
        panel.focusKeyboard()
        wait(10)
        var list = panel.keyboardFocusTarget
        compare(list.activeFocus, true)
        keyClick(Qt.Key_F, Qt.ControlModifier)
        keyClick(Qt.Key_A, Qt.ControlModifier)
        keyClick(Qt.Key_Backspace)
        keyClick(Qt.Key_Down)
        music.action = ""
        music.argument = null
      }

      function test_tooltipUpdatesWhileHovered() {
        music.song = { id: "one", title: "First track", artist: "First artist" }
        mouseMove(musicIcon, musicIcon.width / 2, musicIcon.height / 2)
        tryCompare(musicIcon, "tooltipHovered", true)
        compare(tooltipBar.tooltip, "First track · First artist")
        var count = tooltipBar.showCount
        music.song = { id: "two", title: "Next track", artist: "Next artist" }
        tryCompare(tooltipBar, "tooltip", "Next track · Next artist")
        compare(tooltipBar.showCount, count + 1)
        music.song = { id: "two", title: "Next track", artist: "Next artist" }
        compare(tooltipBar.showCount, count + 1)
        music.song = null
        tryCompare(tooltipBar, "tooltip", "Lazy Music")
        mouseMove(panel, 5, 5)
        tryCompare(musicIcon, "tooltipHovered", false)
        count = tooltipBar.showCount
        music.song = { id: "three", title: "Third track" }
        compare(tooltipBar.showCount, count)
        mouseMove(musicIcon, musicIcon.width / 2, musicIcon.height / 2)
        tryCompare(tooltipBar, "tooltip", "Third track")
      }

      function cleanup() {
        console.log("KEYBOARD_CASE", qtest_results.functionName, qtest_results.failed ? "FAIL" : "PASS")
      }

      onCompletedChanged: if (completed) {
        console.log(qtest_results.failCount === 0 ? "KEYBOARD_TESTS_PASS" : "KEYBOARD_TESTS_FAIL",
                    "passed:", qtest_results.passCount, "failed:", qtest_results.failCount)
      }

      function test_arrowsAndScrolling() {
        var albums = []
        for (var i = 0; i < 100; ++i) albums.push({ id: String(i), name: "Album " + i })
        music.albums = albums
        wait(10)
        var list = panel.keyboardFocusTarget
        compare(list.currentIndex, 0)
        keyClick(Qt.Key_Up)
        compare(list.currentIndex, 0)
        keyClick(Qt.Key_Down)
        compare(list.currentIndex, 1)
        keyClick(Qt.Key_PageDown)
        verify(list.currentIndex > 1)
        keyClick(Qt.Key_End)
        compare(list.currentIndex, 99)
        verify(list.contentY > 0)
        keyClick(Qt.Key_Down)
        compare(list.currentIndex, 99)
        keyClick(Qt.Key_Home)
        compare(list.currentIndex, 0)
        compare(list.contentY, 0)
      }

      function test_openAndBack() {
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        compare(music.action, "album")
        compare(music.argument, "b")
        keyClick(Qt.Key_Left)
        compare(music.action, "back")
        compare(panel.keyboardFocusTarget.activeFocus, true)
      }

      function test_mixedSearchSongIndex() {
        music.view = "search"
        wait(10)
        compare(panel.entries.length, 5)
        keyClick(Qt.Key_End)
        keyClick(Qt.Key_Return)
        compare(music.action, "")
        keyClick(Qt.Key_Right)
        compare(music.action, "")
        keyClick(Qt.Key_Space)
        compare(music.action, "play")
        compare(music.argument, 1)
        keyClick(Qt.Key_Space)
        compare(music.action, "toggle")
      }

      function test_artistAndPlaylist() {
        music.view = "artists"
        wait(10)
        keyClick(Qt.Key_Right)
        compare(music.action, "artist")
        compare(music.argument, "artist")
        music.view = "playlists"
        wait(10)
        keyClick(Qt.Key_Return)
        compare(music.action, "playlist")
        compare(music.argument, "playlist")
      }

      function test_songSelectionRequiresSpace() {
        music.view = "album"
        wait(10)
        var list = panel.keyboardFocusTarget
        keyClick(Qt.Key_Down)
        compare(music.action, "")
        keyClick(Qt.Key_Return)
        keyClick(Qt.Key_Right)
        compare(music.action, "")
        keyClick(Qt.Key_Up)
        compare(list.currentIndex, 0)
        compare(music.action, "")
        keyClick(Qt.Key_Escape)
        compare(fakeWidget.opened, false)
        compare(music.action, "")
        fakeWidget.opened = true
        panel.focusKeyboard()
        keyClick(Qt.Key_Space)
        compare(music.action, "play")
        compare(music.argument, 0)
      }

      function test_leftClickPlaysSong() {
        music.view = "album"
        wait(10)
        var list = panel.keyboardFocusTarget
        mouseClick(list.itemAtIndex(1))
        compare(list.currentIndex, 1)
        compare(music.action, "play")
        compare(music.argument, 1)
      }

      function test_playButtonUsesSelectedSong() {
        music.view = "album"
        wait(10)
        keyClick(Qt.Key_Down)
        var all = buttons(panel)
        for (var i = 0; i < all.length; ++i) {
          if (all[i].tooltipText === "Play selected track") {
            all[i].forceActiveFocus()
            keyClick(Qt.Key_Return)
            compare(music.action, "play")
            compare(music.argument, 1)
            return
          }
        }
        fail("Play button missing")
      }

      function test_searchEditingAndFocus() {
        keyClick(Qt.Key_F, Qt.ControlModifier)
        var search = window.contentItem.Window.window.activeFocusItem
        verify(search !== panel.keyboardFocusTarget)
        keyClick("a")
        keyClick(Qt.Key_Space)
        keyClick("b")
        compare(search.text, "a b")
        keyClick(Qt.Key_Left)
        keyClick(Qt.Key_Backspace)
        compare(search.text, "ab")
        compare(music.action, "")
        keyClick(Qt.Key_Enter)
        compare(music.action, "search")
        compare(music.argument, "ab")
        compare(panel.keyboardFocusTarget.activeFocus, true)
      }

      function test_searchDownSubmitsPendingQuery() {
        keyClick(Qt.Key_F, Qt.ControlModifier)
        keyClick("x")
        keyClick(Qt.Key_Down)
        compare(music.action, "search")
        compare(music.argument, "x")
        compare(panel.keyboardFocusTarget.activeFocus, true)
      }

      function test_spaceAndTabButtons() {
        keyClick(Qt.Key_Space)
        compare(music.action, "toggle")
        keyClick(Qt.Key_Tab)
        verify(!panel.keyboardFocusTarget.activeFocus)
        button("ARTISTS").forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(music.action, "artists")
        button("PLAYLISTS").forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(music.action, "playlists")
        keyClick(Qt.Key_Down)
        compare(panel.keyboardFocusTarget.activeFocus, true)
      }

      function test_mediaKeys() {
        keyClick(Qt.Key_F5)
        compare(music.action, "previous")
        keyClick(Qt.Key_F6)
        compare(music.action, "toggle")
        keyClick(Qt.Key_F7)
        compare(music.action, "next")
        keyClick(Qt.Key_MediaPrevious)
        compare(music.action, "previous")
        keyClick(Qt.Key_MediaTogglePlayPause)
        compare(music.action, "toggle")
        keyClick(Qt.Key_MediaNext)
        compare(music.action, "next")
      }

      function test_mediaKeysWhileSearching() {
        keyClick(Qt.Key_F, Qt.ControlModifier)
        keyClick("a")
        keyClick(Qt.Key_F5)
        compare(music.action, "previous")
        keyClick(Qt.Key_F6)
        compare(music.action, "toggle")
        keyClick(Qt.Key_F7)
        compare(music.action, "next")
      }

      function test_loadingAndEmptyLists() {
        music.loading = true
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        compare(music.action, "")
        compare(panel.keyboardFocusTarget.currentIndex, 0)
        music.loading = false
        music.albums = []
        wait(10)
        keyClick(Qt.Key_Return)
        keyClick(Qt.Key_Up)
        compare(music.action, "")
        compare(panel.keyboardFocusTarget.currentIndex, -1)
      }

      function test_paginationButtonAndReset() {
        music.view = "artists"
        wait(10)
        verify(!button("‹").enabled)
        button("›").forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(music.action, "artistsPage")
        compare(music.artistOffset, 100)
        music.artists = [{ id: "new", name: "Next page artist" }]
        panel.focusKeyboard()
        wait(10)
        compare(panel.keyboardFocusTarget.currentIndex, 0)
        keyClick(Qt.Key_Return)
        compare(music.argument, "new")
      }

      function test_setupAndReturnFocus() {
        button("SERVER").forceActiveFocus()
        keyClick(Qt.Key_Return)
        tryCompare(panel, "setupMode", true)
        wait(10)
        var field = panel.keyboardFocusTarget
        compare(field.activeFocus, true)
        compare(field.text, music.serverUrl)
        keyClick(Qt.Key_Tab)
        verify(!field.activeFocus)
        button("CANCEL").forceActiveFocus()
        keyClick(Qt.Key_Return)
        tryCompare(panel, "setupMode", false)
        wait(10)
        compare(panel.keyboardFocusTarget.activeFocus, true)
      }

      function test_escapeAndReopen() {
        keyClick(Qt.Key_F, Qt.ControlModifier)
        keyClick(Qt.Key_Escape)
        compare(fakeWidget.opened, false)
        fakeWidget.opened = true
        panel.focusKeyboard()
        compare(panel.keyboardFocusTarget.activeFocus, true)
        keyClick(Qt.Key_Escape)
        compare(fakeWidget.opened, false)
      }
    }

    Timer { interval: 100; running: true; onTriggered: tests.ready = true }
  }

  Timer {
    interval: 40000
    running: true
    onTriggered: { console.error("KEYBOARD_TESTS_TIMEOUT"); Qt.quit() }
  }
}

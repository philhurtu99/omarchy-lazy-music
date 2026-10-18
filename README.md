# Omarchy Lazy Music Player

A small, text-only music player for the Omarchy bar. It connects directly to Navidrome or another Subsonic-compatible server, Jellyfin, or Emby. No artwork is loaded or shown.

![Illustration of the Lazy Music player with fictional track and album names](preview.png)

*Illustrative preview with fictional library data.*

## Install and connect

Requires Omarchy Shell, Python 3, `mpv`, and a music server. Run this in a terminal to install and enable Lazy Music:

```sh
omarchy plugin add https://github.com/philhurtu99/omarchy-lazy-music.git --enable
```

Confirm the install when prompted. The bar widget defaults to the right section.
While this repository is private, the command requires a GitHub account with access to it.

Click the bar widget. On first open, select **Navidrome / Subsonic**, **Jellyfin**, or **Emby**, and enter the server URL, username, and password. Use HTTPS unless the server is on a trusted local network and you explicitly enable HTTP. The **Server** button opens setup again with the current address and username filled in. Enter the new address and password to switch servers; the existing connection stays active if the new login fails. The eye button shows or hides the password you are typing. Emby URLs may be entered with or without a trailing `/emby`.

![Lazy Music server setup showing Navidrome / Subsonic, Jellyfin, and Emby options](assets/setup.png)

The password is used to authenticate and is not stored. A private session is stored at `~/.config/omarchy/lazy-music/session.json` with `0600` permissions, outside the plugin folder. Subsonic uses a salted token; Jellyfin and Emby use access tokens. **Disconnect** in the Server screen stops playback and removes this local session. It does not revoke a Jellyfin or Emby token on the server or erase cached track metadata. The plugin installs no packages or system services, asks for no elevated privileges, and runs no remote installer. Its service entry runs inside the existing Omarchy Shell process.

## Playback

- Left click opens the panel. Right click toggles pause; middle click skips to the next track.
- Hover the bar icon to see the current song and artist. The tooltip follows track changes even while the pointer stays on the icon.
- The current catalog page refreshes when you reopen the panel after a minute. If the music server is unavailable at login, the plugin retries transient connection errors automatically.
- Browse Albums, Artists, and Playlists, or search for artists, albums, and songs. Artists load in pages of 100. Select an artist to browse albums and an album to browse songs.
- **Shuffle library** starts a random mix from the full server library and fetches another random batch as the queue runs out.
- **Shuffle play** in an album or artist plays all songs from that selection in random order. **Shuffle play** in a playlist includes songs on every page.
- Large playlists are fetched once into a private local cache; the panel displays 100 tracks per page. **Refresh playlist** reloads it. **Refresh artists** reloads the artist list, including the local Subsonic cache.
- Use Previous, Play/Pause, Next, Stop, and the progress bar. Escape closes the panel.
- Like or unlike the currently playing song with the heart at the bottom right of its title and artist. Favorites are saved on the music server.

## Keyboard

The library list takes focus when the panel opens. The selected row is highlighted and scrolls into view automatically.

| Key | Action |
| --- | --- |
| ↑ / ↓ | Select the previous / next row |
| Enter / → | Open the selected artist, album or playlist; songs stay selected without starting playback |
| ← / Backspace | Go back from an artist, album or playlist |
| Home / End | Select the first / last row on the current catalog page |
| Page Up / Page Down | Move by one screen of rows |
| Ctrl+F | Focus search and select its text |
| Space | Play the selected song, or toggle play/pause if it is already the current song |
| F5 / F6 / F7 | Previous track / play-pause / next track |
| Tab / Shift+Tab | Move between buttons, search and the list |
| Escape | Close the panel |

In search, Enter submits the query and focuses the results; ↑ or ↓ also moves to the results. Selecting a song with arrows does not start playback: press Space or the Play button. A left click on a song starts playback immediately. Escape only closes the panel. Text fields keep their normal editing keys. Focused buttons activate with Enter or Space. Use Tab to reach the catalog page buttons, library tabs, shuffle and server controls. Server setup can also be completed with Tab and Enter.

F5/F6/F7 and previous/play-pause/next media keys also work while typing in the panel. To control Lazy Music with the panel closed, add these personal bindings to `~/.config/hypr/bindings.lua` (unbind any existing assignment first):

```lua
o.bind("F5", "Lazy Music: previous", "omarchy-shell lazymusic.player previous")
o.bind("F6", "Lazy Music: play/pause", "omarchy-shell lazymusic.player playPause")
o.bind("F7", "Lazy Music: next", "omarchy-shell lazymusic.player next")
```

Keyboards with media symbols may send `XF86AudioPrev`, `XF86AudioPlay`, `XF86AudioPause`, and `XF86AudioNext` instead (often using Fn). These keys are already assigned to Omarchy's general media player. [The complete binding example](examples/hypr-media-keys.lua) replaces them and adds F5/F6/F7. Reload with `hyprctl reload` and check `hyprctl configerrors`. These F keys then control Lazy Music in every app. When the panel is closed, play/pause resumes or pauses the current queue. With the panel open, it uses the selected song.

**KEYS ON / KEYS OFF**, at the right of the playback controls, turns these shortcuts off when they get in the way, for example in games. When off, the panel ignores F5/F6/F7 and media keys, and the binding example leaves those keys unbound so they reach the focused app. Volume and mute keys are not affected. The choice is kept across restarts. For the button to update Hyprland, install the helper on your `PATH`:

```sh
install -m 755 examples/lazy-music-fkeys-toggle ~/.local/bin/
```

Shell commands: `omarchy-shell shell summon lazymusic.player '{}'` and `omarchy-shell shell hide lazymusic.player`. To reopen server setup, use the **Server** button or `qs ipc -p /usr/share/omarchy/shell call lazymusic.player setup`.

## Uninstall

Stop playback before removing the plugin. Use **Stop** in the panel, or run:

```sh
python3 ~/.config/omarchy/plugins/lazymusic.player/backend.py stop
omarchy plugin remove lazymusic.player
```

Removing the plugin does not delete its private session. To remove the saved server URL and authentication token as well, run:

```sh
rm -f ~/.config/omarchy/lazy-music/session.json
```

## Data and security

The plugin runs with your user permissions inside the shared Omarchy shell. It sends your credentials only to the configured server during setup. Catalog requests and Jellyfin/Emby playback reject redirects to another origin. Subsonic authentication parameters are part of request URLs, as required by its API, so use HTTPS and consider server or reverse proxy access logs. Jellyfin and Emby use authorization headers for catalog and playback requests. For playback, a local audio relay sends those headers to the configured server; mpv receives only a loopback URL with a temporary access code.

Playback runs through local `mpv` and a Unix socket inside a `0700` runtime directory. The Jellyfin/Emby relay is a separate Python process bound to `127.0.0.1`, with its access code in a `0600` runtime file. Stop closes `mpv` and the relay. mpv starts without user scripts or configuration. Queue state in `~/.local/state/omarchy-lazy-music/` and the private playlist cache in `~/.cache/omarchy-lazy-music/` contain track metadata, but no credentials. A very large Subsonic playlist may take time on its first fetch; the response is bounded at 128 MB. Jellyfin and Emby collections are fetched in pages.

## Validate

```sh
omarchy plugin validate ~/.config/omarchy/plugins/lazymusic.player
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell ~/.config/omarchy/plugins/lazymusic.player/{BarWidget,Panel,Setup,Service}.qml
python3 ~/.config/omarchy/plugins/lazymusic.player/backend.py configStatus
```

Run the keyboard integration checks from this repository with `python3 tests/run-keyboard.py`. They use QtTest inside Quickshell with a fake music service and the installed Omarchy UI components, without connecting to a music server or playing audio.

After editing installed plugin code, use `omarchy restart shell` if changes do not appear. A plugin rescan can retain the old QML code in the running shell's cache.

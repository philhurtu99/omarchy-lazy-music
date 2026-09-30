#!/usr/bin/env python3
"""Music server catalog and mpv control for the Lazy Music Omarchy widget."""

import fcntl
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import hmac
import io
import json
import os
from pathlib import Path
import random
import re
import socket
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


PLUGIN_HOME = Path.home() / ".config/omarchy/lazy-music"
SESSION = PLUGIN_HOME / "session.json"
STATE_DIR = Path.home() / ".local/state/omarchy-lazy-music"
STATE_FILE = STATE_DIR / "state.json"
QUEUE_FILE = STATE_DIR / "queue.json"
CACHE_DIR = Path.home() / ".cache/omarchy-lazy-music/playlists"
ARTIST_CACHE_DIR = Path.home() / ".cache/omarchy-lazy-music/artists"
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "omarchy-lazy-music"
SOCKET = RUNTIME_DIR / "mpv.sock"
LOCK = RUNTIME_DIR / "lock"
PROXY_INFO = RUNTIME_DIR / "stream-proxy.json"
USER_AGENT = "LazyMusic/0.1.0"
CLIENT = "OmarchyLazyMusic"
PLAYLIST_PAGE_SIZE = 100
ARTIST_PAGE_SIZE = 100
MAX_PLAYLIST_RESPONSE_BYTES = 128_000_000
MAX_SETUP_BYTES = 16_384
MAX_PROXY_INFO_BYTES = 2_048


class SameOriginRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        before, after = urlsplit(request.full_url), urlsplit(newurl)
        if (before.scheme, before.netloc) != (after.scheme, after.netloc):
            raise ValueError("Server redirected to a different origin")
        return super().redirect_request(request, fp, code, msg, headers, newurl)


HTTP = build_opener(SameOriginRedirect)


def private_dir(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path, 0o700)


def read_session():
    if SESSION.is_symlink():
        raise ValueError("Session file must not be a symlink")
    if SESSION.stat().st_mode & 0o077:
        raise ValueError("Session permissions are too open; use chmod 600")
    if SESSION.stat().st_size > MAX_SETUP_BYTES:
        raise ValueError("Session file is too large")
    data = json.loads(SESSION.read_text())
    if not isinstance(data, dict):
        raise ValueError("Session file is invalid")
    kind = data.get("kind", "subsonic")
    required = ("serverUrl", "username", "salt", "token") if kind == "subsonic" else \
        ("serverUrl", "username", "userId", "accessToken", "deviceId") if kind in ("jellyfin", "emby") else ()
    if not required or not all(data.get(key) for key in required):
        raise ValueError("Server session is incomplete")
    validate_server_url(data["serverUrl"], allow_http=True)
    if not isinstance(data["username"], str) or len(data["username"]) > 256:
        raise ValueError("Server session is invalid")
    if kind == "subsonic" and (not all(isinstance(data[key], str) for key in ("salt", "token")) or
                                any(len(data[key]) > 128 for key in ("salt", "token"))):
        raise ValueError("Server session is invalid")
    if kind in ("jellyfin", "emby"):
        for key in ("accessToken", "userId", "deviceId"):
            value = data[key]
            if not isinstance(value, str) or len(value) > 1024 or any(char in value for char in '\r\n"'):
                raise ValueError("Server session is invalid")
    data["kind"] = kind
    return data


def save_session(session):
    private_dir(PLUGIN_HOME)
    temporary = PLUGIN_HOME / ("session." + uuid.uuid4().hex + ".tmp")
    fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(session, output)
        os.replace(temporary, SESSION)
    finally:
        temporary.unlink(missing_ok=True)


def validate_server_url(value, allow_http=False):
    url = str(value or "").strip().rstrip("/")
    parsed = urlsplit(url)
    if (len(url) > 2048 or parsed.scheme not in ("https", "http") or not parsed.hostname or
            parsed.username or parsed.password or parsed.query or parsed.fragment or
            any(char.isspace() for char in url)):
        raise ValueError("Enter a complete server URL without credentials or query parameters")
    if parsed.scheme == "http" and not allow_http:
        raise ValueError("HTTPS is required unless Allow HTTP is selected")
    return url


def read_json(request, limit, timeout):
    with HTTP.open(request, timeout=timeout) as response:
        if int(response.headers.get("Content-Length", "0") or 0) > limit:
            raise ValueError("Server response is too large")
        payload = response.read(limit + 1)
        compressed = response.headers.get("Content-Encoding", "").lower() == "gzip"
    if len(payload) > limit:
        raise ValueError("Server response is too large")
    if compressed:
        with gzip.GzipFile(fileobj=io.BytesIO(payload)) as stream:
            payload = stream.read(limit + 1)
        if len(payload) > limit:
            raise ValueError("Server response is too large")
    result = json.loads(payload)
    if not isinstance(result, dict):
        raise ValueError("Invalid server response")
    return result


def api_url(endpoint, params=None, session=None):
    session = session or read_session()
    values = {
        "u": session["username"], "s": session["salt"], "t": session["token"],
        "v": "1.13.0", "c": CLIENT, "f": "json"
    }
    values.update(params or {})
    return session["serverUrl"].rstrip("/") + "/rest/" + endpoint + ".view?" + urlencode(values)


def api(endpoint, params=None, session=None):
    request = Request(api_url(endpoint, params, session), headers={"User-Agent": USER_AGENT,
                                                        "Accept": "application/json",
                                                        "Accept-Encoding": "gzip"})
    limit = (MAX_PLAYLIST_RESPONSE_BYTES if endpoint == "getPlaylist" else
             32_000_000 if endpoint == "getArtists" else 4_000_000)
    data = read_json(request, limit, 90 if endpoint == "getPlaylist" else 30 if endpoint == "getArtists" else 12).get("subsonic-response", {})
    if not isinstance(data, dict):
        raise ValueError("Invalid Subsonic response")
    if data.get("status") != "ok":
        error = data.get("error")
        code = error.get("code", "unknown") if isinstance(error, dict) else "unknown"
        raise ValueError("Subsonic error " + str(code))
    return data


def media_authorization(session):
    prefix = "Emby" if session["kind"] == "emby" else "MediaBrowser"
    base = (prefix + ' Client="Lazy Music", Device="Omarchy", '
            'DeviceId="' + session["deviceId"] + '", Version="0.1.0"')
    if session["kind"] == "emby":
        base += ', UserId="' + session.get("userId", "") + '"'
        return base
    token = session.get("accessToken")
    return base + (', Token="' + token + '"' if token else "")


def media_url(path, params=None, session=None):
    session = session or read_session()
    base = session["serverUrl"].rstrip("/")
    if session["kind"] == "emby" and not base.lower().endswith("/emby"):
        base += "/emby"
    url = base + "/" + path.lstrip("/")
    values = {key: value for key, value in (params or {}).items() if value is not None}
    return url + ("?" + urlencode(values) if values else "")


def media_api(path, params=None, session=None, body=None):
    session = session or read_session()
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json", "Accept-Encoding": "gzip",
               "Authorization": media_authorization(session)}
    if session["kind"] == "emby" and session.get("accessToken"):
        headers["X-Emby-Token"] = session["accessToken"]
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    request = Request(media_url(path, params, session), data=data, headers=headers)
    return read_json(request, 16_000_000, 30)


def media_items(path, params=None, convert=None, page_size=500):
    params = dict(params or {})
    params.update({"StartIndex": 0, "Limit": page_size, "EnableImages": "false",
                   "EnableUserData": "false", "EnableTotalRecordCount": "true"})
    transform = convert or (lambda item: item)
    def fetch(start, limit=page_size):
        response = media_api(path, params | {"StartIndex": start, "Limit": limit})
        page = response.get("Items", [])
        if not isinstance(page, list):
            raise ValueError("Invalid media server item list")
        return response, page

    result = []
    first, page = fetch(0)
    total = int(first.get("TotalRecordCount") or 0)
    if total < 0 or total > 200_000 or len(page) > 200_000:
        raise ValueError("Media server collection is too large or invalid")
    if total and not page:
        raise ValueError("Media server stopped before the collection was complete")

    def append_page(page):
        result.extend(value for item in page if (value := transform(item)) is not None)

    append_page(page)
    offset = len(page)
    if total:
        effective_size = min(page_size, len(page))
        while offset < total:
            starts = [offset + effective_size * index for index in range(4)
                      if offset + effective_size * index < total]
            with ThreadPoolExecutor(max_workers=len(starts)) as pool:
                pages = list(pool.map(lambda start: fetch(start, effective_size)[1], starts))
            if any(len(items) != min(effective_size, total - start)
                   for start, items in zip(starts, pages)):
                break
            for items in pages:
                append_page(items)
            offset += sum(len(items) for items in pages)
    while offset < total or not total and page:
        _, page = fetch(offset)
        if not page:
            if total:
                raise ValueError("Media server stopped before the collection was complete")
            break
        offset += len(page)
        if offset > 200_000:
            raise ValueError("Media server collection is too large")
        append_page(page)
    return result


def configure_session(payload):
    if not isinstance(payload, dict):
        raise ValueError("Invalid setup data")
    kind = payload.get("kind")
    if kind not in ("subsonic", "jellyfin", "emby"):
        raise ValueError("Choose a server type")
    server = validate_server_url(payload.get("serverUrl"), payload.get("allowHttp") is True)
    username = str(payload.get("username") or "").strip()
    password = str(payload.get("password") or "")
    if not 0 < len(username) <= 256 or not 0 < len(password) <= 4096:
        raise ValueError("Enter a username and password")
    if kind == "subsonic":
        salt = os.urandom(8).hex()
        token = hashlib.md5((password + salt).encode()).hexdigest()
        session = {"kind": kind, "serverUrl": server, "username": username, "salt": salt, "token": token}
        api("ping", session=session)
    else:
        candidate = {"kind": kind, "serverUrl": server, "username": username,
                     "deviceId": str(uuid.uuid4())}
        response = media_api("Users/AuthenticateByName", session=candidate,
                                body={"Username": username, "Pw": password})
        access_token = str(response.get("AccessToken") or "")
        user = response.get("User")
        user_id = str(user.get("Id") or "") if isinstance(user, dict) else ""
        if (not access_token or len(access_token) > 1024 or any(char in access_token for char in '\r\n"') or
                not user_id or len(user_id) > 256 or any(char in user_id for char in '\r\n"')):
            raise ValueError("Server authentication failed")
        session = candidate | {"accessToken": access_token, "userId": user_id}
    save_session(session)
    return {"ok": True, "configured": True, "kind": kind}


def config_status():
    try:
        session = read_session()
        return {"ok": True, "configured": True, "kind": session["kind"]}
    except FileNotFoundError:
        return {"ok": True, "configured": False}
    except (ValueError, json.JSONDecodeError) as error:
        return {"ok": True, "configured": False, "error": str(error)[:160]}


def song(item):
    return {key: str(item.get(key) or "")[:500] for key in ("id", "title", "artist", "album")} | {
        "duration": max(0, int(item.get("duration") or 0))
    }


def album(item):
    return {key: str(item.get(key) or "")[:500] for key in ("id", "name", "artist")} | {
        "songCount": max(0, int(item.get("songCount") or 0))
    }


def artist(item):
    return {key: str(item.get(key) or "")[:500] for key in ("id", "name")} | {
        "albumCount": max(0, int(item.get("albumCount") or 0))
    }


def playlist(item):
    return {key: str(item.get(key) or "")[:500] for key in ("id", "name")} | {
        "songCount": max(0, int(item.get("songCount") or 0))
    }


def media_song(item):
    artists = item.get("Artists") or []
    name = (", ".join(str(artist) for artist in artists)
            if isinstance(artists, list) and artists else item.get("AlbumArtist") or "")
    return {"id": str(item.get("Id") or "")[:500], "title": str(item.get("Name") or "")[:500],
            "artist": str(name)[:500], "album": str(item.get("Album") or "")[:500],
            "duration": max(0, int(item.get("RunTimeTicks") or 0) // 10_000_000)} if item.get("Id") else None


def media_album(item):
    count = item.get("ChildCount")
    return {"id": str(item.get("Id") or "")[:500], "name": str(item.get("Name") or "")[:500],
            "artist": str(item.get("AlbumArtist") or "")[:500],
            "songCount": max(0, int(count)) if count is not None else None} if item.get("Id") else None


def media_artist(item):
    count = item.get("AlbumCount", item.get("ChildCount"))
    return {"id": str(item.get("Id") or "")[:500], "name": str(item.get("Name") or "")[:500],
            "albumCount": max(0, int(count)) if count is not None else None} if item.get("Id") else None


def media_playlist(item):
    count = item.get("ChildCount")
    return {"id": str(item.get("Id") or "")[:500], "name": str(item.get("Name") or "")[:500],
            "songCount": max(0, int(count)) if count is not None else None} if item.get("Id") else None


def media_user_path(session=None):
    session = session or read_session()
    return "Users/" + quote(session["userId"], safe="") + "/Items"


def media_artist_page(offset):
    session = read_session()
    start = max(0, min(int(offset), 200_000))
    data = media_api("Artists/AlbumArtists", {"UserId": session["userId"], "StartIndex": start,
                                                   "Limit": ARTIST_PAGE_SIZE, "SortBy": "SortName",
                                                   "SortOrder": "Ascending", "EnableImages": "false"})
    return {"ok": True, "kind": "artists", "artists": [value for item in data.get("Items", [])
                                                             if (value := media_artist(item)) is not None],
            "totalArtists": int(data.get("TotalRecordCount") or 0), "offset": start}


def media_album_songs(album_id):
    def with_track_order(item):
        track = media_song(item)
        if track is None:
            return None
        return {"track": track, "disc": int(item.get("ParentIndexNumber") or 0),
                "number": int(item.get("IndexNumber") or 0)}

    entries = media_items(media_user_path(), {"ParentId": album_id, "IncludeItemTypes": "Audio",
                                            "Recursive": "true"}, with_track_order)
    entries.sort(key=lambda entry: (entry["disc"], entry["number"]))
    return [entry["track"] for entry in entries]


def media_artist_songs(artist_id):
    artist_filter = "ArtistIds" if read_session()["kind"] == "emby" else "AlbumArtistIds"
    return media_items(media_user_path(), {artist_filter: artist_id,
                                           "IncludeItemTypes": "Audio", "Recursive": "true"}, media_song)


def media_random_tracks():
    data = media_api(media_user_path(), {"IncludeItemTypes": "Audio", "Recursive": "true",
                                                    "SortBy": "Random", "Limit": 100, "EnableImages": "false"})
    return [value for item in data.get("Items", []) if (value := media_song(item)) is not None]


def media_catalog(command, argument=""):
    path = media_user_path()
    if command == "albums":
        data = media_api(path, {"IncludeItemTypes": "MusicAlbum", "Recursive": "true",
                                    "SortBy": "DateCreated", "SortOrder": "Descending", "Limit": 24,
                                    "EnableImages": "false"})
        return {"ok": True, "kind": "albums", "albums": [value for item in data.get("Items", [])
                                                              if (value := media_album(item)) is not None]}
    if command in ("artists", "artistsPage", "artistsRefresh"):
        return media_artist_page(argument if command == "artistsPage" else 0) | {"kind": command}
    if command == "search":
        query = argument[:150]
        queries = [("Artists/AlbumArtists", {"UserId": read_session()["userId"], "SearchTerm": query, "Limit": 12}),
                   (path, {"SearchTerm": query, "IncludeItemTypes": "MusicAlbum", "Recursive": "true", "Limit": 12}),
                   (path, {"SearchTerm": query, "IncludeItemTypes": "Audio", "Recursive": "true", "Limit": 30})]
        with ThreadPoolExecutor(max_workers=3) as pool:
            results = list(pool.map(lambda entry: media_api(entry[0], entry[1]), queries))
        return {"ok": True, "kind": "search",
                "artists": [value for item in results[0].get("Items", []) if (value := media_artist(item)) is not None],
                "albums": [value for item in results[1].get("Items", []) if (value := media_album(item)) is not None],
                "songs": [value for item in results[2].get("Items", []) if (value := media_song(item)) is not None]}
    if command == "artist":
        data = media_api(path + "/" + quote(argument[:500], safe=""))
        artist_filter = "ArtistIds" if read_session()["kind"] == "emby" else "AlbumArtistIds"
        albums = media_items(path, {artist_filter: argument[:500], "IncludeItemTypes": "MusicAlbum",
                                    "Recursive": "true", "SortBy": "SortName"}, media_album)
        return {"ok": True, "kind": "artist", "name": str(data.get("Name") or "Artist")[:500],
                "albums": albums}
    if command == "album":
        album_id = quote(argument[:500], safe="")
        data = media_api(path + "/" + album_id)
        return {"ok": True, "kind": "album", "name": str(data.get("Name") or "Album")[:500],
                "artist": str(data.get("AlbumArtist") or "")[:500], "songs": media_album_songs(argument[:500])}
    if command == "playlists":
        items = media_items(path, {"IncludeItemTypes": "Playlist", "Recursive": "true",
                                       "SortBy": "SortName"}, media_playlist)
        return {"ok": True, "kind": "playlists", "playlists": items}
    if command in ("playlist", "playlistPage", "playlistRefresh"):
        if command == "playlistPage":
            request = json.loads(argument)
            result = playlist_page(str(request.get("id") or "")[:500], request.get("offset", 0))
        else:
            result = playlist_page(argument[:500], 0, refresh=command == "playlistRefresh")
        return result | {"kind": command}
    if command == "ping":
        media_api(path, {"Limit": 1})
        return {"ok": True}
    raise ValueError("Unknown command")


def playlist_cache_path(playlist_id):
    session = read_session()
    key = session["serverUrl"] + "\0" + session["username"] + "\0" + playlist_id
    if session["kind"] in ("jellyfin", "emby"):
        key += "\0" + session["kind"]
    return CACHE_DIR / (hashlib.sha256(key.encode()).hexdigest() + ".json")


def load_playlist(playlist_id, refresh=False):
    path = playlist_cache_path(playlist_id)
    if not refresh:
        try:
            return json.loads(path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            pass
    if read_session()["kind"] in ("jellyfin", "emby"):
        session = read_session()
        data = media_api(media_user_path(session) + "/" + quote(playlist_id, safe=""))
        tracks = media_items("Playlists/" + quote(playlist_id, safe="") + "/Items",
                               {"UserId": session["userId"]},
                               lambda item: media_song(item) if item.get("Type") == "Audio" else None)
        result = {"id": playlist_id, "name": str(data.get("Name") or "Playlist")[:500], "songs": tracks}
    else:
        data = api("getPlaylist", {"id": playlist_id}).get("playlist", {})
        result = {"id": playlist_id, "name": str(data.get("name") or "Playlist")[:500],
                  "songs": [song(x) for x in data.get("entry", []) if x.get("id")]}
    private_dir(CACHE_DIR)
    temporary = CACHE_DIR / (path.name + f".{os.getpid()}.tmp")
    fd = os.open(temporary, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as output:
        json.dump(result, output)
    os.replace(temporary, path)
    return result


def playlist_page(playlist_id, offset, refresh=False):
    data = load_playlist(playlist_id, refresh)
    tracks = data["songs"]
    start = max(0, min(int(offset), max(0, len(tracks) - 1)))
    return {"ok": True, "kind": "playlist", "name": data["name"], "id": playlist_id,
            "songs": tracks[start:start + PLAYLIST_PAGE_SIZE], "totalSongs": len(tracks), "offset": start}


def artist_cache_path():
    session = read_session()
    key = session["serverUrl"] + "\0" + session["username"]
    return ARTIST_CACHE_DIR / (hashlib.sha256(key.encode()).hexdigest() + ".json")


def load_artists(refresh=False):
    path = artist_cache_path()
    if not refresh:
        try:
            return json.loads(path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            pass
    groups = api("getArtists").get("artists", {}).get("index", [])
    result = [artist(item) for group in groups for item in group.get("artist", []) if item.get("id")]
    result.sort(key=lambda item: item["name"].casefold())
    private_dir(ARTIST_CACHE_DIR)
    temporary = ARTIST_CACHE_DIR / (path.name + f".{os.getpid()}.tmp")
    fd = os.open(temporary, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as output:
        json.dump(result, output)
    os.replace(temporary, path)
    return result


def artist_page(offset, refresh=False):
    artists = load_artists(refresh)
    start = max(0, min(int(offset), max(0, len(artists) - 1)))
    return {"ok": True, "kind": "artists", "artists": artists[start:start + ARTIST_PAGE_SIZE],
            "totalArtists": len(artists), "offset": start}


def album_songs(album_id):
    if read_session()["kind"] in ("jellyfin", "emby"):
        return media_album_songs(album_id)
    data = api("getAlbum", {"id": album_id}).get("album", {})
    return [song(item) for item in data.get("song", []) if item.get("id")]


def artist_songs(artist_id):
    if read_session()["kind"] in ("jellyfin", "emby"):
        return media_artist_songs(artist_id)
    data = api("getArtist", {"id": artist_id}).get("artist", {})
    album_ids = [str(item.get("id"))[:500] for item in data.get("album", []) if item.get("id")]
    if not album_ids:
        return []
    with ThreadPoolExecutor(max_workers=4) as pool:
        return [track for tracks in pool.map(album_songs, album_ids) for track in tracks]


def catalog(command, argument=""):
    if read_session()["kind"] in ("jellyfin", "emby"):
        return media_catalog(command, argument)
    if command == "albums":
        data = api("getAlbumList2", {"type": "newest", "size": "24"})
        return {"ok": True, "kind": "albums", "albums": [album(x) for x in data.get("albumList2", {}).get("album", [])]}
    if command == "search":
        data = api("search3", {"query": argument[:150], "songCount": "30", "albumCount": "12", "artistCount": "12"})
        found = data.get("searchResult3", {})
        return {"ok": True, "kind": "search", "songs": [song(x) for x in found.get("song", [])],
                "albums": [album(x) for x in found.get("album", [])],
                "artists": [artist(x) for x in found.get("artist", [])]}
    if command == "artists":
        return artist_page(0)
    if command == "artistsPage":
        return artist_page(argument) | {"kind": "artistsPage"}
    if command == "artistsRefresh":
        return artist_page(0, refresh=True) | {"kind": "artistsRefresh"}
    if command == "artist":
        data = api("getArtist", {"id": argument[:500]}).get("artist", {})
        return {"ok": True, "kind": "artist", "name": str(data.get("name") or "Artist")[:500],
                "albums": [album(x) for x in data.get("album", [])]}
    if command == "album":
        data = api("getAlbum", {"id": argument[:500]}).get("album", {})
        return {"ok": True, "kind": "album", "name": str(data.get("name") or "")[:500],
                "artist": str(data.get("artist") or "")[:500], "songs": [song(x) for x in data.get("song", [])]}
    if command == "playlists":
        data = api("getPlaylists").get("playlists", {})
        return {"ok": True, "kind": "playlists", "playlists": [playlist(x) for x in data.get("playlist", [])]}
    if command == "playlist":
        return playlist_page(argument[:500], 0)
    if command == "playlistRefresh":
        return playlist_page(argument[:500], 0, refresh=True) | {"kind": "playlistRefresh"}
    if command == "playlistPage":
        request = json.loads(argument)
        return playlist_page(str(request.get("id") or "")[:500], request.get("offset", 0)) | {"kind": "playlistPage"}
    if command == "ping":
        api("ping")
        return {"ok": True}
    raise ValueError("Unknown command")


def default_state():
    return {"index": -1, "queueLength": 0, "song": None, "active": False,
            "seenActive": False, "shuffled": False, "radioMode": False,
            "startedAt": 0, "playbackError": ""}


def read_state():
    try:
        value = json.loads(STATE_FILE.read_text())
        if isinstance(value, dict):
            return default_state() | {key: entry for key, entry in value.items() if key in default_state()}
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    return default_state()


def save_state(state):
    private_dir(STATE_DIR)
    temporary = STATE_DIR / f"state.{os.getpid()}.tmp"
    fd = os.open(temporary, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(state, stream)
    os.replace(temporary, STATE_FILE)


def save_queue(tracks):
    private_dir(STATE_DIR)
    temporary = STATE_DIR / f"queue.{os.getpid()}.tmp"
    fd = os.open(temporary, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as output:
        json.dump(tracks, output)
    os.replace(temporary, QUEUE_FILE)


def read_queue():
    try:
        data = json.loads(QUEUE_FILE.read_text())
        return data if isinstance(data, list) else []
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def media_stream_url(session, track_id):
    path = "Audio/" + quote(track_id, safe="")
    if session["kind"] == "emby":
        return media_url(path + "/stream", {"static": "true"}, session)
    return media_url(path + "/universal",
                     {"UserId": session["userId"], "DeviceId": session["deviceId"],
                      "MaxStreamingBitrate": 140_000_000}, session)


class StreamProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, _format, *_args):
        pass

    def do_HEAD(self):
        self.handle_stream()

    def do_GET(self):
        self.handle_stream()

    def handle_stream(self):
        path = urlsplit(self.path)
        parts = path.path.lstrip("/").split("/", 1)
        if path.query or len(parts) != 2 or not hmac.compare_digest(parts[0], self.server.nonce):
            self.send_error(404)
            return
        route = parts[1]
        if route == "health":
            self.send_response(204)
            self.end_headers()
            return
        if route == "shutdown":
            self.send_response(204)
            self.end_headers()
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        if not route.startswith("audio/"):
            self.send_error(404)
            return
        track_id = unquote(route[6:])
        if not track_id or len(track_id) > 500 or any(ord(char) < 32 for char in track_id):
            self.send_error(400)
            return
        byte_range = self.headers.get("Range")
        if byte_range and (len(byte_range) > 100 or not re.fullmatch(r"bytes=(?:\d+-\d*|-\d+)", byte_range)):
            self.send_error(416)
            return
        try:
            session = read_session()
            if session["kind"] not in ("jellyfin", "emby"):
                raise ValueError("Unsupported server type")
            headers = {"User-Agent": USER_AGENT, "Accept-Encoding": "identity",
                       "Authorization": media_authorization(session)}
            if session["kind"] == "emby":
                headers["X-Emby-Token"] = session["accessToken"]
            if byte_range:
                headers["Range"] = byte_range
            request = Request(media_stream_url(session, track_id), headers=headers)
            with HTTP.open(request, timeout=30) as response:
                self.send_response(response.status)
                for name in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"):
                    if value := response.headers.get(name):
                        self.send_header(name, value)
                self.end_headers()
                if self.command == "GET":
                    while chunk := response.read(65_536):
                        self.wfile.write(chunk)
        except HTTPError as error:
            self.send_error(error.code)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except (OSError, ValueError, URLError):
            self.send_error(502, "Upstream unavailable")


def read_proxy_info():
    try:
        if PROXY_INFO.is_symlink() or PROXY_INFO.stat().st_size > MAX_PROXY_INFO_BYTES:
            return None
        info = json.loads(PROXY_INFO.read_text())
        port, nonce = info.get("port"), info.get("nonce")
        if isinstance(port, int) and 0 < port < 65536 and isinstance(nonce, str) and re.fullmatch(r"[0-9a-f]{48}", nonce):
            return info
    except (FileNotFoundError, ValueError, OSError, AttributeError):
        pass
    return None


def proxy_request(info, action):
    url = f"http://127.0.0.1:{info['port']}/{info['nonce']}/{action}"
    with HTTP.open(Request(url), timeout=0.5) as response:
        return response.status == 204


def ensure_stream_proxy():
    private_dir(RUNTIME_DIR)
    info = read_proxy_info()
    if info:
        try:
            if proxy_request(info, "health"):
                return info
        except (OSError, ValueError, URLError):
            pass
    PROXY_INFO.unlink(missing_ok=True)
    process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "streamProxy"],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(30):
        time.sleep(0.1)
        info = read_proxy_info()
        if info:
            try:
                if proxy_request(info, "health"):
                    return info
            except (OSError, ValueError, URLError):
                pass
        if process.poll() is not None:
            break
    if process.poll() is None:
        process.terminate()
    raise RuntimeError("Local audio relay did not start")


def stop_stream_proxy():
    info = read_proxy_info()
    if info:
        try:
            proxy_request(info, "shutdown")
        except (OSError, ValueError, URLError):
            pass


def run_stream_proxy():
    private_dir(RUNTIME_DIR)
    server = ThreadingHTTPServer(("127.0.0.1", 0), StreamProxyHandler)
    server.daemon_threads = True
    server.nonce = os.urandom(24).hex()
    info = {"pid": os.getpid(), "port": server.server_address[1], "nonce": server.nonce}
    temporary = RUNTIME_DIR / f"stream-proxy.{os.getpid()}.tmp"
    fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(info, output)
        os.replace(temporary, PROXY_INFO)
        server.serve_forever(poll_interval=0.2)
    finally:
        server.server_close()
        temporary.unlink(missing_ok=True)
        current = read_proxy_info()
        if current and current.get("pid") == os.getpid():
            PROXY_INFO.unlink(missing_ok=True)


def mpv_command(command, timeout=2):
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(timeout)
        client.connect(str(SOCKET))
        client.sendall((json.dumps({"command": command, "request_id": 1}) + "\n").encode())
        buffer = b""
        while True:
            block = client.recv(65536)
            if not block:
                raise ConnectionError("mpv disconnected")
            buffer += block
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                message = json.loads(line)
                if message.get("request_id") == 1:
                    if message.get("error") != "success":
                        return None
                    return message.get("data") if message.get("data") is not None else "success"


def mpv_value(name):
    try:
        return mpv_command(["get_property", name], 0.7)
    except (OSError, ValueError, json.JSONDecodeError):
        return None


def ensure_mpv():
    private_dir(RUNTIME_DIR)
    if mpv_value("idle-active") is not None:
        return
    try:
        SOCKET.unlink()
    except FileNotFoundError:
        pass
    subprocess.Popen(
        ["mpv", "--no-config", "--ytdl=no", "--idle=yes", "--no-terminal", "--no-video", "--audio-display=no",
         "--input-ipc-server=" + str(SOCKET), "--user-agent=" + USER_AGENT,
         "--msg-level=all=error"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    for _ in range(25):
        time.sleep(0.08)
        if mpv_value("idle-active") is not None:
            return
    raise RuntimeError("mpv did not start")


def start_current(state):
    index = state["index"]
    queue = read_queue()
    if not 0 <= index < len(queue):
        state["active"] = False
        state["seenActive"] = False
        save_state(state)
        return
    state["song"] = queue[index]
    state["queueLength"] = len(queue)
    track_id = queue[index]["id"]
    ensure_mpv()
    session = read_session()
    if session["kind"] in ("jellyfin", "emby"):
        proxy = ensure_stream_proxy()
        url = f"http://127.0.0.1:{proxy['port']}/{proxy['nonce']}/audio/{quote(track_id, safe='')}"
    else:
        url = api_url("stream", {"id": track_id}, session)
    if mpv_command(["set_property", "http-header-fields", []]) is None:
        raise RuntimeError("mpv could not clear stream headers")
    if mpv_command(["loadfile", url, "replace"]) is None:
        raise RuntimeError("mpv could not load the track")
    mpv_command(["set_property", "pause", False])
    state["active"] = True
    state["seenActive"] = False
    state["startedAt"] = time.time()
    state["playbackError"] = ""
    save_state(state)


def start_shuffled_tracks(tracks):
    if not tracks:
        raise ValueError("No songs found")
    queue = list(tracks)
    random.SystemRandom().shuffle(queue)
    save_queue(queue)
    state = read_state()
    state.update(index=0, queueLength=len(queue), shuffled=True, radioMode=False)
    start_current(state)
    return status(read_state())


def random_tracks():
    if read_session()["kind"] in ("jellyfin", "emby"):
        return media_random_tracks()
    data = api("getRandomSongs", {"size": "100"}).get("randomSongs", {})
    return [song(item) for item in data.get("song", []) if item.get("id")]


def extend_radio_queue(state):
    queue = read_queue()
    recent = {item.get("id") for item in queue[-500:]}
    fetched = random_tracks()
    fresh = [item for item in fetched if item["id"] not in recent]
    if not fresh:
        fresh = fetched
    if not fresh:
        return False
    queue.extend(fresh)
    save_queue(queue)
    state["queueLength"] = len(queue)
    return True


def advance_queue(state):
    if state["index"] + 1 >= state["queueLength"] and state.get("radioMode"):
        extend_radio_queue(state)
    if state["index"] + 1 < state["queueLength"]:
        state["index"] += 1
        start_current(state)
        return True
    state["active"] = False
    save_state(state)
    stop_stream_proxy()
    return False


def status(state):
    idle = mpv_value("idle-active")
    if idle is False and state["active"] and not state["seenActive"]:
        state["seenActive"] = True
        save_state(state)
    elif idle is True and state["active"] and state["seenActive"]:
        advance_queue(state)
        idle = mpv_value("idle-active")
    elif state["active"] and not state["seenActive"] and state.get("startedAt") and \
            time.time() - state["startedAt"] >= 20:
        state["playbackError"] = "Track could not be played"
        if idle is None:
            state["active"] = False
            save_state(state)
            stop_stream_proxy()
        else:
            advance_queue(state)
            idle = mpv_value("idle-active")
    current = state["song"]
    return {"ok": True, "song": current, "playing": bool(state["active"] and idle is False and mpv_value("pause") is False),
            "paused": bool(state["active"] and idle is False and mpv_value("pause") is True),
            "position": float(mpv_value("time-pos") or 0), "duration": float(mpv_value("duration") or (current or {}).get("duration") or 0),
            "index": state["index"], "queueLength": state["queueLength"], "connected": idle is not None,
            "shuffled": state.get("shuffled") is True, "radioMode": state.get("radioMode") is True,
            "playbackError": state.get("playbackError") or ""}


def control(command, argument=""):
    state = read_state()
    if command == "status":
        return status(state)
    if command == "play":
        request = json.loads(argument)
        tracks = [song(x) for x in request.get("songs", [])[:200] if isinstance(x, dict) and x.get("id")]
        index = int(request.get("index", 0))
        if not tracks or not 0 <= index < len(tracks):
            raise ValueError("No track selected")
        if request.get("shuffle") is True:
            random.SystemRandom().shuffle(tracks)
            index = 0
        save_queue(tracks)
        state.update(index=index, queueLength=len(tracks), shuffled=request.get("shuffle") is True,
                     radioMode=False)
        start_current(state)
    elif command in ("playPlaylist", "playPlaylistAt"):
        request = json.loads(argument)
        playlist_id = str(request.get("id") or "")[:500]
        if not playlist_id:
            raise ValueError("No playlist selected")
        tracks = load_playlist(playlist_id)["songs"]
        if not tracks:
            raise ValueError("Playlist is empty")
        if command == "playPlaylist":
            random.SystemRandom().shuffle(tracks)
            index = 0
            shuffled = True
        else:
            index = int(request.get("index", 0))
            if not 0 <= index < len(tracks):
                raise ValueError("Track is not in playlist")
            shuffled = False
        save_queue(tracks)
        state.update(index=index, queueLength=len(tracks), shuffled=shuffled, radioMode=False)
        start_current(state)
    elif command == "playRandom":
        tracks = random_tracks()
        if not tracks:
            raise ValueError("No songs in library")
        save_queue(tracks)
        state.update(index=0, queueLength=len(tracks), shuffled=True, radioMode=True)
        start_current(state)
    elif command == "next":
        if state["index"] + 1 >= state["queueLength"] and state.get("radioMode"):
            extend_radio_queue(state)
        if state["index"] + 1 < state["queueLength"]:
            state["index"] += 1
            start_current(state)
    elif command == "previous":
        if state["index"] > 0:
            state["index"] -= 1
            start_current(state)
        elif state["active"]:
            mpv_command(["seek", 0, "absolute"])
    elif command == "toggle":
        if state["active"]:
            mpv_command(["cycle", "pause"])
        elif state["queueLength"]:
            start_current(state)
    elif command == "stop":
        state = default_state()
        save_state(state)
        QUEUE_FILE.unlink(missing_ok=True)
        if mpv_value("idle-active") is not None:
            try:
                mpv_command(["quit"])
            except (OSError, ConnectionError):
                pass
        stop_stream_proxy()
    elif command == "seek":
        seconds = max(0, min(float(argument), 86400))
        if state["active"]:
            mpv_command(["seek", seconds, "absolute"])
    else:
        raise ValueError("Unknown command")
    return status(read_state())


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    argument = sys.argv[2] if len(sys.argv) > 2 else ""
    if command == "streamProxy":
        run_stream_proxy()
        return
    try:
        if command == "configStatus":
            result = config_status()
        elif command == "configure":
            setup = sys.stdin.buffer.readline(MAX_SETUP_BYTES + 1)
            if not setup or len(setup) > MAX_SETUP_BYTES:
                raise ValueError("Setup data is missing or too large")
            result = configure_session(json.loads(setup))
            private_dir(RUNTIME_DIR)
            with open(LOCK, "a+") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                control("stop")
        elif command in ("albums", "search", "artists", "artistsPage", "artistsRefresh", "artist",
                       "album", "playlists", "playlist", "playlistPage", "playlistRefresh", "ping"):
            result = catalog(command, argument)
        elif command in ("playAlbum", "playArtist"):
            if not argument:
                raise ValueError("No album or artist selected")
            tracks = album_songs(argument[:500]) if command == "playAlbum" else artist_songs(argument[:500])
            private_dir(RUNTIME_DIR)
            with open(LOCK, "a+") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                result = start_shuffled_tracks(tracks)
        else:
            private_dir(RUNTIME_DIR)
            with open(LOCK, "a+") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                result = control(command, argument)
    except FileNotFoundError:
        result = {"ok": False, "error": "Server session or mpv is unavailable"}
    except HTTPError as error:
        result = {"ok": False, "error": "Server HTTP " + str(error.code),
                  "retryable": error.code in (429, 502, 503, 504)}
    except (URLError, TimeoutError):
        result = {"ok": False, "error": "Server is unreachable", "retryable": True}
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as error:
        result = {"ok": False, "error": str(error)[:180]}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()

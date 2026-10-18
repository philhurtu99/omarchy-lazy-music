-- Lazy Music controls, including keyboards whose F5/F6/F7 media layer
-- sends XF86 key names. Replaces Omarchy's general media bindings.
local lazy_music_keys = {
  { "F5", "previous", "previous" },
  { "F6", "play/pause", "playPause" },
  { "F7", "next", "next" },
  { "XF86AudioPrev", "previous", "previous" },
  { "XF86AudioPlay", "play/pause", "playPause" },
  { "XF86AudioPause", "play/pause", "playPause" },
  { "XF86AudioNext", "next", "next" },
}

-- The KEYS ON/OFF button in the panel runs lazy-music-fkeys-toggle. When off,
-- these keys are left unbound so they reach the focused app (e.g. games).
local keys_flag = io.open(os.getenv("HOME") .. "/.local/state/omarchy-lazy-music/fkeys-disabled", "r")
local keys_disabled = keys_flag ~= nil
if keys_flag then keys_flag:close() end

for _, binding in ipairs(lazy_music_keys) do
  hl.unbind(binding[1])
  if not keys_disabled then
    o.bind(binding[1], "Lazy Music: " .. binding[2],
      "omarchy-shell lazymusic.player " .. binding[3],
      { locked = binding[1]:sub(1, 4) == "XF86" })
  end
end

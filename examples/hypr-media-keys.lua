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

for _, binding in ipairs(lazy_music_keys) do
  hl.unbind(binding[1])
  o.bind(binding[1], "Lazy Music: " .. binding[2],
    "omarchy-shell lazymusic.player " .. binding[3],
    { locked = binding[1]:sub(1, 4) == "XF86" })
end

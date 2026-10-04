import QtQuick
import qs.Ui

BarIconButton {
  id: root
  property var musicService: null

  tooltipText: musicService && musicService.song && musicService.song.title
    ? musicService.song.title + (musicService.song.artist ? " · " + musicService.song.artist : "")
    : "Lazy Music"

  // WidgetButton sends a snapshot to the bar on mouse enter. Send the new
  // text again when the song changes while the pointer stays on the icon.
  onTooltipTextChanged: {
    if (tooltipHovered && bar) bar.showTooltip(root, tooltipText)
  }
}

-- Paste into ~/.config/hypr/hyprland.lua to make the icon preview a floating, fully opaque window.
-- (tag/opacity: Omarchy makes windows slightly transparent by default, which lets the desktop show through.)
o.window({ title = "^iOS icon preview$" }, {
  float = true,
  pin = true,
  no_shadow = true,
  tag = "-default-opacity",
  opacity = "1 1",
  move = { "(monitor_w/2-380)", "(monitor_h/2-240)" },
})

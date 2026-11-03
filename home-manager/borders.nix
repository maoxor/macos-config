# Focused-window border: JankyBorders (2026-11-03). OmniWM's own border was tried first and judged poor by the user;
# JankyBorders reads each window's real corner radius (SkyLight), so the border follows macOS 26's rounded corners.
# Colour: a fixed, strong violet (#B026FF), the user's choice (2026-11-03); it does not follow the wallpaper accent.
# raycast-dim.lua reads this colour and width from bordersrc to ring Raycast's panel the same way.
# Only the focused window gets a border (inactive_color fully transparent). No Accessibility needed: without it
# JankyBorders takes the front window from SkyLight. Rollback: remove this file from home.nix imports and switch.
{ ... }:
{
  services.jankyborders = {
    enable = true;
    settings = {
      style = "round";
      width = "6.0";
      hidpi = "on";
      active_color = "0xffb026ff";
      inactive_color = "0x00000000";
    };
  };
}

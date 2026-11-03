# Focused-window border: JankyBorders (2026-11-03). OmniWM's own border was tried first and judged poor by the user;
# JankyBorders reads each window's real corner radius (SkyLight), so the border follows macOS 26's rounded corners.
# Colour = palette accent (base0D); theme-apply.sh recolours the running instance when the wallpaper changes.
# Only the focused window gets a border (inactive_color fully transparent). No Accessibility needed: without it
# JankyBorders takes the front window from SkyLight. Rollback: remove this file from home.nix imports and switch.
{ ... }:
let
  palette = import ./palette.nix;
in {
  services.jankyborders = {
    enable = true;
    settings = {
      style = "round";
      width = "4.0";
      hidpi = "on";
      active_color = "0xff${palette.base0D}";
      inactive_color = "0x00000000";
    };
  };
}

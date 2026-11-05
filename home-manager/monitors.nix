# btop, styled (2026-11-05): a theme made from the wallpaper palette (follows the theme like Ghostty), transparent
# background so Ghostty's glass shows through, rounded corners, braille graphs, vim keys. btop itself is a Homebrew
# formula (homebrew/Brewfile); opened by Raycast "btop" (scripts/geek-monitor).
{ ... }:
let
  p = import ./palette.nix;
  c = hex: "#${hex}";
in {
  xdg.configFile."btop/themes/wallpaper.theme".text = ''
    theme[main_bg]=""
    theme[main_fg]="${c p.base05}"
    theme[title]="${c p.base06}"
    theme[hi_fg]="${c p.base0D}"
    theme[selected_bg]="${c p.base02}"
    theme[selected_fg]="${c p.base06}"
    theme[inactive_fg]="${c p.base03}"
    theme[graph_text]="${c p.base04}"
    theme[meter_bg]="${c p.base02}"
    theme[proc_misc]="${c p.base0D}"
    theme[cpu_box]="${c p.base0D}"
    theme[mem_box]="${c p.base0E}"
    theme[net_box]="${c p.base0C}"
    theme[proc_box]="${c p.base09}"
    theme[div_line]="${c p.base02}"
    theme[temp_start]="${c p.base0B}"
    theme[temp_mid]="${c p.base0A}"
    theme[temp_end]="${c p.base08}"
    theme[cpu_start]="${c p.base0B}"
    theme[cpu_mid]="${c p.base0D}"
    theme[cpu_end]="${c p.base08}"
    theme[free_start]="${c p.base0B}"
    theme[free_mid]=""
    theme[free_end]="${c p.base0C}"
    theme[cached_start]="${c p.base0C}"
    theme[cached_mid]=""
    theme[cached_end]="${c p.base0D}"
    theme[available_start]="${c p.base0A}"
    theme[available_mid]=""
    theme[available_end]="${c p.base09}"
    theme[used_start]="${c p.base0E}"
    theme[used_mid]=""
    theme[used_end]="${c p.base08}"
    theme[download_start]="${c p.base0C}"
    theme[download_mid]="${c p.base0D}"
    theme[download_end]="${c p.base0E}"
    theme[upload_start]="${c p.base0B}"
    theme[upload_mid]="${c p.base0A}"
    theme[upload_end]="${c p.base09}"
    theme[process_start]="${c p.base0B}"
    theme[process_mid]="${c p.base0D}"
    theme[process_end]="${c p.base08}"
  '';

  xdg.configFile."btop/btop.conf".text = ''
    color_theme = "wallpaper"
    theme_background = False
    truecolor = True
    rounded_corners = True
    graph_symbol = "braille"
    vim_keys = True
    update_ms = 1000
    shown_boxes = "cpu mem net proc"
    proc_sorting = "cpu lazy"
    proc_gradient = True
    proc_per_core = False
    proc_tree = False
    cpu_graph_upper = "total"
    show_cpu_freq = True
    check_temp = True
    show_coretemp = True
    temp_scale = "celsius"
    show_battery = True
    mem_graphs = True
    show_disks = True
    net_auto = True
    clock_format = "%H:%M"
    base_10_sizes = False
  '';
}

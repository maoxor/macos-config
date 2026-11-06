# macOS settings of this setup, declared once and applied by Home Manager (`defaults write` at activation,
# user level, no sudo). scripts/macos-defaults.sh compares them with the live Mac (verify.sh, doctor.sh).
# Values were read from the reference Mac. Not here, on purpose: the accent/highlight colours (owned by
# scripts/theme-apply.sh), the display resolution, the keyboard input source and the wallpaper
# (manual steps: README "Manual settings"), and anything personal (accounts, Dock apps, recent items).
{ config, lib, pkgs, ... }:
let
  profile = import ./profile.nix;
  # macOS shortcuts turned off so their keys stay free for OmniWM, Raycast and Neru
  # (ids of ~/Library/Preferences/com.apple.symbolichotkeys.plist):
  #   15-26 Mission Control "switch to desktop N" & screenshots chords · 60/61 input source switching
  #   32-35 Mission Control / application windows on Control(+Shift)+Up/Down (→ OmniWM focus/move)
  #   64 Spotlight (Cmd+Space → Raycast) · 79-82 move left/right a space (Control+arrows → OmniWM)
  #   118 switch to desktop 1 (Control+1 → OmniWM) · 160 Launchpad · 163/164 Notification Center / Focus
  disabledHotkeys = [ 15 16 17 18 19 20 21 22 23 24 25 26 32 33 34 35 60 61 64 79 80 81 82 118 160 163 164 ];
  trackpad = {
    Clicking = true;                        # tap to click
    Dragging = true;                        # tap to drag (double tap)
    DragLock = false;
    TrackpadThreeFingerDrag = false;
    TrackpadThreeFingerHorizSwipeGesture = 0;   # 3 fingers belong to OmniWM
    TrackpadThreeFingerVertSwipeGesture = 0;
    TrackpadFourFingerHorizSwipeGesture = 0;    # 4 fingers up = OmniWM Overview
    TrackpadFourFingerVertSwipeGesture = 0;
    TrackpadThreeFingerTapGesture = 2;          # look up
    TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
    FirstClickThreshold = 2;
    SecondClickThreshold = 2;
    ActuateDetents = false;
    ForceSuppressed = true;
  };
in {
  # Read by tools/hammerspoon/config/function-keys.lua: F3/F4 are blocked only when this file exists.
  xdg.configFile."macos-config/lock-down" = lib.mkIf profile.lockDown { text = ""; };
  targets.darwin.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      AppleShowAllExtensions = true;
      _HIHideMenuBar = true;                      # menu bar auto-hides
      AppleMenuBarVisibleInFullscreen = false;    # no macOS menu bar in full screen either (SketchyBar replaces it)
      AppleMiniaturizeOnDoubleClick = false;
      AppleEnableSwipeNavigateWithScrolls = true;
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      KB_DoubleQuoteOption = "« abc »";           # French typographic quotes
      KB_SingleQuoteOption = "‘abc’";
      "com.apple.swipescrolldirection" = true;    # natural scrolling
      "com.apple.trackpad.scaling" = 3.0;         # tracking speed
      "com.apple.trackpad.scrolling" = 0.3125;    # scrolling speed
      "com.apple.trackpad.forceClick" = false;
      "com.apple.mouse.doubleClickThreshold" = 0.15;
      "com.apple.springing.enabled" = true;
      "com.apple.springing.delay" = 0.0035511255264282227;
      "com.apple.sound.uiaudio.enabled" = false;  # no UI sound effects
      "com.apple.sound.beep.feedback" = 0;
    };
    # fn/🌐 key does nothing (default: opens the Emoji & Symbols picker). 0 nothing, 1 input source, 2 emoji, 3 dictation.
    "com.apple.HIToolbox".AppleFnUsageType = 0;
    "com.apple.AppleMultitouchTrackpad" = trackpad;
    # External Magic Trackpad: same gestures (the click/force keys only exist for the built-in one).
    "com.apple.driver.AppleBluetoothMultitouch.trackpad" = builtins.removeAttrs trackpad
      [ "ActuateDetents" "ForceSuppressed" "FirstClickThreshold" "SecondClickThreshold" ];
    "com.apple.dock" = {
      autohide = true;
      tilesize = 43;
      orientation = "left";
      show-recents = false;
      magnification = false;
      mru-spaces = false;                         # never reorder Spaces
      wvous-br-corner = 14;                       # bottom-right hot corner: Quick Note
      showMissionControlGestureEnabled = false;   # otherwise Mission Control opens behind OmniWM's Overview
      showAppExposeGestureEnabled = false;
    } // lib.optionalAttrs profile.lockDown {
      autohide-delay = 1000.0;                    # the Dock (left edge) never shows
    };
    "com.apple.finder" = {
      ShowPathbar = true;
      ShowStatusBar = true;
      FXPreferredViewStyle = "icnv";
    };
    "com.apple.WindowManager" = {
      GloballyEnabled = false;                    # Stage Manager off (empty screens on workspace switch)
      AutoHide = false;
      HideDesktop = true;
      StandardHideWidgets = true;
      StageManagerHideWidgets = true;
    };
    "com.apple.controlcenter".AutoHideMenuBarOption = 0;
    "com.apple.menuextra.clock" = { ShowDayOfWeek = true; ShowAMPM = true; };
    "com.barut.OmniWM" = {                        # options added by tools/omniwm/patches
      OverviewHideWorkspaceLabels = true;
      OverviewHideSearchBar = true;
      WorkspaceSwipeSensitivity = 1.8;            # vertical swipe: earlier trigger, less travel per workspace
      SuppressSecureInputExplanation = true;      # no panel after 10 s of Secure Input (it stays on)
    };
  };
  # AirPlay receiver off: it listened on ports 5000/7000 for the whole network (public Wi-Fi).
  targets.darwin.currentHostDefaults."com.apple.controlcenter".AirplayRecieverEnabled = false;
  targets.darwin.currentHostDefaults.NSGlobalDomain = {
    "com.apple.trackpad.threeFingerHorizSwipeGesture" = 0;
    "com.apple.trackpad.threeFingerVertSwipeGesture" = 0;
    "com.apple.trackpad.fourFingerVertSwipeGesture" = 0;
  };

  # Symbolic hotkeys are nested plist dicts that `defaults write` would replace wholesale: set only
  # each `enabled` flag. Then make running apps re-read the settings, and restart the Dock/Finder only
  # when the declared settings changed since the last activation.
  home.activation.macosSettings = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] (
    let
      stamp = builtins.hashString "sha256" (builtins.toJSON {
        d = config.targets.darwin.defaults; h = config.targets.darwin.currentHostDefaults; k = disabledHotkeys; });
      plist = "$HOME/Library/Preferences/com.apple.symbolichotkeys.plist";
    in ''
      for n in ${lib.concatMapStringsSep " " toString disabledHotkeys}; do
        if ! /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:$n:enabled false" "${plist}" 2>/dev/null; then
          /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$n dict" -c "Add :AppleSymbolicHotKeys:$n:enabled bool false" "${plist}" >/dev/null 2>&1 || true
        fi
      done
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
      s="$HOME/.local/state/macos-config/defaults.stamp"
      if [ "$(cat "$s" 2>/dev/null)" != "${stamp}" ]; then
        run /usr/bin/killall Dock Finder SystemUIServer 2>/dev/null || true
        mkdir -p "$(dirname "$s")"; echo "${stamp}" > "$s"
      fi
    '');
}

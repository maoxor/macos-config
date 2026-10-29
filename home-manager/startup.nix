# Startup at login: ONE mechanism per tool (LaunchAgents managed here).
# Raycast keeps its own login item (registered by the app): do not duplicate it here.
# `open -a` never starts a second instance of an app that is already running.
{ config, pkgs, ... }:
let
  identity = import ./identity.nix;
  logs = "${config.home.homeDirectory}/Library/Logs/macos-config";
  openApp = name: {
    enable = true;
    config = {
      ProgramArguments = [ "/usr/bin/open" "-g" "-a" name ];
      RunAtLoad = true;
      ProcessType = "Interactive";
    };
  };
  # "Copy then truncate" rotation: launchd/Neru keep the file open (O_APPEND checked), so it is not moved
  # (Neru would keep writing into the archive). The archive keeps at most the last 1 MB; storage stays
  # bounded to ~1 MB of archive plus 10 minutes of growth, per log.
  logRotate = pkgs.writeShellScript "macos-config-logrotate" ''
    umask 077
    for f in "${logs}"/*.log; do
      [ -f "$f" ] || continue
      /bin/chmod 600 "$f"
      if [ "$(/usr/bin/stat -f %z "$f")" -gt 1048576 ]; then
        /usr/bin/tail -c 1048576 "$f" > "$f.1" && : > "$f"
        /bin/chmod 600 "$f.1"
      fi
    done
    exit 0
  '';
in {
  launchd.agents = {
    # Window manager: OmniWM (AeroSpace and native tiling were tried and abandoned).
    omniwm = openApp "OmniWM";
    hammerspoon = openApp "Hammerspoon";
    stats = openApp "Stats";
    # Work apps reopened at login (Ghostty restores its windows, Safari its last session), then
    # apply-window-rules.sh puts every restored window back on its rule's workspace.
    ghostty = openApp "Ghostty";
    safari = openApp "Safari";
    discord = openApp "Discord";
    # Every minute: open Claude Code sessions and their workspace, for Cmd+F5 (restore-session.py) after a crash.
    # Playwright test pages open behind the user's windows (scripts/playwright-background-pages.py); hourly,
    # since projects reinstall playwright-core.
    playwright-background-pages = {
      enable = true;
      config = {
        ProgramArguments = [ "/usr/bin/python3" "-I" "${identity.repoDir}/scripts/playwright-background-pages.py" ];
        RunAtLoad = true;
        StartInterval = 3600;
        ProcessType = "Background";
      };
    };
    session-snapshot = {
      enable = true;
      config = {
        ProgramArguments = [ "/usr/bin/python3" "${identity.repoDir}/scripts/session-snapshot.py" ];
        RunAtLoad = true;
        StartInterval = 60;
        ProcessType = "Background";
      };
    };
    window-rules = {
      enable = true;
      config = {
        ProgramArguments = [ "/bin/bash" "${identity.repoDir}/scripts/apply-window-rules.sh" ];
        RunAtLoad = true;
        ProcessType = "Background";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/apply-window-rules.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/apply-window-rules.log";
      };
    };
    neru = {
      enable = true;
      config = {
        # Binary launched DIRECTLY: through an intermediate script Neru resets its own Accessibility
        # permission (observed once). No bash launcher here.
        ProgramArguments = [ "/Applications/Neru.app/Contents/MacOS/neru" "launch" ];
        RunAtLoad = true;
        # Restarted only after an abnormal exit; SIGTERM / Quit (exit 0) is not restarted.
        KeepAlive = { SuccessfulExit = false; };
        # Panne persistante : au plus 2 relances/min (launchd n'a pas de plafond de relances) ;
        # stop for good: launchctl bootout gui/$(id -u)/org.nix-community.home.neru
        ThrottleInterval = 30;
        ProcessType = "Interactive";
        StandardOutPath = "${logs}/neru.log";
        StandardErrorPath = "${logs}/neru.log";
      };
    };
    # Theme: regenerated when macOS changes the wallpaper (watches the wallpaper index); no-op if the image is unchanged.
    theme-auto = {
      enable = true;
      config = {
        ProgramArguments = [ "/bin/bash" "${identity.repoDir}/scripts/theme-auto.sh" ];
        WatchPaths = [ "${config.home.homeDirectory}/Library/Application Support/com.apple.wallpaper/Store/Index.plist" ];
        ThrottleInterval = 20;
        ProcessType = "Background";
      };
    };
    # Every minute: memory, CPU and GPU per process, one week kept (scripts/perf-journal.py; `report` summarises).
    perf-journal = {
      enable = true;
      config = {
        ProgramArguments = [ "/usr/bin/python3" "-I" "${identity.repoDir}/scripts/perf-journal.py" ];
        RunAtLoad = true;
        StartInterval = 60;
        ProcessType = "Background";
        StandardErrorPath = "${logs}/perf-journal.log";
      };
    };
    logrotate = {
      enable = true;
      config = {
        ProgramArguments = [ "${logRotate}" ];
        RunAtLoad = true;
        StartInterval = 600; # every 10 min (negligible cost: one stat per log)
        ProcessType = "Background";
      };
    };
  };
  home.file."Library/Logs/macos-config/.keep".text = "";
  # omniwmctl (OmniWM's CLI) lives inside the locally built app: expose it on PATH (~/.local/bin).
  home.file.".local/bin/omniwmctl".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/OmniWM.app/Contents/MacOS/omniwmctl";
  # jobgate: heavy jobs wait for real free memory and pause only while the Mac thrashes (docs/performance.md).
  home.file.".local/bin/jobgate".source =
    config.lib.file.mkOutOfStoreSymlink "${identity.repoDir}/scripts/jobgate.py";
}

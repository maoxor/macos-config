{ config, lib, ... }:
let profile = import ./profile.nix; identity = import ./identity.nix;
in lib.mkIf profile.enableShell {
  programs.zsh.enable = true;
  programs.zsh.shellAliases.ll = "ls -lah";
  # Second Claude Code account: separate config dir (login, settings); plain `claude` keeps ~/.claude.
  # env -u: a Ghostty started from a Claude session leaks its child marker, which turns transcript saving off.
  # BROWSER: its links (artifacts, login) open in Chrome, signed in to the second account; `claude` keeps Safari.
  programs.zsh.shellAliases.claude2 = "env -u CLAUDECODE -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR=$HOME/.claude-2 BROWSER=$HOME/.local/bin/open-in-chrome claude";
  # claude-rm: delete closed Claude Code sessions (both accounts); /delete runs it from inside Claude Code.
  home.file.".local/bin/claude-rm".source = config.lib.file.mkOutOfStoreSymlink "${identity.repoDir}/scripts/claude-sessions.py";
  home.file.".claude/skills/delete/SKILL.md".source = ../tools/claude-code/skills/delete/SKILL.md;
  home.file.".claude-2/skills/delete/SKILL.md".source = ../tools/claude-code/skills/delete/SKILL.md;
  home.file.".claude/skills/apres/SKILL.md".source = ../tools/claude-code/skills/apres/SKILL.md;
  home.file.".claude-2/skills/apres/SKILL.md".source = ../tools/claude-code/skills/apres/SKILL.md;
  home.file.".local/bin/open-in-chrome" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Hands the URL to the running Chrome (or starts it) in its default profile.
      exec "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --profile-directory=Default "$@" >/dev/null 2>&1 &
    '';
  };
  # Nix from our own ~/.zshenv: every macOS upgrade rewrites /etc/zshrc and drops the installer's hook (27.2.1 on
  # 2026-11-12: `sketchybar`, `home-manager`… no longer on PATH). nix-daemon.sh guards against a second sourcing.
  programs.zsh.envExtra = ''
    [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ] && . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  '';
  # Migrated from the old ~/.zprofile (Homebrew) and ~/.zshrc (~/.local/bin: Claude Code).
  programs.zsh.profileExtra = ''
    eval "$(/opt/homebrew/bin/brew shellenv zsh)"
  '';
  home.sessionPath = [ "$HOME/.local/bin" ];
  programs.fzf = {
    enable = true;
    # Atuin owns Ctrl-R when enabled; fzf remains available as a CLI.
    enableZshIntegration = !profile.enableAtuin;
  };
  programs.zoxide = { enable = true; enableZshIntegration = true; };
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = false;
      character.success_symbol = "[❯](bold blue)";
      character.error_symbol = "[❯](bold red)";
    };
  };
  programs.atuin = lib.mkIf profile.enableAtuin {
    enable = true;
    enableZshIntegration = true;
    flags = [ "--disable-up-arrow" ];
    settings = { auto_sync = false; update_check = false; };
  };
  programs.direnv = lib.mkIf profile.enableDev {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}

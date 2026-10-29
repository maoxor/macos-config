{ config, pkgs, lib, ... }:
let
  identity = import ./identity.nix;
  profile = import ./profile.nix;
in {
  imports = [ ./shell.nix ./startup.nix ./theme.nix ./macos.nix ];
  assertions = [
    { assertion = identity.homeDirectory == "/Users/${identity.username}";
      message = "Check the home directory; adapt this assertion if the account uses another path."; }
    { assertion = (!profile.enableAtuin && !profile.enableDev) || profile.enableShell;
      message = "Atuin and direnv require enableShell = true here."; }
  ];
  home.username = identity.username;
  home.homeDirectory = identity.homeDirectory;
  # Home Manager compatibility version: do not bump for an ordinary update.
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;
  home.packages = with pkgs; [ ripgrep fzf zoxide jq starship fd gh delta ast-grep gitleaks ]  # gitleaks: pre-commit hooks of the projects
    # yazi, lazygit, bat, btop: programs.* in theme.nix (themed by Stylix)
    ++ lib.optionals profile.enableRestic [ restic ]
    ++ lib.optionals profile.enableSync [ syncthing ];
  # No restic or syncthing service is enabled by this template.
}

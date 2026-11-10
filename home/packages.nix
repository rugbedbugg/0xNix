{ pkgs, pkgs-unstable, ... }:
{
  # Standalone tools picked by hand — nothing else in the config depends on
  # them. Packages a feature needs (grim/slurp for screenshots, playerctl for
  # media keys, fonts) stay next to that feature instead, so removing the
  # feature removes its dependencies too.
  #
  # Stable by default. Anything that should track upstream more closely goes
  # in the unstable list. Bump that with `nix flake update nixpkgs-unstable`
  # and rebuild.
  #
  # Qt apps come from the stable set, never from the unstable list or
  # apps.nix. The Qt theme only applies to apps built against the
  # same Qt as its plugin, and the unstable set usually carries a newer one.
  # checks/qt-theme.nix fails when a second Qt version appears.
  #
  # Packages that change often are in apps.nix.
  home.packages =
    (with pkgs; [
      ripgrep
      fd
      jq
      tree
      genact
      unzip
      openssl
      libreoffice-fresh
      lorien
      kdePackages.marknote
      lazygit
    ])
    ++ (with pkgs-unstable; [
      fastfetch
      awscli2
      # `aws ssm start-session` hands the session to this binary, so it
      # updates together with the CLI.
      ssm-session-manager-plugin
    ]);
}

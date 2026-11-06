{ pkgs, pkgs-unstable, ... }:
{
  # Standalone tools picked by hand — nothing else in the config depends on
  # them. Packages a feature needs (grim/slurp for screenshots, playerctl for
  # media keys, fonts) stay next to that feature instead, so removing the
  # feature removes its dependencies too.
  #
  # Stable by default; anything that should track upstream closely goes in
  # the unstable list. Bump that with
  # `nix flake update nixpkgs-unstable`.
  #
  # Qt apps come from the stable set, never from the unstable list or the
  # profile packages. The Qt theme only applies to apps built against the
  # same Qt as its plugin, and the unstable set usually carries a newer one.
  # checks/qt-theme.nix fails when a second Qt version appears.
  #
  # Frequently updated packages are not here. They install into the user
  # profile from the flake's `agents` and `apps` packages so they can update
  # without a rebuild.
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
    ]);
}

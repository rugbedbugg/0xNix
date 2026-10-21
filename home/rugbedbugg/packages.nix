{ pkgs, pkgs-unstable, ... }:
{
  # Standalone tools picked by hand — nothing else in the config depends on
  # them. Packages a feature needs (grim/slurp for screenshots, playerctl for
  # media keys, fonts) stay next to that feature instead, so removing the
  # feature removes its dependencies too.
  #
  # Stable by default; anything that should track upstream closely goes in
  # the unstable list. Bump that with
  # `nix flake lock --update-input nixpkgs-unstable`.
  home.packages =
    (with pkgs; [
      ripgrep
      fd
      jq
      htop
      tree
      genact
    ])
    ++ (with pkgs-unstable; [
      fastfetch
      claude-code
      codex
      opencode
      antigravity-cli
      awscli2
      vesktop
    ]);
}

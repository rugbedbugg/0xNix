{ pkgs, ... }:
{
  imports = [
    ./shell.nix
    ./hyprland.nix
    ./crt.nix
    ./desktop-tools.nix
    ./swaync.nix
    ./waybar.nix
    ./waybar-side-bars.nix
    ./waybar-bottom.nix
    ./floating.nix
    ./keybinds.nix
    ./media.nix
    ./mpv.nix
    ./files.nix
    ./wallpaper.nix
    ./minimap.nix
    ./gtk.nix
    ./qt.nix
    ./zathura.nix
    ./zapfast.nix
    ./nvim.nix
    ./vim.nix
    ./tmux.nix
  ];

  home.pointerCursor = {
    enable = true;
    package = pkgs.vanilla-dmz;
    name = "Vanilla-DMZ";
    size = 24;
    x11.enable = true;
    gtk.enable = true;
    hyprcursor.enable = true;
  };
  xdg.enable = true;
  fonts.fontconfig.enable = true;
}

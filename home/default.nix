{ config, 
  pkgs,
  pkgs-unstable,
  ...
}:
{
  imports = [
    ./shell.nix
    ./hyprland.nix
    ./desktop-tools.nix
    ./keybinds.nix
    ./packages.nix
    ./media.nix
    ./files.nix
    ./wallpaper.nix
    ./git.nix
  ];

  home = {
    pointerCursor = {
      enable = true;
      package = pkgs.vanilla-dmz;
      name = "Vanilla-DMZ";
      size = 24;
      x11.enable = true;
      gtk.enable = true;
      hyprcursor.enable = true;
    };
  };
  xdg.enable = true;
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
  };
  fonts.fontconfig.enable = true;
  programs = {
    home-manager.enable = true;
    vim = {
      enable = true;
      defaultEditor = true;
      # Sourced from nixpkgs-unstable — vim is in the daily-driver,
      # frequently-updated category alongside the unstable list in
      # packages.nix.
      packageConfigurable = pkgs-unstable.vim-full;
      # vim/oxide.vim is the rice's colour scheme. It leaves the background
      # transparent, so the terminal's shows through, and its colours are
      # 24-bit: foot supports that, and the t_8f/t_8b sequences make vim
      # emit it whatever $TERM's terminfo says.
      extraConfig = ''
        let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
        let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
        set termguicolors
        syntax on
        colorscheme oxide
      '';
    };
  };
  home.file.".vim/colors/oxide.vim".source = ./vim/oxide.vim;
}

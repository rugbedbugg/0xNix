{
  pkgs,
  host,
  home,
  minimal,
  themed,
}:
let
  plain = minimal.config.home-manager.users.example;
  applications = themed.config.home-manager.users.example;
in
{
  rice-scope =
    assert !plain.programs.git.enable;
    assert !plain.programs.direnv.enable;
    assert !plain.programs.neovim.enable;
    assert !plain.programs.vim.enable;
    assert !plain.programs.lf.enable;
    assert !plain.programs.zathura.enable;
    assert !plain.programs.tmux.enable;
    assert !plain.programs.rmpc.enable;
    assert !plain.programs.fastfetch.enable;
    assert !plain.programs.btop.enable;
    assert !plain.programs.mpv.enable;
    assert !plain.services.mpd.enable;
    assert !(plain.xdg.configFile ? "nvim/colors/0xNix.lua");
    assert !(plain.home.file ? ".vim/colors/0xNix.vim");
    assert !(plain.xdg.configFile ? "lf/colors");
    assert !(plain.xdg.configFile ? "mpv/mpv.conf");
    assert !(plain.xdg.configFile ? "zapfast/themes/0xNix.json");
    pkgs.writeText "rice-scope" "Desktop rice without general applications\n";
  example-home = home.home.activationPackage;
  themed-applications = applications.home.activationPackage;
  neovim-theme = pkgs.runCommand "neovim-theme-check" { } ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_CACHE_HOME="$HOME/.cache"
    mkdir -p "$XDG_CONFIG_HOME/nvim/colors"
    ln -s ${applications.xdg.configFile."nvim/init.lua".source} "$XDG_CONFIG_HOME/nvim/init.lua"
    ln -s ${
      applications.xdg.configFile."nvim/colors/0xNix.lua".source
    } "$XDG_CONFIG_HOME/nvim/colors/0xNix.lua"
    ${applications.programs.neovim.finalPackage}/bin/nvim --headless \
      -c 'lua assert(vim.v.errmsg == "", vim.v.errmsg); assert(vim.g.colors_name == "0xNix")' \
      -c 'qa!'
    touch "$out"
  '';
  qt-theme = import ./qt-theme.nix {
    inherit pkgs home;
    system = host.config.system.build.toplevel;
  };
  python-scripts =
    pkgs.runCommand "python-scripts-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.ruff
        ];
      }
      ''
        files="${../home/minimap.py} ${../home/wallpaper-switcher.py}"
        export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
        python -m py_compile $files
        ruff check --no-cache $files
        touch "$out"
      '';
  desktop-config =
    pkgs.runCommand "desktop-config-check"
      {
        nativeBuildInputs = [
          pkgs.lua5_5
          pkgs.python3
          pkgs.hyprland
        ];
      }
      ''
        luac -p ${home.xdg.configFile."hypr/hyprland.lua".source}
        python -m json.tool ${home.xdg.configFile."waybar/config".source} >/dev/null
        export XDG_RUNTIME_DIR="$TMPDIR/runtime"
        export XDG_CACHE_HOME="$TMPDIR/cache"
        export XDG_CONFIG_HOME="$TMPDIR/config"
        mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
        chmod 700 "$XDG_RUNTIME_DIR"
        Hyprland --verify-config --config ${home.xdg.configFile."hypr/hyprland.lua".source}
        touch "$out"
      '';
}

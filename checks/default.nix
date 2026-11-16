{
  pkgs,
  host,
  home,
}:
{
  example-home = home.home.activationPackage;
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

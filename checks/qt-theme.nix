# Loads the Qt theme under a real Qt and fails when it is not applied.
#
# Qt skips a platform plugin it cannot use without an error, and every Qt
# app then falls back to the default light style. This check runs Qt's own
# diagnostic tool with the generated configuration and the Home Manager
# profile, so that failure shows up in `nix flake check` instead of on
# screen. It catches:
# - a change to qt.nix that drops the theme name, the stylesheet or the font
# - an upstream change that stops the qt6ct plugin or style from loading
# - a plugin directory that moves away from the path UWSM hands to apps
# - a session variable missing from uwsm/env, which only apps started from
#   Hyprland read
# - a kdeglobals without all of its colour groups
# - a second Qt version anywhere in the system, Home Manager included
#
# The plugin only works with the Qt it was built against. The tool and the
# plugin here come from one nixpkgs, so the version test is what proves the
# apps match them: it requires one Qt minor version in the whole system
# closure. A Qt app taken from the unstable package set would add a second
# one. The unstable profile packages in flake.nix are outside the system
# closure. Their build fails on its own when Qt gets into them.
{
  pkgs,
  home,
  system,
}:
let
  qtct = home.qt.platformTheme;
  fonts = pkgs.makeFontsConf { fontDirectories = [ pkgs.uni-vga ]; };
  closure = pkgs.closureInfo { rootPaths = [ system ]; };
in
pkgs.runCommand "qt-theme-check"
  {
    nativeBuildInputs = [ pkgs.qt6.qttools ];
  }
  ''
    fail() {
      echo "qt-theme-check: $1" >&2
      [ -f report ] && cat report >&2
      exit 1
    }

    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME/qt6ct" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    ln -s ${home.xdg.configFile."qt6ct/qt6ct.conf".source} "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"

    export QT_QPA_PLATFORM=offscreen
    export QT_QPA_PLATFORMTHEME=${qtct.name}
    export QT_PLUGIN_PATH=${home.home.path}/lib/qt-6/plugins
    export FONTCONFIG_FILE=${fonts}

    qtdiag6 > report 2>&1 || true
    grep -q 'Styles requested *: qt6ct-style' report \
      || fail "the qt6ct style was not applied, so the plugin did not load"
    grep -q 'System font *: "VGA"' report \
      || fail "the font from qt6ct.conf was not applied"

    env=${home.xdg.configFile."uwsm/env".source}
    grep -qx 'export QT_QPA_PLATFORMTHEME=${qtct.name}' "$env" \
      || fail "uwsm/env does not set QT_QPA_PLATFORMTHEME"
    grep -qx 'export QT_PLUGIN_PATH=${home.home.profileDirectory}/lib/qt-6/plugins' "$env" \
      || fail "uwsm/env does not set QT_PLUGIN_PATH"

    versions=$(grep -oE 'qtbase-6\.[0-9]+' ${closure}/store-paths | sort -u)
    [ "$(printf '%s\n' "$versions" | wc -l)" = 1 ] \
      || fail "the system holds more than one Qt version: $(echo $versions). Keep Qt apps in the stable package set"

    groups=$(grep -c '^\[Colors:' ${home.xdg.configFile."kdeglobals".source})
    [ "$groups" = 7 ] || fail "kdeglobals has $groups colour groups, expected 7"

    touch "$out"
  ''

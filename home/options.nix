{ lib, pkgs, ... }:
let
  text =
    description:
    lib.mkOption {
      type = lib.types.nonEmptyStr;
      inherit description;
    };
  identifier = lib.mkOption {
    type = lib.types.strMatching "[A-Za-z0-9_.-]+";
    description = "Exact window class.";
  };
  workspace = lib.mkOption {
    type = lib.types.strMatching "[A-Za-z0-9_-]+";
    description = "Special workspace name without its prefix.";
  };
in
{
  options.desktop = {
    launches = lib.mkOption {
      description = "Tiled and floating launch bindings. Commands are raw shell code, wrapped in UWSM once.";
      default = [
        {
          key = "T";
          description = "Terminal";
          command = "${pkgs.foot}/bin/foot";
          classes = [ "^foot$" ];
        }
      ];
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            key = lib.mkOption {
              type = lib.types.strMatching "[A-Za-z][A-Za-z0-9_]*";
              description = "Single key after SUPER, or SUPER + ALT for a floating launch.";
            };
            description = text "Cheatsheet label.";
            command = text "Raw shell launch command.";
            classes = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Lua class patterns used by the floating launcher.";
            };
          };
        }
      );
    };
    overlays = lib.mkOption {
      description = "Special-workspace toggles. Commands are raw shell code, wrapped in UWSM once.";
      default = [
        {
          key = "SUPER + S";
          description = "Scratch terminal";
          class = "general-special";
          workspace = "general";
          command = "${pkgs.foot}/bin/foot --app-id=general-special";
        }
      ];
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            key = lib.mkOption {
              type = lib.types.strMatching "((CTRL|SUPER|ALT|SHIFT) \\+ )*[A-Za-z][A-Za-z0-9_]*";
              description = "Complete toggle binding using CTRL, SUPER, ALT and SHIFT modifiers.";
            };
            description = text "Cheatsheet label.";
            command = text "Raw shell launch command.";
            class = identifier;
            inherit workspace;
          };
        }
      );
    };
    overlayWindows = lib.mkOption {
      description = "Additional windows with the overlay frame and reload geometry.";
      default = [ ];
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            class = identifier;
            workspace = lib.mkOption {
              type = lib.types.nullOr (lib.types.strMatching "[A-Za-z0-9_-]+");
              default = null;
              description = "Optional special workspace assignment.";
            };
            silent = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Assign the workspace without taking focus.";
            };
          };
        }
      );
    };
    wallpaperHooks = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Executables called with the selected wallpaper path.";
    };
    applicationThemes.zapfast.enable = lib.mkEnableOption "ZapFast theme files";
    keyNames = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Display names for hardware-specific keys in the cheatsheet.";
    };
    screen = lib.mkOption {
      description = "Logical dimensions used by the desktop layout.";
      default = { };
      type = lib.types.submodule {
        options = {
          width = lib.mkOption {
            type = lib.types.ints.positive;
            default = 1920;
          };
          height = lib.mkOption {
            type = lib.types.ints.positive;
            default = 1080;
          };
        };
      };
    };
    bottomBar = {
      modulesCenter = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Modules in the center of the bottom bar.";
      };
      modules = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Additional module definitions for the bottom bar.";
      };
      modulesRight = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional modules before the right-side controls.";
      };
      style = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additional styles for the bottom bar.";
      };
    };
  };
}

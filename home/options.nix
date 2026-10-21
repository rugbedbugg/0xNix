{ lib, ... }:
{
  options.desktop = {
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

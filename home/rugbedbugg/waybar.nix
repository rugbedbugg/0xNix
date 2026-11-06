# The main bar. Its custom modules are the scripts in status-scripts.nix.
{
  osConfig,
  pkgs,
  palette,
  ...
}:
let
  gtkTty = import ./gtk-tty.nix { inherit pkgs palette; };
  pavucontrol = gtkTty.wrap pkgs.pavucontrol "pavucontrol";
  scripts = import ./status-scripts.nix { inherit pkgs osConfig palette; };
  tooltipStyle = import ./tooltip-style.nix { inherit palette; };
in
{
  programs.waybar = {
    enable = true;
    systemd = {
      enable = true;
      targets = [ "graphical-session.target" ];
    };
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 32;
      modules-left = [
        "custom/nix"
        "hyprland/workspaces"
      ];
      modules-center = [ "custom/clock" ];
      modules-right = [
        "custom/cpu"
        "custom/memory"
        "custom/swap"
        "custom/disk"
        "custom/gpu"
        "custom/network"
        "custom/volume"
        "custom/battery"
        "tray"
      ];
      "custom/clock" = {
        exec = "${scripts.clockStatus}";
        return-type = "json";
      };
      "custom/cpu" = {
        exec = "${scripts.cpuStatus}";
        return-type = "json";
      };
      # The stat scripts run for the bar's whole lifetime and print one
      # JSON line per update, like the network module.
      "custom/memory" = {
        exec = "${scripts.memoryStatus}";
        return-type = "json";
      };
      "custom/swap" = {
        exec = "${scripts.swapStatus}";
        return-type = "json";
      };
      "custom/disk" = {
        exec = "${scripts.diskStatus}";
        return-type = "json";
      };
      "custom/gpu" = {
        exec = "${scripts.gpuStatus}";
        return-type = "json";
      };
      "custom/network" = {
        exec = "${scripts.networkStatus}";
        return-type = "json";
      };
      "custom/volume" = {
        exec = "${scripts.volumeStatus}";
        return-type = "json";
        on-click = "${pavucontrol}/bin/pavucontrol";
      };
      "custom/battery" = {
        exec = "${scripts.batteryStatus}";
        return-type = "json";
      };
      "custom/nix" = {
        exec = "${scripts.nixStatus}";
        return-type = "json";
      };
    };

    style = ''
      * { font-family: "VGA", monospace; font-size: 13px; }
      window#waybar { background: ${palette.surface}; color: ${palette.text}; border-bottom: 2px solid ${palette.border}; border-radius: 0; }
      #custom-clock, #custom-cpu, #custom-memory, #custom-swap, #custom-disk, #custom-gpu, #custom-network, #custom-volume, #custom-battery { padding: 0 10px; }
      /* The GTK 3 theme (gtk.nix) makes every button bold. */
      #workspaces button { color: ${palette.text}; padding: 0 7px; border-radius: 0; font-weight: normal; }
      #workspaces button.active { background: ${palette.text}; color: ${palette.surface}; border-radius: 0; }
      /* System stats: one distinct hue per stat, consistent with common
         system-monitor conventions (cpu/mem/disk/gpu each get their own
         color). Red stays reserved for alert states only. */
      #custom-cpu { color: ${palette.cpu}; }
      #custom-memory { color: ${palette.memory}; }
      /* Swap is a dimmer shade of the RAM hue, which marks the two as
         related. */
      #custom-swap { color: ${palette.swap}; }
      #custom-disk { color: ${palette.disk}; }
      #custom-gpu { color: ${palette.gpu}; }
      #custom-battery.critical { color: ${palette.alert}; }
      /* The same 2px white rule as every border in the rice, between the
         text stats and the tray icons. It sits on the last text module
         instead of the tray: waybar hides the tray while it has no icons,
         at login before the apps register and whenever the last one
         quits, and the rule went with it. A machine with no battery loses
         the rule, since the battery script then prints nothing. Icons need
         less room than text, so the tray keeps only a few px on each
         side. */
      #custom-battery { border-right: 2px solid ${palette.border}; }
      #tray { padding: 0 4px; }
      /* VGA has no Nix logo, so it comes from the Nerd Font, in the
         palette's blue. The Propo variant gives the icon its full
         width. The plain one squeezes it into a text cell and clips it.
         The glyph sits 1px low in its own box, so 2px of bottom padding
         centres it on the workspace numbers. */
      #custom-nix { font-family: "DejaVuSansM Nerd Font Propo"; font-size: 20px; color: ${palette.nix}; padding: 0 6px 2px 6px; }
      ${tooltipStyle}
      /* Tray right-click menus (each app's own menu, rendered by waybar
         through this same stylesheet) styled as fuzzel: opaque fill, 2px
         white border, square corners, 11pt, and the hovered row in
         reverse video like fuzzel's selection. */
      menu { background: ${palette.surface}; border: 2px solid ${palette.border}; border-radius: 0; box-shadow: none; padding: 0; }
      .popup decoration { border-radius: 0; box-shadow: none; }
      menu menuitem { background: transparent; color: ${palette.border}; border-radius: 0; padding: 4px 12px; }
      menu menuitem label { font-size: 11pt; }
      menu menuitem:hover { background: ${palette.border}; color: ${palette.surface}; }
      menu menuitem:disabled { color: ${palette.outline}; }
      menu separator { background: ${palette.border}; min-height: 2px; margin: 2px 0; }
    '';
  };
}

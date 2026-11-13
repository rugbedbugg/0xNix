# The bottom bar: a second waybar process that reserves the screen's bottom
# edge. It shows the focused window on the left, the track mpd is playing in
# the middle and a few system readings on the right. Its height comes from
# overlay-geometry.nix, which the floating windows, the special-workspace
# overlays and the minimap also read to stay clear of it. It is its own
# service for the same reason as the small bars in waybar-side-bars.nix: a
# service can restart it alone.
{
  config,
  osConfig,
  pkgs,
  palette,
  ...
}:
let
  geometry = import ./overlay-geometry.nix { inherit (config.desktop) screen; };
  scripts = import ./status-scripts.nix { inherit pkgs osConfig palette; };
  tooltipStyle = import ./tooltip-style.nix { inherit palette; };
  inherit (scripts) barHelpers statPath;

  rmpc = "${config.programs.rmpc.package}/bin/rmpc";
  bluetoothctl = "${pkgs.bluez}/bin/bluetoothctl";

  # The track mpd is playing. The script asks rmpc, the same client as the
  # music overlay, and keeps running when mpd is down or restarts. The
  # text states the player's state in words, since the VGA font has no
  # play or pause symbols.
  musicStatus = pkgs.writeShellScript "waybar-music" ''
    export PATH=${statPath}
    ${barHelpers}

    clock() {
      awk -v s="$1" 'BEGIN { printf "%d:%02d", s / 60, s % 60 }'
    }

    while :; do
      if status=$(${rmpc} status 2>/dev/null) && [ -n "$status" ]; then
        state=$(printf '%s' "$status" | jq -r '.state // ""')
        song=$(${rmpc} song 2>/dev/null)
        artist=$(printf '%s' "$song" | jq -r '.metadata.artist // empty' 2>/dev/null)
        title=$(printf '%s' "$song" | jq -r '.metadata.title // .file // empty' 2>/dev/null)
        album=$(printf '%s' "$song" | jq -r '.metadata.album // empty' 2>/dev/null)
        if [ -z "$title" ] || [ "$state" = Stop ]; then
          emit "Music stopped" "$(row State Stopped)" off
        else
          case "$state" in
            Play) word=Play class=play ;;
            *) word=Pause class=pause ;;
          esac
          elapsed=$(printf '%s' "$status" | jq -r '.elapsed.secs // 0')
          length=$(printf '%s' "$status" | jq -r '.duration.secs // 0')
          tooltip=$(
            row Title "$title"
            [ -n "$artist" ] && row Artist "$artist"
            [ -n "$album" ] && row Album "$album"
            row Time "$(clock "$elapsed") / $(clock "$length")"
            row Volume "$(printf '%s' "$status" | jq -r '.volume')%"
          )
          emit "$word: ''${artist:+$artist - }$title" "$tooltip" "$class"
        fi
      else
        emit "Music off" "$(row State "mpd is not running")" off
      fi
      sleep 2
    done
  '';

  # The CPU temperature. The hwmon index changes between boots, so the
  # script finds the sensors by name. The tooltip lists the others too.
  tempStatus = pkgs.writeShellScript "waybar-temp" ''
    export PATH=${statPath}
    ${barHelpers}

    sensor() {
      for dir in /sys/class/hwmon/hwmon*; do
        if [ "$(cat "$dir/name" 2>/dev/null)" = "$1" ] && [ -r "$dir/temp1_input" ]; then
          echo $(($(cat "$dir/temp1_input") / 1000))
          return
        fi
      done
    }

    cpu_sensor=k10temp
    [ -n "$(sensor "$cpu_sensor")" ] || cpu_sensor=coretemp
    [ -n "$(sensor "$cpu_sensor")" ] || exit 0

    while :; do
      cpu=$(sensor "$cpu_sensor")
      tooltip=$(
        row CPU "$cpu C"
        [ -n "$(sensor amdgpu)" ] && row GPU "$(sensor amdgpu) C"
        [ -n "$(sensor nvme)" ] && row Disk "$(sensor nvme) C"
      )
      class=
      if [ "$cpu" -ge 90 ]; then
        class=critical
      elif [ "$cpu" -ge 80 ]; then
        class=warning
      fi
      emit "Temp $cpu C" "$tooltip" "$class"
      sleep 3
    done
  '';


  # Switch Bluetooth on or off. The module itself only reports the state.
  toggleBluetooth = pkgs.writeShellScript "toggle-bluetooth" ''
    if ${bluetoothctl} show | ${pkgs.gnugrep}/bin/grep -q 'Powered: yes'; then
      ${bluetoothctl} power off
    else
      ${bluetoothctl} power on
    fi
  '';

  bottomBarConfig = pkgs.writeText "waybar-bottom-config.json" (
    builtins.toJSON {
      name = "waybar-bottom";
      layer = "top";
      position = "bottom";
      height = geometry.bottomBar;
      modules-left = [ "hyprland/window" ];
      modules-center = [ "custom/music" ];
      modules-right = [
        "custom/temp"
        "backlight"
        "bluetooth"
        "power-profiles-daemon"
      ];
      "hyprland/window" = {
        format = "{class}: {title}";
        max-length = 80;
        separate-outputs = true;
      };
      "custom/music" = {
        exec = "${musicStatus}";
        return-type = "json";
        max-length = 60;
        on-click = "${rmpc} togglepause";
      };
      "custom/temp" = {
        exec = "${tempStatus}";
        return-type = "json";
      };
      # Scrolling over it changes the brightness, which is the module's own
      # behaviour.
      backlight.format = "Bri {percent}%";
      bluetooth = {
        format = "BT {status}";
        format-on = "BT on";
        format-off = "BT off";
        format-disabled = "BT n/a";
        format-connected = "BT {device_alias}";
        on-click = "${toggleBluetooth}";
      };
      # A click cycles through the profiles, which is the module's own
      # behaviour.
      power-profiles-daemon = {
        format = "Pwr {profile}";
        tooltip-format = "Power profile: {profile}";
      };
    }
  );

  bottomBarStyle = pkgs.writeText "waybar-bottom-style.css" ''
    * { font-family: "VGA", monospace; font-size: 13px; border-radius: 0; }
    window#waybar { background: ${palette.surface}; color: ${palette.text}; border-top: 2px solid ${palette.border}; }
    #window, #custom-music, #custom-temp, #backlight, #bluetooth, #power-profiles-daemon { padding: 0 10px; }
    #custom-temp { color: ${palette.cpu}; }
    #custom-temp.warning, #custom-temp.critical { color: ${palette.alert}; }
    #custom-music.off, #bluetooth.off, #bluetooth.disabled { color: ${palette.outline}; }
    ${tooltipStyle}
  '';
in
{
  systemd.user.services.waybar-bottom = {
    Unit = {
      Description = "Bottom bar";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${config.programs.waybar.package}/bin/waybar -c ${bottomBarConfig} -s ${bottomBarStyle}";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}

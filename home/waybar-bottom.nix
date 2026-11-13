# The bottom bar: a second waybar process that reserves the screen's bottom
# edge. It shows the focused window on the left, the track mpd is playing in
# the middle, a few system readings on the right and the notification center
# button in the corner. Its height comes from
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
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  swaync = "${config.services.swaync.package}/bin/swaync-client";

  # The track mpd is playing. The script asks rmpc, the same client as the
  # music overlay, and keeps running when mpd is down or restarts. The note
  # in front shows the state: blue while playing, yellow while paused. Long
  # artists and titles are cut short with a ~ so the bar's middle keeps its
  # place.
  musicStatus = pkgs.writeShellScript "waybar-music" ''
    export PATH=${statPath}
    ${barHelpers}

    clock() {
      awk -v s="$1" 'BEGIN { printf "%d:%02d", s / 60, s % 60 }'
    }

    # jq counts characters, so a cut never splits one in two. It also
    # escapes the text, since the bar reads the line as markup.
    shorten() {
      jq -rn --arg s "$1" --argjson n "$2" \
        '$s | (if length > $n then .[:$n - 1] + "~" else . end) | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")'
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
            Play) word=Playing class=play note=${palette.nix} ;;
            *) word=Paused class=pause note=${palette.disk} ;;
          esac
          elapsed=$(printf '%s' "$status" | jq -r '.elapsed.secs // 0')
          length=$(printf '%s' "$status" | jq -r '.duration.secs // 0')
          label=$(shorten "$title" 32)
          [ -n "$artist" ] && label="$(shorten "$artist" 20) - $label"
          text="<span color='$note'>♪</span> $label  <span color='${palette.textMuted}'>$(clock "$elapsed")/$(clock "$length")</span>"
          tooltip=$(
            row State "$word"
            row Title "$title"
            [ -n "$artist" ] && row Artist "$artist"
            [ -n "$album" ] && row Album "$album"
            row Time "$(clock "$elapsed") / $(clock "$length")"
            row Volume "$(printf '%s' "$status" | jq -r '.volume')%"
          )
          jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
            '{text: $text, tooltip: ($tooltip | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")), class: $class}'
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


  # The screen brightness, read from the backlight device. The script checks
  # twice a second and prints only when the level changed. Scrolling changes
  # it by 1%, the step waybar's own backlight module used.
  brightnessStatus = pkgs.writeShellScript "waybar-brightness" ''
    export PATH=${statPath}
    ${barHelpers}

    dev=
    for d in /sys/class/backlight/*; do
      [ -r "$d/brightness" ] && dev=$d && break
    done
    [ -n "$dev" ] || exit 0
    max=$(cat "$dev/max_brightness")

    last=
    while :; do
      now=$(cat "$dev/brightness")
      if [ "$now" != "$last" ]; then
        last=$now
        percent=$(((now * 100 + max / 2) / max))
        tooltip=$(
          row Level "$percent%"
          row Raw "$now of $max"
          row Device "''${dev##*/}"
        )
        emit "Brightness $percent%" "$tooltip"
      fi
      sleep 0.5
    done
  '';

  # The notification center button. swaync-client prints a line on every
  # change. The outer loop starts it again when swaync is not up yet or
  # restarts, so the button never goes blank.
  notificationStatus = pkgs.writeShellScript "waybar-notifications" ''
    export PATH=${statPath}
    ${barHelpers}

    while :; do
      ${swaync} --subscribe-waybar 2>/dev/null | while read -r line; do
        count=$(printf '%s' "$line" | jq -r '.text // ""')
        alt=$(printf '%s' "$line" | jq -r '.alt // ""')
        count=''${count:-0}
        case "$alt" in
          dnd*) dnd=on text="Notif DND" class=dnd ;;
          *) dnd=off text="Notif $count" class=$([ "$count" = 0 ] && echo none || echo some) ;;
        esac
        tooltip=$(
          row Count "$count"
          row DND "$dnd"
        )
        emit "$text" "$tooltip" "$class"
      done
      emit "Notif" "$(row State "swaync is not running")" none
      sleep 2
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
        "custom/brightness"
        "bluetooth"
        "power-profiles-daemon"
        "custom/notification"
      ];
      # Short enough that the window title, the track and the readings all
      # fit across 1920 px without pushing the track off the middle.
      "hyprland/window" = {
        format = "{class}: {title}";
        max-length = 60;
        separate-outputs = true;
      };
      "custom/music" = {
        exec = "${musicStatus}";
        return-type = "json";
        on-click = "${rmpc} togglepause";
      };
      "custom/temp" = {
        exec = "${tempStatus}";
        return-type = "json";
      };
      "custom/brightness" = {
        exec = "${brightnessStatus}";
        return-type = "json";
        on-scroll-up = "${brightnessctl} set 1%+";
        on-scroll-down = "${brightnessctl} --min-value=1 set 1%-";
      };
      # The tooltips line their values up in the same columns as the
      # scripts' rows.
      bluetooth = {
        format = "Bluetooth {status}";
        format-on = "Bluetooth ON";
        format-off = "Bluetooth OFF";
        format-disabled = "Bluetooth OFF";
        format-no-controller = "Bluetooth N/A";
        format-connected = "Bluetooth {device_alias}";
        format-connected-battery = "Bluetooth {device_alias} {device_battery_percentage}%";
        max-length = 26;
        tooltip-format = "Controller {controller_alias}\nAddress    {controller_address}\nDevices    none connected";
        tooltip-format-off = "Controller {controller_alias}\nState      off";
        tooltip-format-disabled = "State      blocked by rfkill";
        tooltip-format-no-controller = "State      no controller";
        tooltip-format-connected = "Controller {controller_alias}\nAddress    {controller_address}\nDevices    {num_connections} connected\n\n{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}  {device_address}";
        tooltip-format-enumerate-connected-battery = "{device_alias}  {device_battery_percentage}%";
        on-click = "${toggleBluetooth}";
      };
      # A click cycles through the profiles, which is the module's own
      # behaviour.
      power-profiles-daemon = {
        format = "Power {icon}";
        format-icons = {
          performance = "Perf";
          balanced = "Bal";
          power-saver = "Save";
          default = "?";
        };
        tooltip-format = "Profile    {profile}\nDriver     {driver}";
      };
      "custom/notification" = {
        exec = "${notificationStatus}";
        return-type = "json";
        on-click = "${swaync} --toggle-panel --skip-wait";
        on-click-right = "${swaync} --close-all --skip-wait";
        on-click-middle = "${swaync} --toggle-dnd --skip-wait";
      };
    }
  );

  bottomBarStyle = pkgs.writeText "waybar-bottom-style.css" ''
    * { font-family: "VGA", monospace; font-size: 13px; border-radius: 0; }
    window#waybar { background: ${palette.surface}; color: ${palette.text}; border-top: 2px solid ${palette.border}; }
    #window, #custom-music, #custom-temp, #custom-brightness, #bluetooth, #power-profiles-daemon, #custom-notification { padding: 0 10px; }
    /* The readings take the top bar's stat hues in the same order, from
       CPU through GPU. Grey marks anything that is off. A hot CPU turns
       yellow, then red. */
    #custom-temp { color: ${palette.cpu}; }
    #custom-temp.warning { color: ${palette.disk}; }
    #custom-temp.critical { color: ${palette.alert}; }
    #custom-brightness { color: ${palette.memory}; }
    #bluetooth { color: ${palette.swap}; }
    #power-profiles-daemon { color: ${palette.gpu}; }
    #custom-music.off, #bluetooth.off, #bluetooth.disabled, #bluetooth.no-controller, #custom-notification.none, #custom-notification.dnd { color: ${palette.outline}; }
    /* The same 2px white rule as every border in the rice, between the
       readings and the notification button. */
    #custom-notification { border-left: 2px solid ${palette.border}; }
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

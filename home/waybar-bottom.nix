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
  busctl = "${pkgs.systemd}/bin/busctl";

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
  # restarts, so the button never goes blank. The tooltip shows the newest
  # notification, which the patched swaync returns over D-Bus (swaync.nix).
  # Tooltips do not wrap, so the script wraps the body at 48 columns and
  # keeps three lines.
  notificationStatus = pkgs.writeShellScript "waybar-notifications" ''
    export PATH=${statPath}
    ${barHelpers}

    latest() {
      timeout 2 ${busctl} --user --json=short call org.erikreider.swaync.cc \
        /org/erikreider/swaync/cc org.erikreider.swaync.cc GetLatestNotification 2>/dev/null \
        | jq -c '.data[0] | fromjson' 2>/dev/null
    }

    # Prints the notification as rows: the summary cut at 48 characters,
    # the body wrapped into at most three lines and the time it arrived.
    latest_rows() {
      local json=$1 t when
      printf '%s' "$json" | jq -r '
        def cut($w): if length > $w then .[:$w - 1] + "~" else . end;
        def wrap($w): gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ")
          | if . == "" then [] else split(" ")
            | reduce .[] as $x ([];
                if length == 0 then [$x]
                elif (.[-1] | length) + 1 + ($x | length) <= $w then .[-1] += " " + $x
                else . + [$x] end)
            | map(cut($w)) end;
        def row($k; $v): ($k + "          ")[:10] + " " + $v;
        row("App"; .app | cut(48)),
        row("Summary"; .summary | cut(48)),
        (.body | wrap(48)
          | (if length > 3 then .[:3] | .[2] |= (if length < 48 then . + "~" else .[:47] + "~" end) else . end)
          | to_entries[] | row(if .key == 0 then "Body" else "" end; .value))'
      t=$(printf '%s' "$json" | jq -r '.time')
      if [ "$(date -d "@$t" +%F)" = "$(date +%F)" ]; then
        when=$(date -d "@$t" +%H:%M)
      else
        when=$(date -d "@$t" '+%d %b %H:%M')
      fi
      row Time "$when"
    }

    while :; do
      ${swaync} --subscribe-waybar 2>/dev/null | while read -r line; do
        count=$(printf '%s' "$line" | jq -r '.text // ""')
        alt=$(printf '%s' "$line" | jq -r '.alt // ""')
        count=''${count:-0}
        case "$alt" in
          dnd*) text="Notif DND" class=dnd ;;
          *) text="Notif $count" class=$([ "$count" = 0 ] && echo none || echo some) ;;
        esac
        json=$(latest)
        if [ -n "$json" ] && [ "$(printf '%s' "$json" | jq -r '.time // empty')" ]; then
          tooltip=$(latest_rows "$json")
        else
          tooltip=$(row State "no notifications")
        fi
        emit "$text" "$tooltip" "$class"
      done
      emit "Notif" "$(row State "swaync is not running")" none
      sleep 2
    done
  '';

  # Bluetooth, read from bluetoothctl every three seconds. waybar's own
  # module only knows the controller's name and address and each
  # connection's name, address and battery. This also shows the
  # controller's switches and every paired device. bluetoothctl waits
  # forever while bluetoothd is down, so each call has a timeout.
  bluetoothStatus = pkgs.writeShellScript "waybar-bluetooth" ''
    export PATH=${statPath}
    ${barHelpers}

    bt() {
      timeout 2 ${bluetoothctl} "$@" 2>/dev/null
    }

    # The value of one "Key: value" line in bluetoothctl's output.
    field() {
      awk -v k="$1" 'index($0, "\t" k ": ") == 1 { print substr($0, length(k) + 4); exit }'
    }

    while :; do
      show=$(bt show)
      status=$?
      if [ "$status" = 124 ]; then
        emit "Bluetooth N/A" "$(row State "bluetoothd is not running")" no-controller
        sleep 3
        continue
      fi
      if [ -z "$show" ] || printf '%s' "$show" | grep -q "No default controller"; then
        emit "Bluetooth N/A" "$(row State "no controller")" no-controller
        sleep 3
        continue
      fi

      power=$(printf '%s' "$show" | field PowerState)
      [ -n "$power" ] || power=$(printf '%s' "$show" | field Powered | awk '{ print ($1 == "yes") ? "on" : "off" }')
      controller=$(
        row Controller "$(printf '%s' "$show" | field Alias)"
        row Address "$(printf '%s' "$show" | awk 'NR == 1 { print $2 }')"
        row Power "$power"
        row Visible "$(printf '%s' "$show" | field Discoverable)"
        row Pairable "$(printf '%s' "$show" | field Pairable)"
        row Scanning "$(printf '%s' "$show" | field Discovering)"
      )

      # One info call per connected device. The first one names the bar.
      online=$(bt devices Connected)
      connected= first=
      label=Connected
      while read -r _ addr name; do
        [ -n "$addr" ] || continue
        info=$(bt info "$addr")
        battery=$(printf '%s' "$info" | awk -F'[()]' '/^\tBattery Percentage:/ { print $2; exit }')
        icon=$(printf '%s' "$info" | field Icon)
        [ -n "$first" ] || first="$name''${battery:+ $battery%}"
        connected+="$(row "$label" "$(cell "$name") $addr''${battery:+  $battery%}''${icon:+  ''${icon#*-}}")"$'\n'
        label=
      done <<<"$online"
      paired=$(
        label=Paired
        bt devices Paired | while read -r _ addr name; do
          printf '%s' "$online" | grep -q " $addr " && continue
          row "$label" "$(cell "$name") $addr"
          label=
        done
      )

      case "$power" in
        on)
          if [ -n "$first" ]; then
            text="Bluetooth $first" class=connected
          else
            text="Bluetooth ON" class=on
          fi
          ;;
        off-blocked) text="Bluetooth OFF" class=disabled ;;
        *) text="Bluetooth OFF" class=off ;;
      esac

      tooltip=$(
        printf '%s\n' "$controller"
        if [ -n "$connected" ] || [ -n "$paired" ]; then
          echo
          [ -n "$connected" ] && printf '%s' "$connected"
          [ -n "$paired" ] && printf '%s\n' "$paired"
        fi
      )
      emit "$text" "$tooltip" "$class"
      sleep 3
    done
  '';

  # Switch Bluetooth on or off. The module only reports the state.
  toggleBluetooth = pkgs.writeShellScript "toggle-bluetooth" ''
    if ${bluetoothctl} show | ${pkgs.gnugrep}/bin/grep -q 'Powered: yes'; then
      ${bluetoothctl} power off
    else
      ${bluetoothctl} power on
    fi
  '';

  bottomBarConfig = pkgs.writeText "waybar-bottom-config.json" (
    builtins.toJSON (
      {
        name = "waybar-bottom";
        layer = "top";
        position = "bottom";
        height = geometry.bottomBar;
        modules-left = [
          "hyprland/window"
        ];
        modules-center = [ "custom/music" ];
        modules-right = [
          "custom/temp"
          "custom/brightness"
          "custom/bluetooth"
        ]
        ++ config.desktop.bottomBar.modulesRight
        ++ [
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
        "custom/bluetooth" = {
          exec = "${bluetoothStatus}";
          return-type = "json";
          max-length = 26;
          on-click = "${toggleBluetooth}";
        };
        # A click cycles through the profiles, which is the module's own
        # behaviour.
        power-profiles-daemon = {
          format = "Mode {icon}";
          format-icons = {
            performance = "Perf";
            balanced = "Bal";
            power-saver = "Save";
            default = "?";
          };
          tooltip = false;
        };
        "custom/notification" = {
          exec = "${notificationStatus}";
          return-type = "json";
          on-click = "${swaync} --toggle-panel --skip-wait";
          on-click-right = "${swaync} --close-all --skip-wait";
          on-click-middle = "${swaync} --toggle-dnd --skip-wait";
        };
      }
      // config.desktop.bottomBar.modules
    )
  );

  bottomBarStyle = pkgs.writeText "waybar-bottom-style.css" ''
    * { font-family: "VGA", monospace; font-size: 13px; border-radius: 0; }
    window#waybar { background: ${palette.surface}; color: ${palette.text}; border-top: 2px solid ${palette.border}; }
    #window, #custom-music, #custom-temp, #custom-brightness, #custom-bluetooth, #power-profiles-daemon, #custom-notification { padding: 0 10px; }
    /* The readings take the top bar's stat hues in the same order, from
       CPU through GPU. Grey marks anything that is off. A hot CPU turns
       yellow, then red. */
    #custom-temp { color: ${palette.cpu}; }
    #custom-temp.warning { color: ${palette.disk}; }
    #custom-temp.critical { color: ${palette.alert}; }
    #custom-brightness { color: ${palette.memory}; }
    #custom-bluetooth { color: ${palette.swap}; }
    #power-profiles-daemon { color: ${palette.gpu}; }
    #custom-music.off, #custom-bluetooth.off, #custom-bluetooth.disabled, #custom-bluetooth.no-controller, #custom-notification.none, #custom-notification.dnd { color: ${palette.outline}; }
    /* The same 2px white rule as every border in the rice, between the
       readings and the notification button. */
    #custom-notification { border-left: 2px solid ${palette.border}; }
    ${tooltipStyle}
    ${config.desktop.bottomBar.style}
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

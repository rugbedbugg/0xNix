{
  config,
  osConfig,
  pkgs,
  vars,
  ...
}:
let
  geometry = import ./overlay-geometry.nix { inherit (vars) screen; };
  screenrec = import ./screenrec.nix { inherit config pkgs; };
  gtkTty = import ./gtk-tty.nix { inherit pkgs; };
  pavucontrol = gtkTty.wrap pkgs.pavucontrol "pavucontrol";

  # Special-workspace bar: a second, separate waybar process that sits on
  # the top-left corner of the floating special-workspace terminals
  # (keybinds.nix). overlay-geometry.nix computes its margins from the same
  # screen size as those windows. Measuring the layer surface live
  # confirmed both waybar quirks it relies on: margin-top counts from below
  # the main bar, and an explicit width drops the side anchors
  # (bar.cpp setPosition).
  #
  # Content: waybar's own hyprland/workspaces module with show-special on
  # and every non-special workspace ignored — so it lists every special
  # workspace that currently exists, with the shown one highlighted, and
  # updates itself from Hyprland's IPC. `ignore-workspaces` is a full
  # regex_match against the raw name ("1", "special:music"), and {name}
  # already has the "special:" prefix stripped — both confirmed in the
  # waybar 0.15.0 source.
  #
  # Visibility: a separate process, so SIGUSR1/SIGUSR2 can be pointed at
  # this bar alone with explicit show/hide actions (per-bar on-sigusr1/2,
  # waybar(5)) instead of a toggle that could drift out of sync — and the
  # main bar keeps its default SIGUSR2-reload behaviour, which home-manager
  # relies on when reloading waybar.service.
  specialBarConfig = pkgs.writeText "waybar-special-config.json" (
    builtins.toJSON {
      layer = "top";
      position = "top";
      inherit (geometry.label) height;
      margin-top = geometry.label.marginTop;
      margin-left = geometry.label.marginLeft;
      margin-right = geometry.label.marginRight;
      exclusive = false;
      passthrough = true;
      start_hidden = true;
      on-sigusr1 = "show";
      on-sigusr2 = "hide";
      modules-left = [ "hyprland/workspaces" ];
      "hyprland/workspaces" = {
        format = "{name}";
        show-special = true;
        ignore-workspaces = [ "(?!special:).*" ];
      };
    }
  );

  # Same look as the main bar's workspace buttons (reverse video for the
  # shown one). The background and border sit on #workspaces, which sizes
  # to its buttons, so the rest of the 400px-wide bar stays transparent —
  # and passthrough lets clicks through that empty part.
  specialBarStyle = pkgs.writeText "waybar-special-style.css" ''
    * { font-family: "VGA", monospace; font-size: 13px; border-radius: 0; }
    window#waybar { background: transparent; }
    #workspaces { background: #20242c; border: 2px solid #ffffff; }
    #workspaces button { color: #eceff4; background: transparent; padding: 0 7px; border: none; border-radius: 0; }
    #workspaces button.active, #workspaces button.visible { background: #eceff4; color: #20242c; }
  '';

  # Tooltips styled as mako toasts: opaque fill, 2px white border, square
  # corners, 8px padding, same font and size. The GTK theme otherwise gives
  # them a translucent, rounded, shadowed box. Every bar with tooltips
  # shares these.
  tooltipStyle = ''
    tooltip, tooltip.background { background: #20242c; border: 2px solid #ffffff; border-radius: 0; box-shadow: none; opacity: 1; }
    tooltip label { color: #ffffff; font-size: 11pt; padding: 8px; }
  '';

  # Where the clock sits, for the small bars laid over the main bar on
  # either side of it. The clock never moves: it's alone in the main bar's
  # centre, which waybar keeps in the screen's middle. At 13px the VGA font
  # is 8px per character. The clock is 17 characters ("Fri 30 Oct  11:40")
  # plus 10px padding on each side.
  clockSlot = rec {
    inherit (config.programs.waybar.settings.mainBar) height;
    cell = 8;
    width = 17 * cell + 20;
    left = vars.screen.width / 2 - width / 2;
    right = left + width;
  };

  # The shared part of such a bar's config. As with the special bar, the
  # side margins set the width. Margins count from below the main bar's
  # exclusive zone, so a negative top margin of the main bar's height lays
  # it over the bar. At the same height, its text shares the clock's
  # baseline. The background is transparent, so the main bar shows through.
  besideClock =
    { name, left, width }:
    {
      inherit name;
      layer = "top";
      position = "top";
      inherit (clockSlot) height;
      margin-top = -clockSlot.height;
      margin-left = left;
      margin-right = vars.screen.width - left - width;
      exclusive = false;
    };
  besideClockStyle = ''
    * { font-family: "VGA", monospace; font-size: 13px; border-radius: 0; }
    window#waybar { background: transparent; }
    ${tooltipStyle}
  '';

  # Recording timer bar: a waybar process that shows screenrec.nix's
  # "REC m:ss" while a recording runs. It's its own layer surface, named
  # waybar-recording, so the no_screen_share layer rule below can keep it
  # out of screen captures. Recordings and screenshots get a black box
  # there instead of the elapsed time.
  #
  # It sits flush against the clock's left edge and the text grows
  # leftwards inside it, with room for 10 characters ("REC 100:00") plus
  # 10px padding on each side.
  #
  # The recorder starts this bar's service with each recording and stops
  # it afterwards. Waybar's own hide only makes a bar transparent and
  # leaves the surface up, which would leave the black box in every
  # capture.
  recordingBarConfig =
    let
      width = 10 * clockSlot.cell + 20;
    in
    pkgs.writeText "waybar-recording-config.json" (
      builtins.toJSON (
        besideClock {
          name = "waybar-recording";
          left = clockSlot.left - width;
          inherit width;
        }
        // {
          modules-right = [ "custom/recording" ];
        # Clicking it stops the recording, like pressing the record key.
          "custom/recording" = {
            exec = "${screenrec.status}";
            return-type = "json";
            on-click = "${screenrec.toggle} stop";
          };
        }
      )
    );

  # A running recording needs stopping at some point, so it gets the alert
  # red.
  recordingBarStyle = pkgs.writeText "waybar-recording-style.css" ''
    ${besideClockStyle}
    #custom-recording { color: #ff0000; padding: 0 10px; }
  '';

  # Mic bar: the REC timer's twin on the clock's right. Its text grows
  # rightwards, with room for 7 characters ("Mic OFF"). It always shows, so
  # the bar always runs. Clicking mutes the default mic and scrolling steps
  # its level by 1% up to 100%.
  micBarConfig =
    let
      width = 7 * clockSlot.cell + 20;
    in
    pkgs.writeText "waybar-mic-config.json" (
      builtins.toJSON (
        besideClock {
          name = "waybar-mic";
          left = clockSlot.right;
          inherit width;
        }
        // {
          modules-left = [ "custom/mic" ];
          "custom/mic" = {
            exec = "${micStatus}";
            return-type = "json";
            on-click = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
            on-scroll-up = "${pkgs.wireplumber}/bin/wpctl set-volume -l 1 @DEFAULT_AUDIO_SOURCE@ 1%+";
            on-scroll-down = "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 1%-";
          };
        }
      )
    );

  # A live mic gets the alert red, like the other things that need
  # attention. A muted one gets the grey that marks disabled things
  # elsewhere in the rice.
  micBarStyle = pkgs.writeText "waybar-mic-style.css" ''
    ${besideClockStyle}
    #custom-mic { padding: 0 10px; }
    #custom-mic.on { color: #ff0000; }
    #custom-mic.off { color: #6c7380; }
  '';

  # Shows the bar while any special workspace is on screen and hides it
  # otherwise, driven by Hyprland's own `activespecial` IPC event — so it's
  # correct no matter how the workspace was hidden (its toggle key, switching
  # workspace, focusing another window). Event format confirmed live:
  # "activespecial>>special:music,eDP-1" when shown, "activespecial>>,eDP-1"
  # when closed. Single-monitor setup, so the monitor field is ignored.
  specialBarWatcher = pkgs.writeShellScript "special-bar-watcher" ''
    bar() {
      ${pkgs.systemd}/bin/systemctl --user kill --kill-whom=main --signal="$1" waybar-special.service
    }

    # The bar always starts hidden; only bring it up if a special workspace
    # is already on screen (i.e. this watcher restarted mid-session). The
    # sleep matters: SIGUSR1/2 terminate a process that hasn't installed its
    # handlers yet, so a signal sent while waybar is still starting would
    # kill it rather than show it.
    shown=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[0].specialWorkspace.name')
    if [ -n "$shown" ]; then
      sleep 1
      bar SIGUSR1
    fi

    ${pkgs.socat}/bin/socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" \
      | while IFS= read -r line; do
          case "$line" in
            "activespecial>>,"*) bar SIGUSR2 ;;
            "activespecial>>"*) bar SIGUSR1 ;;
          esac
        done

    # The event socket only closes when Hyprland goes away; exit non-zero so
    # Restart=on-failure brings the watcher back if that ever happens
    # mid-session.
    exit 1
  '';

  # Shell functions shared by the main bar's script modules. Each script puts
  # jq, gawk and coreutils on its PATH.
  #   emit TEXT TOOLTIP [CLASS]  print one waybar JSON line, with the tooltip
  #                              escaped for Pango markup
  #   row LABEL VALUE            print one aligned tooltip row
  #   cell NAME                  NAME in a 16-column cell. A longer one is
  #                              cut to 15 and ends in ~, so the column
  #                              after it stays aligned
  #   iec BYTES                  a byte count in KiB, MiB or GiB
  #   rate BYTES                 a byte rate in kB/s, MB/s or GB/s
  #   pcpu SHARE                 a CPU share as a percentage
  #   top [FORMAT]               read "VALUE COMMAND" lines and print rows
  #                              for the five programs using the most. A
  #                              program's processes add up to one row, Nix
  #                              wrapper names (.foo-wrapped) become foo and
  #                              kernel threads ([kworker/0:1]) become kworker.
  #                              FORMAT names the function that prints each
  #                              value, iec by default.
  barHelpers = ''
    emit() {
      jq -cn --arg text "$1" --arg tooltip "$2" --arg class "''${3:-}" \
        '{text: $text, tooltip: ($tooltip | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")), class: $class}'
    }

    row() {
      printf '%-10s %s\n' "$1" "$2"
    }

    cell() {
      local name=$1
      [ ''${#name} -gt 16 ] && name="''${name:0:15}~"
      printf '%-16s' "$name"
    }

    iec() {
      awk -v b="$1" 'BEGIN {
        split("B KiB MiB GiB TiB", u, " "); i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i]
      }'
    }

    rate() {
      awk -v b="$1" 'BEGIN {
        split("B/s kB/s MB/s GB/s", u, " "); i = 1
        while (b >= 1000 && i < 4) { b /= 1000; i++ }
        printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i]
      }'
    }

    pcpu() {
      awk -v p="$1" 'BEGIN { printf "%.1f%%", p }'
    }

    top() {
      fmt=''${1:-iec}
      awk '{
        name = $2
        if (name ~ /^\[/) {
          gsub(/^\[|\]$/, "", name); sub(/\/.*/, "", name)
        } else {
          sub(/.*\//, "", name); sub(/^\./, "", name); sub(/-wrapped$/, "", name); sub(/:$/, "", name)
        }
        sum[name] += $1
      } END { for (n in sum) print sum[n], n }' \
        | sort -rn | head -n 5 \
        | {
            label=Top
            while read -r value name; do
              row "$label" "$(cell "$name") $($fmt $value)"
              label=
            done
          }
    }
  '';

  # Network module for the main bar. Waybar's own network module has no
  # placeholder for the Wi-Fi channel width or the negotiated link rate, so
  # this script builds the bar text and tooltip from nmcli instead. It runs
  # for the bar's whole lifetime and prints one JSON line every 2s, which
  # keeps the previous byte counters in shell variables for the live
  # down/up rates.
  networkStatus = pkgs.writeShellScript "waybar-network" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.networkmanager
        pkgs.jq
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
      ]
    }
    ${barHelpers}

    prev_dev= prev_rx=0 prev_tx=0 prev_t=0
    while :; do
      dev= type=
      while IFS=: read -r d t s; do
        if [ "$s" = connected ] && { [ "$t" = wifi ] || [ "$t" = ethernet ]; }; then
          dev=$d type=$t
          break
        fi
      done < <(nmcli -t -f DEVICE,TYPE,STATE device)

      if [ -z "$dev" ]; then
        emit Offline "No connection" disconnected
        prev_dev=
        sleep 2
        continue
      fi

      # Live rates from the kernel byte counters, averaged since the last
      # sample. The first sample after a device change has no baseline.
      rx=$(cat /sys/class/net/$dev/statistics/rx_bytes)
      tx=$(cat /sys/class/net/$dev/statistics/tx_bytes)
      now=$(date +%s%N)
      if [ "$dev" = "$prev_dev" ] && [ "$now" -gt "$prev_t" ]; then
        down=$(rate $(( (rx - prev_rx) * 1000000000 / (now - prev_t) )))
        up=$(rate $(( (tx - prev_tx) * 1000000000 / (now - prev_t) )))
      else
        down="..." up="..."
      fi
      prev_dev=$dev prev_rx=$rx prev_tx=$tx prev_t=$now

      addr=$(nmcli -g IP4.ADDRESS device show "$dev" | head -n1)
      gw=$(nmcli -g IP4.GATEWAY device show "$dev")

      if [ "$type" = wifi ]; then
        # Terse output escapes ":" inside fields as "\:". Swap those for a
        # control byte before splitting, then put them back. SSID comes
        # last so any leftover text stays with it.
        line=$(nmcli -t -f IN-USE,CHAN,FREQ,RATE,BANDWIDTH,SIGNAL,SECURITY,BSSID,SSID \
          device wifi list --rescan no ifname "$dev" | grep -m1 '^\*')
        line=''${line//\\:/$'\x01'}
        IFS=: read -r _ chan freq linkrate width signal security bssid ssid <<< "$line"
        bssid=''${bssid//$'\x01'/:}
        ssid=''${ssid//$'\x01'/:}
        ssid=''${ssid//\\\\/\\}
        tooltip=$(printf '%-10s %s\n' \
          SSID "$ssid" \
          Signal "$signal%" \
          Channel "$chan ($freq)" \
          Bandwidth "$width" \
          "Link rate" "$linkrate" \
          Security "''${security:-open}" \
          BSSID "$bssid" \
          IP "''${addr:-none}" \
          Gateway "''${gw:-none}" \
          Down "$down" \
          Up "$up")
        emit "Wi-Fi $signal%" "$tooltip" wifi
      else
        speed=$(cat /sys/class/net/$dev/speed 2>/dev/null)
        tooltip=$(printf '%-10s %s\n' \
          Interface "$dev" \
          "Link rate" "''${speed:+$speed Mbit/s}" \
          IP "''${addr:-none}" \
          Gateway "''${gw:-none}" \
          Down "$down" \
          Up "$up")
        emit LAN "$tooltip" ethernet
      fi
      sleep 2
    done
  '';

  # Toasts on plugging in and unplugging the charger. The kernel sends a
  # power_supply uevent on every battery or adapter change. Only a change
  # in the adapter's online state shows a toast.
  powerWatcher = pkgs.writeShellScript "power-watcher" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.systemd
        pkgs.libnotify
        pkgs.coreutils
        pkgs.gnugrep
      ]
    }

    ac=
    for s in /sys/class/power_supply/*; do
      if [ "$(cat "$s/type")" = Mains ]; then
        ac=$s
        break
      fi
    done
    [ -n "$ac" ] || exit 0

    capacity() {
      cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1
    }

    last=$(cat "$ac/online")
    udevadm monitor --udev --subsystem-match=power_supply \
      | while IFS= read -r line; do
          case "$line" in
            UDEV*) ;;
            *) continue ;;
          esac
          now=$(cat "$ac/online")
          [ "$now" = "$last" ] && continue
          last=$now
          if [ "$now" = 1 ]; then
            notify-send -a power "Charging" "Battery $(capacity)%"
          else
            notify-send -a power "On battery" "Battery $(capacity)%"
          fi
        done

    # udevadm only exits if udev goes away. Exit non-zero so the service
    # restarts.
    exit 1
  '';

  # The PATH every stat script below starts from.
  statPath = pkgs.lib.makeBinPath [
    pkgs.jq
    pkgs.coreutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.findutils
    pkgs.procps
    pkgs.util-linux
    pkgs.pciutils
  ];

  # CPU module. Usage is the share of CPU time spent outside idle and
  # iowait since the last sample, the same as waybar's own cpu module. The
  # top list measures each program over that same interval rather than
  # ps's lifetime average, so it shows what is busy now. Its shares are of
  # the whole CPU, so they add up to the usage figure.
  cpuStatus = pkgs.writeShellScript "waybar-cpu" ''
    export PATH=${statPath}
    ${barHelpers}

    model=$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo)
    threads=$(nproc)
    temp=
    for h in /sys/class/hwmon/hwmon*; do
      case "$(cat $h/name)" in
        k10temp | coretemp | zenpower)
          temp=$h/temp1_input
          break
          ;;
      esac
    done

    # "TOTAL IDLE" ticks for the whole CPU.
    ticks() {
      awk '/^cpu / { t = 0; for (i = 2; i <= 9; i++) t += $i; print t, $5 + $6; exit }' /proc/stat
    }
    # "PID TICKS NAME" for every process, named after argv[0] like the
    # other modules' top lists.
    procs() {
      {
        ps -eo pid=,args= | awk '{ print "n", $1, $2 }'
        cat /proc/[0-9]*/stat 2>/dev/null | awk '{ pid = $1; sub(/^.*\) /, ""); print "t", pid, $12 + $13 }'
      } | awk '$1 == "n" { name[$2] = $3 } $1 == "t" { t[$2] = $3 }
          END { for (p in t) if (p in name) print p, t[p], name[p] }'
    }

    read -r prev_total prev_idle < <(ticks)
    prev_procs=$(procs)
    sleep 2
    while :; do
      read -r total idle < <(ticks)
      cur_procs=$(procs)
      dt=$((total - prev_total))
      usage=$((dt > 0 ? (dt - (idle - prev_idle)) * 100 / dt : 0))
      tooltip=$(
        row Model "$model"
        row Usage "$usage%"
        row Threads "$threads"
        v=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null \
          | awk '{ s += $1 } END { if (NR) printf "%d MHz average", s / NR / 1000 }')
        [ -n "$v" ] && row Clock "$v"
        [ -n "$temp" ] && row Temp "$(($(cat $temp) / 1000)) °C"
        row Load "$(cut -d' ' -f1-3 /proc/loadavg)"
        awk -v dt=$dt 'NR == FNR { prev[$1] = $2; next }
            dt > 0 && ($1 in prev) && $2 > prev[$1] { print ($2 - prev[$1]) * 100 / dt, $3 }' \
          <(printf '%s\n' "$prev_procs") <(printf '%s\n' "$cur_procs") \
          | top pcpu
      )
      emit "CPU $usage%" "$tooltip"
      prev_total=$total prev_idle=$idle prev_procs=$cur_procs
      sleep 2
    done
  '';

  # RAM module. The percentage counts memory in use as total minus
  # available, the same as waybar's own memory module.
  memoryStatus = pkgs.writeShellScript "waybar-memory" ''
    export PATH=${statPath}
    ${barHelpers}

    while :; do
      eval "$(awk '/^(MemTotal|MemAvailable|Buffers|Cached|Shmem):/ {
        sub(":", "", $1); printf "%s=%d\n", $1, $2 * 1024
      }' /proc/meminfo)"
      used=$((MemTotal - MemAvailable))
      tooltip=$(
        row Used "$(iec $used) / $(iec $MemTotal)"
        row Available "$(iec $MemAvailable)"
        row Cached "$(iec $Cached)"
        row Buffers "$(iec $Buffers)"
        row Shared "$(iec $Shmem)"
        ps -eo rss=,args= | awk '$1 > 0 { print $1 * 1024, $2 }' | top
      )
      emit "RAM $((used * 100 / MemTotal))%" "$tooltip"
      sleep 5
    done
  '';

  # Swap module. A zram device also shows how much it holds, what that
  # takes in RAM once compressed, and the ratio between the two.
  swapStatus = pkgs.writeShellScript "waybar-swap" ''
    export PATH=${statPath}
    ${barHelpers}

    while :; do
      eval "$(awk '/^(SwapTotal|SwapFree):/ {
        sub(":", "", $1); printf "%s=%d\n", $1, $2 * 1024
      }' /proc/meminfo)"
      if [ "$SwapTotal" -eq 0 ]; then
        emit "Swap off" "No swap device"
        sleep 5
        continue
      fi
      used=$((SwapTotal - SwapFree))
      tooltip=$(
        row Used "$(iec $used) / $(iec $SwapTotal)"
        tail -n +2 /proc/swaps | while read -r name _ size dev_used _; do
          dev=''${name##*/}
          if [ -r /sys/block/$dev/mm_stat ]; then
            read -r orig compr ram _ < /sys/block/$dev/mm_stat
            algo=$(grep -o '\[[^]]*\]' /sys/block/$dev/comp_algorithm | tr -d '[]')
            row Device "$dev ($algo)"
            row Stored "$(iec $orig)"
            row "In RAM" "$(iec $ram)"
            if [ "$compr" -gt 0 ]; then
              row Ratio "$(awk -v a=$orig -v b=$compr 'BEGIN { printf "%.1fx", a / b }')"
            fi
          else
            row Device "$name ($(iec $((dev_used * 1024))) / $(iec $((size * 1024))))"
          fi
        done
        awk '/^VmSwap:/ && $2 > 0 { split(FILENAME, p, "/"); print $2 * 1024, p[3] }' \
          /proc/[0-9]*/status 2>/dev/null \
          | while read -r bytes pid; do
              cmd=$(tr '\0' '\n' < /proc/$pid/cmdline 2>/dev/null | head -n1)
              echo "$bytes ''${cmd:-?}"
            done \
          | top
      )
      emit "Swap $((used * 100 / SwapTotal))%" "$tooltip"
      sleep 5
    done
  '';

  # Disk module for /. The percentage matches df's Use%. Read and write
  # rates come from the drive's sector counters, averaged since the last
  # sample. Every other local filesystem gets a row of its own.
  diskStatus = pkgs.writeShellScript "waybar-disk" ''
    export PATH=${statPath}
    ${barHelpers}

    src=$(findmnt -no SOURCE /)
    fstype=$(findmnt -no FSTYPE /)
    drive=$(lsblk -no PKNAME "$src" | head -n1)
    model=$(cat /sys/block/$drive/device/model 2>/dev/null | xargs)

    prev_r=0 prev_w=0 prev_t=0
    while :; do
      read -r size used avail < <(df -B1 --output=size,used,avail / | tail -n1)
      read -r _ _ r _ _ _ w _ < /sys/block/$drive/stat
      now=$(date +%s%N)
      if [ "$prev_t" -gt 0 ]; then
        read_rate=$(rate $(( (r - prev_r) * 512 * 1000000000 / (now - prev_t) )))
        write_rate=$(rate $(( (w - prev_w) * 512 * 1000000000 / (now - prev_t) )))
      else
        read_rate="..." write_rate="..."
      fi
      prev_r=$r prev_w=$w prev_t=$now

      tooltip=$(
        row Mount /
        row Device "''${src##*/} ($fstype)"
        [ -n "$model" ] && row Drive "$model"
        row Used "$(iec $used) / $(iec $size)"
        row Free "$(iec $avail)"
        row Read "$read_rate"
        row Write "$write_rate"
        df -B1 -l -x tmpfs -x devtmpfs -x efivarfs -x ramfs -x overlay \
          --output=target,used,size | tail -n +2 \
          | while read -r target t_used t_size; do
              [ "$target" = / ] && continue
              row "$target" "$(iec $t_used) / $(iec $t_size)"
            done
      )
      emit "Disk $(( (used * 100 + used + avail - 1) / (used + avail) ))%" "$tooltip"
      sleep 5
    done
  '';

  # GPU module. The DRM card index depends on probe order. simpledrm can
  # claim card0 at boot and push the real GPU to card1. Use the first card
  # that reports a busy percentage instead of a fixed index. With no such
  # card the script prints nothing and waybar hides the module. Rows the
  # driver doesn't report are left out.
  gpuStatus = pkgs.writeShellScript "waybar-gpu" ''
    export PATH=${statPath}
    ${barHelpers}

    card=
    for f in /sys/class/drm/card*/device/gpu_busy_percent; do
      if [ -r "$f" ]; then
        card=''${f%/gpu_busy_percent}
        break
      fi
    done
    [ -n "$card" ] || exit 0
    name=$(lspci -mm -s "$(basename "$(readlink -f "$card")")" | awk -F'"' '{ print $6 }')
    hwmon=$(echo $card/hwmon/hwmon*)

    sensor() {
      [ -r "$hwmon/$1" ] && awk -v v="$(cat "$hwmon/$1")" -v d="$2" -v f="$3" 'BEGIN { printf f, v / d }'
    }
    pair() {
      [ -r "$card/$1" ] && echo "$(iec $(cat "$card/$1")) / $(iec $(cat "$card/$2"))"
    }

    while :; do
      busy=$(cat $card/gpu_busy_percent)
      tooltip=$(
        [ -n "$name" ] && row Model "$name"
        row Load "$busy%"
        v=$(sensor freq1_input 1000000 "%d MHz") && row Clock "$v"
        v=$(sensor temp1_input 1000 "%d °C") && row Temp "$v"
        v=$(sensor power1_input 1000000 "%.1f W") && row Power "$v"
        v=$(pair mem_info_vram_used mem_info_vram_total) && row VRAM "$v"
        v=$(pair mem_info_gtt_used mem_info_gtt_total) && row GTT "$v"
      )
      emit "GPU $busy%" "$tooltip"
      sleep 2
    done
  '';

  # Shared by the volume and mic modules. Each script puts pulseaudio and
  # jq on its PATH.
  #   device sinks|sources NAME  "DESCRIPTION|PORT|VOLUME|MUTED" for one
  #                              sink or source
  audioHelpers = ''
    device() {
      pactl -f json list "$1" | jq -r --arg n "$2" '.[] | select(.name == $n)
        | [.description,
           ((.active_port as $p | .ports[] | select(.name == $p) | .description) // ""),
           (.volume | to_entries[0].value.value_percent | rtrimstr("%")),
           (.mute | tostring)]
        | join("|")'
    }
  '';

  # Volume module. It redraws on PulseAudio events instead of polling, so
  # a volume key shows up at once. The tooltip covers the default output
  # and every app playing sound. The mic has its own module beside the
  # clock.
  volumeStatus = pkgs.writeShellScript "waybar-volume" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.pulseaudio
        pkgs.jq
        pkgs.coreutils
        pkgs.gawk
      ]
    }
    ${barHelpers}
    ${audioHelpers}

    show() {
      IFS='|' read -r out port vol muted < <(device sinks "$(pactl get-default-sink)")
      tooltip=$(
        row Output "$out"
        [ -n "$port" ] && row Port "$port"
        row Volume "$vol%$([ "$muted" = true ] && echo ", muted")"
        pactl -f json list sink-inputs \
          | jq -r '.[] | [(.properties["application.name"] // "?"), (.volume | to_entries[0].value.value_percent)] | @tsv' \
          | {
              label=Playing
              while IFS=$'\t' read -r app v; do
                row "$label" "$(cell "$app") $v"
                label=
              done
            }
      )
      if [ "$muted" = true ]; then
        emit Muted "$tooltip" muted
      else
        emit "Vol $vol%" "$tooltip"
      fi
    }

    # pactl subscribe ends if the sound server restarts. Start over then.
    while :; do
      show
      pactl subscribe | while read -r line; do
        case "$line" in
          *"on sink #"* | *"on sink-input #"* | *"on server"*) show ;;
        esac
      done
      sleep 1
    done
  '';

  # Mic module, shown beside the clock (micBarConfig). It always shows the
  # default mic: "Mic ON" when live, "Mic OFF" when muted. The tooltip names
  # the mic, its level and the apps recording from a mic. Speaker monitors
  # don't count as recording, and neither do pavucontrol's level meters
  # ("Peak detect" streams). Like the volume module, it redraws on
  # PulseAudio events.
  micStatus = pkgs.writeShellScript "waybar-mic" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.pulseaudio
        pkgs.jq
        pkgs.coreutils
        pkgs.gawk
      ]
    }
    ${barHelpers}
    ${audioHelpers}

    # One app name per stream recording from a mic.
    listeners() {
      jq -rn --argjson sources "$(pactl -f json list sources)" \
        --argjson outputs "$(pactl -f json list source-outputs)" '
        ($sources | map(select(.name | endswith(".monitor") | not) | .index)) as $mics
        | $outputs[]
        | select(.properties["media.name"] != "Peak detect")
        | select(.source as $s | $mics | index($s))
        | .properties["application.name"] // "?"'
    }

    show() {
      IFS='|' read -r name port level muted < <(device sources "$(pactl get-default-source)")
      apps=$(listeners)
      tooltip=$(
        row Input "$name"
        [ -n "$port" ] && row Port "$port"
        row Level "$level%$([ "$muted" = true ] && echo ", muted")"
        label=Listening
        while read -r app; do
          [ -n "$app" ] || continue
          row "$label" "$app"
          label=
        done <<< "$apps"
      )
      if [ "$muted" = true ]; then
        emit "Mic OFF" "$tooltip" off
      else
        emit "Mic ON" "$tooltip" on
      fi
    }

    while :; do
      show
      pactl subscribe | while read -r line; do
        case "$line" in
          *"on source #"* | *"on source-output #"* | *"on server"*) show ;;
        esac
      done
      sleep 1
    done
  '';

  # Nix logo at the left end of the bar. The tooltip names the running
  # NixOS release and the system generation. `nixos-rebuild test` doesn't
  # add a generation, so the tooltip says so when the running system isn't
  # the newest one.
  nixStatus = pkgs.writeShellScript "waybar-nix" ''
    export PATH=${statPath}
    ${barHelpers}

    while :; do
      link=$(readlink /nix/var/nix/profiles/system)
      gen=''${link#system-}
      gen=''${gen%-link}
      built=$(date -d "@$(stat -c %Y /nix/var/nix/profiles/$link)" '+%F %H:%M')
      tooltip=$(
        row NixOS "$(cat /run/current-system/nixos-version)"
        if [ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ]; then
          row Generation "$gen, built $built"
        else
          row Generation "a test build, newer than $gen"
        fi
        row Kernel "$(uname -r)"
      )
      emit "" "$tooltip"
      sleep 30
    done
  '';

  # Battery module. Batteries report either energy (µWh) or charge (µAh),
  # so power and the time left come out in the units it uses. The classes
  # match waybar's battery states: warning at 25% and critical at 10%.
  batteryStatus = pkgs.writeShellScript "waybar-battery" ''
    export PATH=${statPath}
    ${barHelpers}

    bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1)
    [ -n "$bat" ] || exit 0

    get() {
      cat "$bat/$1" 2>/dev/null
    }

    while :; do
      capacity=$(get capacity) status=$(get status)
      if [ -n "$(get energy_full)" ]; then
        now=$(get energy_now) full=$(get energy_full) design=$(get energy_full_design)
        draw=$(get power_now)
        unit=Wh
      else
        now=$(get charge_now) full=$(get charge_full) design=$(get charge_full_design)
        draw=$(get current_now)
        unit=mAh
      fi
      volts=$(get voltage_now)

      tooltip=$(
        row Status "$status"
        if [ "$unit" = Wh ]; then
          row Charge "$(awk -v n=$now -v f=$full 'BEGIN { printf "%.1f / %.1f Wh", n / 1e6, f / 1e6 }')"
          watts=$(awk -v p=$draw 'BEGIN { printf "%.1f", p / 1e6 }')
        else
          row Charge "$((now / 1000)) / $((full / 1000)) mAh"
          watts=$(awk -v i=$draw -v v=$volts 'BEGIN { printf "%.1f", i * v / 1e12 }')
        fi
        [ "''${design:-0}" -gt 0 ] && row Health "$((full * 100 / design))%"
        [ "''${draw:-0}" -gt 0 ] && row Power "$watts W"
        case "$status" in
          Discharging) left=$now ;;
          Charging) left=$((full - now)) ;;
          *) left= ;;
        esac
        if [ -n "$left" ] && [ "''${draw:-0}" -gt 0 ]; then
          mins=$((left * 60 / draw))
          row "$([ "$status" = Charging ] && echo "To full" || echo "To empty")" "$((mins / 60))h $((mins % 60))m"
        fi
        [ "$(get cycle_count)" -gt 0 ] 2>/dev/null && row Cycles "$(get cycle_count)"
        row Model "$(get manufacturer) $(get model_name) ($(get technology))"
      )
      class=
      if [ "$capacity" -le 10 ]; then
        class=critical
      elif [ "$capacity" -le 25 ]; then
        class=warning
      fi
      emit "Bat $capacity%" "$tooltip" "$class"
      sleep 5
    done
  '';
in
{
  home.packages = with pkgs; [
    wl-clipboard
    grim
    slurp
    libnotify
    # Wrapped to run with the tty theme below.
    pavucontrol
    noto-fonts
    noto-fonts-color-emoji
    nerd-fonts.dejavu-sans-mono
    uni-vga
  ];
  xdg.dataFile."themes/tty/gtk-4.0/gtk.css".source = gtkTty.css;
  # The recording timer shows on screen only. Screen captures, including
  # recordings and screenshots, draw a black box over it instead.
  #
  # The bars beside the clock share the main bar's layer, where the surface
  # mapped last draws on top. Waybar remaps the main bar on every reload,
  # which would cover them. Hyprland draws a layer's surfaces in
  # descending order, so -1 keeps them above the main bar.
  wayland.windowManager.hyprland.extraConfig = ''
    hl.layer_rule({ name = "recording-timer-private", match = { namespace = "^waybar-recording$" }, no_screen_share = true })
    hl.layer_rule({ name = "beside-clock-above-bar", match = { namespace = "^waybar-(mic|recording)$" }, order = -1 })
  '';
  programs = {
    foot = {
      enable = true;
      settings.main = {
        font = "VGA:size=11";
        pad = "2x2";
      };
    };
    fuzzel = {
      enable = true;
      settings = {
        main = {
          font = "VGA:size=11";
          # Same aspect ratio as the screen (1920x1080 = 16:9), at roughly
          # the same screen coverage the original default (width=30,
          # lines=15) had — not fullscreen. Solved empirically against this
          # exact font/size (VGA:size=11 renders a fixed 12x26px cell, plus
          # fuzzel's own default padding/border): width=42, lines=11 ->
          # 588x332px (ratio 1.77, vs. screen's 1.78; area within 1% of the
          # original 444x436px). Padding/anchor left at fuzzel's own
          # defaults (center, hpad=40, vpad=8) — only width/lines changed.
          width = 42;
          lines = 11;
        };
        colors = {
          background = "20242cff";
          text = "ffffffff";
          match = "ff0000ff";
          selection = "ffffffff";
          selection-text = "20242cff";
          selection-match = "ff0000ff";
          border = "ffffffff";
        };
        border = {
          width = 2;
          radius = 0;
        };
      };
    };

    waybar = {
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
        modules-center = [ "clock" ];
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
        clock = {
          format = "{:%a %d %b  %H:%M}";
          tooltip-format = "{:%F}";
        };
        "custom/cpu" = {
          exec = "${cpuStatus}";
          return-type = "json";
        };
        # The stat scripts run for the bar's whole lifetime and print one
        # JSON line per update, like the network module.
        "custom/memory" = {
          exec = "${memoryStatus}";
          return-type = "json";
        };
        "custom/swap" = {
          exec = "${swapStatus}";
          return-type = "json";
        };
        "custom/disk" = {
          exec = "${diskStatus}";
          return-type = "json";
        };
        "custom/gpu" = {
          exec = "${gpuStatus}";
          return-type = "json";
        };
        "custom/network" = {
          exec = "${networkStatus}";
          return-type = "json";
        };
        "custom/volume" = {
          exec = "${volumeStatus}";
          return-type = "json";
          on-click = "${pavucontrol}/bin/pavucontrol";
        };
        "custom/battery" = {
          exec = "${batteryStatus}";
          return-type = "json";
        };
        "custom/nix" = {
          exec = "${nixStatus}";
          return-type = "json";
        };
      };

      style = ''
        * { font-family: "VGA", monospace; font-size: 13px; }
        window#waybar { background: #20242c; color: #eceff4; border-bottom: 2px solid #ffffff; border-radius: 0; }
        #clock, #custom-cpu, #custom-memory, #custom-swap, #custom-disk, #custom-gpu, #custom-network, #custom-volume, #custom-battery { padding: 0 10px; }
        #workspaces button { color: #eceff4; padding: 0 7px; border-radius: 0; }
        #workspaces button.active { background: #eceff4; color: #20242c; border-radius: 0; }
        /* System stats: one distinct hue per stat, consistent with common
           system-monitor conventions (cpu/mem/disk/gpu each get their own
           color). Red stays reserved for alert states only. */
        #custom-cpu { color: #5fd7ff; }
        #custom-memory { color: #c792ea; }
        /* Swap is a dimmer shade of the RAM hue, which marks the two as
           related. */
        #custom-swap { color: #9d8fbf; }
        #custom-disk { color: #e5c07b; }
        #custom-gpu { color: #7ee787; }
        #custom-battery.critical { color: #ff0000; }
        /* The same 2px white rule as every border in the rice, between the
           text stats and the tray icons. Icons need less room than text,
           so the tray keeps only a few px on each side. */
        #tray { border-left: 2px solid #ffffff; padding: 0 4px; }
        /* VGA has no Nix logo, so it comes from the Nerd Font, in the light
           blue of the NixOS logo. The Propo variant gives the icon its full
           width. The plain one squeezes it into a text cell and clips it.
           The glyph sits 1px low in its own box, so 2px of bottom padding
           centres it on the workspace numbers. */
        #custom-nix { font-family: "DejaVuSansM Nerd Font Propo"; font-size: 20px; color: #7ebae4; padding: 0 6px 2px 6px; }
        ${tooltipStyle}
        /* Tray right-click menus (each app's own menu, rendered by waybar
           through this same stylesheet) styled as fuzzel: opaque fill, 2px
           white border, square corners, 11pt, and the hovered row in
           reverse video like fuzzel's selection. */
        menu { background: #20242c; border: 2px solid #ffffff; border-radius: 0; box-shadow: none; padding: 0; }
        .popup decoration { border-radius: 0; box-shadow: none; }
        menu menuitem { background: transparent; color: #ffffff; border-radius: 0; padding: 4px 12px; }
        menu menuitem label { font-size: 11pt; }
        menu menuitem:hover { background: #ffffff; color: #20242c; }
        menu menuitem:disabled { color: #6c7380; }
        menu separator { background: #ffffff; min-height: 2px; margin: 2px 0; }
      '';
    };
  };
  services = {
    # Runs the daemon and its tray icon. Pair the phone again from it: this
    # machine is a new device to KDE Connect.
    kdeconnect = {
      enable = true;
      indicator = true;
    };
    mako = {
      enable = true;
      settings = {
        border-size = 2;
        border-radius = 0;
        border-color = "#ffffffff";
        background-color = "#20242cff";
        text-color = "#ffffffff";
        font = "VGA 11";
        width = 320;
        margin = "8";
        padding = "8";
        # Auto-dismiss after 5s. Critical alerts are the one exception —
        # 0 means "never auto-dismiss", consistent with red already being
        # reserved here for things that need to be acted on, not glanced at.
        default-timeout = 5000;
        "urgency=critical" = {
          border-color = "#ff0000ff";
          text-color = "#ff0000ff";
          default-timeout = 0;
        };
      };
    };
    polkit-gnome.enable = true;
    hypridle = {
      enable = true;
      settings = {
        general = {
          # ly-lock reads ly's config, so the lock screen matches the login
          # screen. The NixOS module (programs.ly-lock) installs it.
          lock_cmd = "${osConfig.programs.ly-lock.package}/bin/ly-lock";
          before_sleep_cmd = "${pkgs.systemd}/bin/loginctl lock-session";
        };
        listener = [
          {
            timeout = 600;
            on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
          }
        ];
      };
    };
  };

  systemd.user.services = {
    # The config and style are passed as store paths, so changing either one
    # changes this unit and home-manager restarts the bar on activation.
    waybar-special = {
      Unit = {
        Description = "Special-workspace bar";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        # The watcher's PartOf carries a *stop* of this unit over to it, but
        # nothing carries a *start* back — and home-manager applies config
        # changes as stop + start, which left the watcher dead after an
        # activation (confirmed live). Wants= closes that gap.
        Wants = [ "special-bar-watcher.service" ];
      };
      Service = {
        ExecStart = "${config.programs.waybar.package}/bin/waybar -c ${specialBarConfig} -s ${specialBarStyle}";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    waybar-mic = {
      Unit = {
        Description = "Mic indicator bar";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${config.programs.waybar.package}/bin/waybar -c ${micBarConfig} -s ${micBarStyle}";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Started and stopped by the recorder, so nothing pulls it in at login.
    waybar-recording = {
      Unit = {
        Description = "Recording timer bar";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${config.programs.waybar.package}/bin/waybar -c ${recordingBarConfig} -s ${recordingBarStyle}";
        Restart = "on-failure";
      };
    };

    # PartOf the bar: whenever the bar restarts (and so comes back hidden),
    # the watcher restarts with it and re-syncs to what's actually on screen.
    special-bar-watcher = {
      Unit = {
        Description = "Show/hide the special-workspace bar from Hyprland IPC events";
        Requires = [ "waybar-special.service" ];
        # graphical-session.target must be listed here even though
        # waybar-special already orders after it. Without it, the target's
        # WantedBy implicitly orders itself *after* this unit, closing the
        # loop target -> watcher -> waybar-special -> target. On boot systemd
        # broke that loop by dropping this watcher (so the bar never showed).
        # On shutdown it couldn't break it, so `uwsm stop` failed and
        # reboot/poweroff/logout hung (both confirmed in the journal).
        After = [
          "waybar-special.service"
          "graphical-session.target"
        ];
        PartOf = [
          "waybar-special.service"
          "graphical-session.target"
        ];
      };
      Service = {
        ExecStart = "${specialBarWatcher}";
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    power-watcher = {
      Unit = {
        Description = "Charger plug and unplug toasts";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${powerWatcher}";
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}

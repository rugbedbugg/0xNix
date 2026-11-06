# The scripts behind the main bar's modules and the small bars beside the
# clock, plus the power watcher. Each one runs for the bar's whole lifetime and
# prints one waybar JSON line per update, apart from the watcher, which sends
# toasts.
{
  pkgs,
  osConfig,
  palette,
}:
let
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
              cmd=$({ tr '\0' '\n' < /proc/$pid/cmdline; } 2>/dev/null | head -n1)
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
      if [ -z "$vol" ]; then
        pending=1
        emit "Vol --" "No output device"
        return
      fi
      pending=
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

    # The bar can start before the sound server does. Subscribing first and
    # drawing from inside the reader means no event in between gets lost. A
    # lookup that finds no output prints "Vol --" and is retried every
    # second until it does. The loop also starts over when pactl subscribe
    # ends, which it does if the sound server restarts.
    while :; do
      pactl subscribe | {
        pending=
        show
        while :; do
          if read -r -t 1 line; then
            case "$line" in
              *"on sink #"* | *"on sink-input #"* | *"on server"*) show ;;
            esac
          elif [ $? -gt 128 ]; then
            [ -n "$pending" ] && show
          else
            break
          fi
        done
      }
      sleep 1
    done
  '';

  # Mic module, shown beside the clock (micBarConfig in
  # waybar-side-bars.nix). It always shows the
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
      if [ -z "$level" ]; then
        pending=1
        emit "Mic --" "No input device"
        return
      fi
      pending=
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

    # Starts up like the volume module: subscribe first, then draw, and
    # retry every second while there is no input.
    while :; do
      pactl subscribe | {
        pending=
        show
        while :; do
          if read -r -t 1 line; then
            case "$line" in
              *"on source #"* | *"on source-output #"* | *"on server"*) show ;;
            esac
          elif [ $? -gt 128 ]; then
            [ -n "$pending" ] && show
          else
            break
          fi
        done
      }
      sleep 1
    done
  '';

  # Camera module, shown beside the clock (camBarConfig in
  # waybar-side-bars.nix). "Cam ON" means a
  # program has a camera node open, "Cam OFF" means none does. The tooltip
  # names the camera and the programs using it, which are found by scanning
  # /proc for open /dev/video file descriptors. Only the user's own
  # processes are visible that way, which covers every app in this session.
  # Opening or closing a node wakes the loop through inotify, and the 3s
  # timeout catches a node that appears later, like a USB camera plugged in.
  # Output is printed only when it changes, since waybar redraws on every
  # line.
  camStatus = pkgs.writeShellScript "waybar-cam" ''
    export PATH=${statPath}:${pkgs.inotify-tools}/bin
    ${barHelpers}

    # One program name per process holding a camera node open.
    users() {
      find /proc/[0-9]*/fd -lname '/dev/video*' 2>/dev/null \
        | awk -F/ '!seen[$3]++ { print $3 }' \
        | while read -r pid; do
            cat /proc/$pid/comm 2>/dev/null
          done \
        | sort -u
    }

    show() {
      apps=$(users)
      tooltip=$(
        label=Camera
        for name in /sys/class/video4linux/*/name; do
          [ -r "$name" ] && cat "$name"
        done | sort -u | while read -r cam; do
          row "$label" "$cam"
          label=
        done
        label=Using
        while read -r app; do
          [ -n "$app" ] || continue
          row "$label" "$app"
          label=
        done <<< "$apps"
      )
      if [ -n "$apps" ]; then
        emit "Cam ON" "$tooltip" on
      else
        emit "Cam OFF" "$tooltip" off
      fi
    }

    last=
    while :; do
      out=$(show)
      if [ "$out" != "$last" ]; then
        echo "$out"
        last=$out
      fi
      inotifywait -qq -t 3 -e open -e close /dev/video* 2>/dev/null || sleep 1
      sleep 0.2
    done
  '';

  # Clock module in the middle of the bar. The text is the plain date and
  # time. The tooltip lists the date, ISO week, day of the year, quarter,
  # UNIX epoch, UTC time and zone, then the month calendar beside them and a
  # dot-matrix world map under both, with a marker on the current location.
  #
  # The location comes from ipinfo.io, once an hour at most, and is kept in
  # the runtime directory. It is the address the network shows to the
  # internet, so it follows a VPN exit. A failed lookup is not retried for
  # 5 minutes. With no answer yet the tooltip says "unknown" and the map has
  # no marker.
  #
  # world-map.txt is a 71x36 grid of land cells from the dotted-map library
  # (the map in the portfolio site), where "+" is land. This script projects
  # a position onto it the way the library does: Mercator, with the
  # library's own extent for a map of this size. A marker that lands on
  # water snaps to the mainland cell nearest to it. Two grid rows fold into
  # one line of text with ":", "'" and "." so the map stays in the bar's
  # VGA font, which has no block characters.
  #
  # The calendar is cal's month with its day columns spread to 32
  # characters, so it fills the space beside the info rows. The tooltip
  # text carries four control characters that become Pango spans after
  # escaping: the marker (1 and 2) and today in the calendar (3 and 4). LC_CTYPE is UTF-8 so a city name with accents pads right.
  clockStatus = pkgs.writeShellScript "waybar-clock" ''
    export PATH=${statPath}:${pkgs.curl}/bin
    export LC_CTYPE=C.UTF-8
    ${barHelpers}

    cache=''${XDG_RUNTIME_DIR:-/tmp}/waybar-location.json
    tried=$cache.tried

    fetch() {
      touch "$tried"
      tmp=$(mktemp)
      if curl -fsS -m 10 https://ipinfo.io/json -o "$tmp" 2>/dev/null \
        && jq -e '.loc' "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$cache"
      else
        rm -f "$tmp"
      fi
    }

    # worldmap LAT LON  the map as 18 lines. Without a position, no marker.
    worldmap() {
      awk -v lat="$1" -v lon="$2" '
        BEGIN {
          W = 71; H = 36; R = 6378137; pi = atan2(0, -1)
          xmin = -18701674.453269962; xrange = 37403348.906539924
          ymax = 11361819.887676764; yrange = 18884783.128941886
          radius = 4
        }
        { for (c = 1; c <= W; c++) land[NR - 1, c - 1] = (substr($0, c, 1) == "+") }
        END {
          mr = -1
          if (lat != "" && lon != "") {
            phi = lat * pi / 180
            px = R * lon * pi / 180
            py = R * log(sin(pi / 4 + phi / 2) / cos(pi / 4 + phi / 2))
            tc = int(W * (px - xmin) / xrange + 0.5)
            tr = int(H * (ymax - py) / yrange + 0.5)
            best = -1e9; fb = 1e9
            for (r = 0; r < H; r++) for (c = 0; c < W; c++) {
              if (!land[r, c]) continue
              d = (r - tr) ^ 2 + (c - tc) ^ 2
              if (d < fb) { fb = d; fr = r; fc = c }
              if (d <= radius * radius) {
                n = 0
                for (dr = -1; dr <= 1; dr++) for (dc = -1; dc <= 1; dc++)
                  if ((dr || dc) && land[r + dr, c + dc]) n++
                s = n - d / 100
                if (s > best) { best = s; br = r; bc = c }
              }
            }
            if (best > -1e9) { mr = br; mc = bc } else if (fb < 1e9) { mr = fr; mc = fc }
          }
          for (r = 0; r < H; r += 2) {
            line = ""
            for (c = 0; c < W; c++) {
              t = land[r, c]; b = land[r + 1, c]
              g = t ? (b ? ":" : "\047") : (b ? "." : " ")
              if (mr >= 0 && c == mc && (r == mr || r + 1 == mr)) g = "\001@\002"
              line = line g
            }
            print line
          }
        }' ${./world-map.txt}
    }

    tick=0
    loc_stamp=none
    last_ymd=
    while :; do
      if [ $((tick % 60)) -eq 0 ] \
        && [ -z "$(find "$cache" -mmin -60 2>/dev/null)" ] \
        && [ -z "$(find "$tried" -mmin -5 2>/dev/null)" ]; then
        fetch &
      fi
      tick=$((tick + 1))

      stamp=$(stat -c %Y "$cache" 2>/dev/null)
      if [ "$stamp" != "$loc_stamp" ]; then
        loc_stamp=$stamp
        city= country= lat= lon=
        if [ -r "$cache" ]; then
          IFS='|' read -r city country lat lon < <(
            jq -r '[.city, .country, (.loc | split(",")[0]), (.loc | split(",")[1])] | join("|")' "$cache"
          )
        fi
        map=$(worldmap "$lat" "$lon")
      fi

      IFS='|' read -r text dayname ymd isoweek yday mon epoch zone isoyear year < <(
        date '+%a %d %b  %H:%M|%A|%F|%V|%-j|%-m|%s|%Z %:z|%G|%Y'
      )
      if [ "$ymd" != "$last_ymd" ]; then
        last_ymd=$ymd
        # Dec 28 always falls in the last ISO week of its year.
        weeks=$(date -d "$isoyear-12-28" +%V)
        ydays=$(date -d "$year-12-31" +%-j)
        calendar=$(cal -m | awk -v today="$((10#''${ymd##*-}))" '
          NR == 1 { gsub(/^ +| +$/, ""); printf "%*s\n", int((32 + length($0)) / 2), $0; next }
          {
            out = ""
            for (i = 0; i < 7; i++) {
              cell = substr($0, i * 3 + 1, 2)
              if (NR > 2 && cell ~ /[0-9]/ && cell + 0 == today) cell = "\003" cell "\004"
              out = out (i ? "   " : "") cell
            }
            print out
          }')
      fi

      info=$(
        row Date "$dayname $ymd"
        row Week "$((10#$isoweek)) of $((10#$weeks))"
        row Day "$yday of $ydays ($((yday * 100 / ydays))%)"
        row Quarter "Q$(((mon - 1) / 3 + 1))"
        row Epoch "$epoch"
        row UTC "$(date -u +%H:%M:%S)"
        row Zone "$zone"
        if [ -n "$lat" ]; then
          row Location "$city, $country"
          row Coords "$lat, $lon"
        else
          row Location unknown
        fi
      )
      tooltip=$(
        awk -v pad=36 'NR == FNR { l[FNR] = $0; n = FNR; next } { r[FNR] = $0; m = FNR }
          END { for (i = 1; i <= (n > m ? n : m); i++) printf "%-*s%s\n", pad, l[i], r[i] }' \
          <(echo "$info") <(echo "$calendar")
        echo
        echo "$map"
      )
      jq -cn --arg text "$text" --arg tooltip "$tooltip" \
        --arg mark "${palette.alert}" --arg bg "${palette.text}" --arg fg "${palette.surface}" '{
          text: $text,
          tooltip: ($tooltip | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")
            | gsub("\u0001"; "<span foreground=\"" + $mark + "\">") | gsub("\u0002"; "</span>")
            | gsub("\u0003"; "<span background=\"" + $bg + "\" foreground=\"" + $fg + "\">") | gsub("\u0004"; "</span>")),
          class: ""
        }'
      sleep 1
    done
  '';

  # Nix logo at the left end of the bar. The tooltip names the running
  # NixOS release, the nixpkgs and flake commits behind it, the Nix version
  # and the system generation. `nixos-rebuild test` doesn't add a
  # generation, so the tooltip says so when the running system isn't the
  # newest one. The Built against row reads system.configurationRevision
  # (flake.nix).
  nixStatus = pkgs.writeShellScript "waybar-nix" ''
    export PATH=${statPath}
    ${barHelpers}

    # "Built against" is 13 characters, longer than the shared 10-character
    # label column, so this tooltip pads to 13.
    row() {
      printf '%-13s %s\n' "$1" "$2"
    }

    while :; do
      link=$(readlink /nix/var/nix/profiles/system)
      gen=''${link#system-}
      gen=''${gen%-link}
      built=$(date -d "@$(stat -c %Y /nix/var/nix/profiles/$link)" '+%F %H:%M')
      version=$(cat /run/current-system/nixos-version)
      pkgsrev=''${version##*.}
      pkgsdate=''${version%.*}
      pkgsdate=''${pkgsdate##*.}
      config=$(/run/current-system/sw/bin/nixos-version --json | jq -r '.configurationRevision // empty')
      up=$(${pkgs.procps}/bin/uptime -p)
      tooltip=$(
        row NixOS "$version"
        if [[ $pkgsdate =~ ^[0-9]{8}$ ]]; then
          row Nixpkgs "$pkgsrev (''${pkgsdate:0:4}-''${pkgsdate:4:2}-''${pkgsdate:6:2})"
        fi
        row Nix "$(${osConfig.nix.package}/bin/nix --version | awk '{ print $NF }')"
        if [ -n "$config" ]; then
          row "Built against" "''${config:0:7}"
        else
          row "Built against" unknown
        fi
        if [ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ]; then
          row Generation "$gen, built $built"
        else
          row Generation "Test build >> Gen $gen"
        fi
        row Saved "$(ls -d /nix/var/nix/profiles/system-*-link | wc -l) generations"
        row Kernel "$(uname -r)"
        row Uptime "''${up#up }"
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
  inherit
    networkStatus
    powerWatcher
    cpuStatus
    memoryStatus
    swapStatus
    diskStatus
    gpuStatus
    volumeStatus
    micStatus
    camStatus
    clockStatus
    nixStatus
    batteryStatus
    ;
}

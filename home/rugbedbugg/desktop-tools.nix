{
  config,
  osConfig,
  pkgs,
  ...
}:
let
  # Special-workspace bar: a second, separate waybar process that sits on
  # the top-left corner of the floating special-workspace terminals
  # (keybinds.nix). Those windows are pinned at (152, 101), size 1616x909,
  # and Hyprland draws their 2px border *outside* that box — so the frame's
  # outer top-left corner is (150, 99). This 28px-tall bar occupies y 73-101
  # starting at x 150: its left edge is flush with the window border, and
  # its own 2px bottom border lands on the window's top border rows.
  #
  # Geometry, both confirmed by measuring the layer surface live:
  # - margin-top counts from below the main bar's 32px exclusive zone, not
  #   from the screen edge, so 73 - 32 = 41.
  # - No `width`: with position=top, an explicit width makes waybar drop the
  #   left/right anchors (bar.cpp setPosition), which centers the bar and
  #   silently ignores margin-left. Anchored on both sides instead, the
  #   margins set the box: 150 from the left, 1920 - 150 - 400 = 1370 from
  #   the right, for a 400px-wide bar.
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
      height = 28;
      margin-top = 41;
      margin-left = 150;
      margin-right = 1370;
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

    rate() {
      awk -v b="$1" 'BEGIN {
        split("B/s kB/s MB/s GB/s", u, " "); i = 1
        while (b >= 1000 && i < 4) { b /= 1000; i++ }
        printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i]
      }'
    }

    emit() {
      jq -cn --arg text "$1" --arg tooltip "$2" --arg class "$3" \
        '{text: $text, tooltip: ($tooltip | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")), class: $class}'
    }

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
in
{
  home.packages = with pkgs; [
    wl-clipboard
    grim
    slurp
    libnotify
    pavucontrol
    noto-fonts
    noto-fonts-color-emoji
    nerd-fonts.dejavu-sans-mono
    uni-vga
  ];
  programs = {
    firefox.enable = true;
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
        modules-left = [ "hyprland/workspaces" ];
        modules-center = [ "clock" ];
        modules-right = [
          "cpu"
          "memory"
          "memory#swap"
          "disk"
          "custom/gpu"
          "custom/network"
          "pulseaudio"
          "battery"
          "tray"
        ];
        clock = {
          format = "{:%a %d %b  %H:%M}";
          tooltip-format = "{:%F}";
        };
        cpu = {
          format = "CPU {usage}%";
          interval = 2;
        };
        memory = {
          format = "RAM {percentage}%";
          tooltip-format = "{used:0.1f} / {total:0.1f} GiB";
          interval = 5;
        };
        "memory#swap" = {
          format = "Swap {swapPercentage}%";
          # Without its own tooltip-format this module falls back to the
          # memory module's default tooltip, which shows RAM used.
          tooltip-format = "{swapUsed:0.1f} / {swapTotal:0.1f} GiB";
          interval = 5;
        };
        disk = {
          path = "/";
          format = "Disk {percentage_used}%";
          interval = 30;
        };
        "custom/gpu" = {
          exec = "${pkgs.coreutils}/bin/cat /sys/class/drm/card1/device/gpu_busy_percent";
          format = "GPU {}%";
          interval = 2;
        };
        "custom/network" = {
          exec = "${networkStatus}";
          return-type = "json";
        };
        pulseaudio = {
          format = "Vol {volume}%";
          format-muted = "Muted";
          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
        };
        battery = {
          format = "Bat {capacity}%";
          states = {
            warning = 25;
            critical = 10;
          };
        };
      };

      style = ''
        * { font-family: "VGA", monospace; font-size: 13px; }
        window#waybar { background: #20242c; color: #eceff4; border-bottom: 2px solid #ffffff; border-radius: 0; }
        #clock, #cpu, #memory, #disk, #custom-gpu, #custom-network, #pulseaudio, #battery, #tray { padding: 0 10px; }
        #workspaces button { color: #eceff4; padding: 0 7px; border-radius: 0; }
        #workspaces button.active { background: #eceff4; color: #20242c; border-radius: 0; }
        /* System stats: one distinct hue per stat, consistent with common
           system-monitor conventions (cpu/mem/disk/gpu each get their own
           color). Red stays reserved for alert states only. */
        #cpu { color: #5fd7ff; }
        #memory { color: #c792ea; }
        /* Swap is the same module type as RAM (#memory, id class .swap):
           a dimmer shade of the same hue marks them as related. */
        #memory.swap { color: #9d8fbf; }
        #disk { color: #e5c07b; }
        #custom-gpu { color: #7ee787; }
        #battery.critical { color: #ff0000; }
        /* Tooltips styled as mako toasts: opaque fill, 2px white border,
           square corners, 8px padding, same font and size. The GTK theme
           otherwise gives them a translucent, rounded, shadowed box. */
        tooltip, tooltip.background { background: #20242c; border: 2px solid #ffffff; border-radius: 0; box-shadow: none; opacity: 1; }
        tooltip label { color: #ffffff; font-size: 11pt; padding: 8px; }
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

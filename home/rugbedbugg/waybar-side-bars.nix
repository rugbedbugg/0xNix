# The small waybar processes that sit beside the main bar: the label bar for
# the special workspaces, and the camera, mic and recording indicators around
# the clock. Each is its own layer surface and its own service, so a layer
# rule can single one out and a service can start and stop it.
{
  config,
  osConfig,
  pkgs,
  vars,
  palette,
  ...
}:
let
  geometry = import ./overlay-geometry.nix { inherit (vars) screen; };
  screenrec = import ./screenrec.nix { inherit config pkgs; };
  scripts = import ./status-scripts.nix { inherit pkgs osConfig palette; };
  tooltipStyle = import ./tooltip-style.nix { inherit palette; };

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
    #workspaces { background: ${palette.surface}; border: 2px solid ${palette.border}; }
    #workspaces button { color: ${palette.text}; background: transparent; padding: 0 7px; border: none; border-radius: 0; font-weight: normal; }
    #workspaces button.active, #workspaces button.visible { background: ${palette.text}; color: ${palette.surface}; }
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
    {
      name,
      left,
      width,
    }:
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

  # Width of the camera bar, with room for 7 characters ("Cam OFF") plus
  # 10px padding on each side. It always shows, so the recording bar
  # leaves its slot free.
  camWidth = 7 * clockSlot.cell + 20;

  # Recording timer bar: a waybar process that shows screenrec.nix's
  # "REC m:ss" while a recording runs. It's its own layer surface, named
  # waybar-recording, so the no_screen_share layer rule below can keep it
  # out of screen captures. Recordings and screenshots get a black box
  # there instead of the elapsed time.
  #
  # It sits flush against the camera bar's left edge and the text grows
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
          left = clockSlot.left - camWidth - width;
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
    #custom-recording { color: ${palette.alert}; padding: 0 10px; }
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
            exec = "${scripts.micStatus}";
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
    #custom-mic.on { color: ${palette.alert}; }
    #custom-mic.off { color: ${palette.outline}; }
  '';

  # Camera bar: the mic bar's twin on the clock's left. Its text grows
  # leftwards from the clock, with room for 7 characters ("Cam OFF"). It
  # always shows, so the bar always runs.
  camBarConfig = pkgs.writeText "waybar-cam-config.json" (
    builtins.toJSON (
      besideClock {
        name = "waybar-cam";
        left = clockSlot.left - camWidth;
        width = camWidth;
      }
      // {
        modules-right = [ "custom/cam" ];
        "custom/cam" = {
          exec = "${scripts.camStatus}";
          return-type = "json";
        };
      }
    )
  );

  # Same colours as the mic: red while a program has the camera open and
  # grey while nothing does.
  camBarStyle = pkgs.writeText "waybar-cam-style.css" ''
    ${besideClockStyle}
    #custom-cam { padding: 0 10px; }
    #custom-cam.on { color: ${palette.alert}; }
    #custom-cam.off { color: ${palette.outline}; }
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
in
{
  # The recording timer shows on screen only. Screen captures, including
  # recordings and screenshots, draw a black box over it instead.
  #
  # The bars beside the clock share the main bar's layer, where the surface
  # mapped last draws on top. Waybar remaps the main bar on every reload,
  # which would cover them. Hyprland draws a layer's surfaces in
  # descending order, so -1 keeps them above the main bar.
  wayland.windowManager.hyprland.extraConfig = ''
    hl.layer_rule({ name = "recording-timer-private", match = { namespace = "^waybar-recording$" }, no_screen_share = true })
    hl.layer_rule({ name = "beside-clock-above-bar", match = { namespace = "^waybar-(mic|cam|recording)$" }, order = -1 })
  '';

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

    waybar-cam = {
      Unit = {
        Description = "Camera indicator bar";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${config.programs.waybar.package}/bin/waybar -c ${camBarConfig} -s ${camBarStyle}";
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
  };
}

{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  vars,
  ...
}:
let
  geometry = import ./overlay-geometry.nix { inherit (vars) screen; };
  screenrec = import ./screenrec.nix { inherit config pkgs; };
  gtkTty = import ./gtk-tty.nix { inherit pkgs; };
  # uwsm-app asks uwsm's resident app daemon for the launch command, which
  # takes ~30ms. `uwsm app` starts a Python process for every launch and
  # takes ~125ms.
  app = cmd: "${pkgs.uwsm}/bin/uwsm-app -- ${cmd}";
  # Frequently updated packages installed with `nix profile`.
  profileBin = "${config.home.homeDirectory}/.nix-profile/bin";
  notify = "${pkgs.mako}/bin/makoctl";
  media = "${pkgs.playerctl}/bin/playerctl";

  # Full screen or a slurp region, opened in satty to crop and annotate.
  # Nothing lands on disk or the clipboard until it's asked for there.
  # satty doesn't create the save directory itself.
  screenshotDir = "${config.xdg.userDirs.pictures}/Screenshots";
  screenshot = pkgs.writeShellScript "screenshot" ''
    ${pkgs.coreutils}/bin/mkdir -p "${screenshotDir}"
    if [ "$1" = region ]; then
      geometry=$(${pkgs.slurp}/bin/slurp) || exit 0
      set -- -g "$geometry"
    else
      set --
    fi
    ${pkgs.grim}/bin/grim "$@" - | ${app "${config.programs.satty.package}/bin/satty --filename -"}
  '';

  # Bare Super toggles the launcher: close it if it's already open,
  # otherwise open it. fuzzel enforces single-instance via its own lock
  # file, so pkill-ing a running instance is the correct "close" action.
  toggleLauncher = pkgs.writeShellScript "toggle-launcher" ''
    if ${pkgs.procps}/bin/pkill -x fuzzel; then
      exit 0
    fi
    ${app "${pkgs.fuzzel}/bin/fuzzel"}
  '';

  # SUPER + / cheat sheet, read live from Hyprland so it can't drift from
  # the real config: every bind with a `description` (hyprland.nix and the
  # binds below), in config order. Modifiers are decoded from modmask
  # (SHIFT=1, CTRL=4, ALT=8, SUPER=64). The 1-0 workspace binds collapse to
  # one row per action, and rows that come out identical are dropped.
  # Display only; picking a row just closes it. Toggles like the launcher.
  #
  # Media keys show as the laptop key that sends them. On this Vivobook Go
  # E1404FA the F-row is in function mode, so the media keys need Fn.
  # Fn + F1 to F5 send mute, volume down and up, and brightness down and
  # up. Fn + F9 sends mic mute.
  cheatsheet = pkgs.writeShellScript "keybind-cheatsheet" ''
    if ${pkgs.procps}/bin/pkill -x fuzzel; then
      exit 0
    fi
    ${pkgs.hyprland}/bin/hyprctl binds -j | ${pkgs.jq}/bin/jq -r '
      def mods: . as $m
        | [ {b: 64, n: "SUPER"}, {b: 4, n: "CTRL"}, {b: 8, n: "ALT"}, {b: 1, n: "SHIFT"} ]
        | map(select(($m / .b | floor) % 2 == 1) | .n);
      def keyname: {
          "SUPER_L": "(tap)", "slash": "/", "RETURN": "Enter", "Escape": "Esc",
          "mouse:272": "Left drag", "mouse:273": "Right drag",
          "XF86AudioMute": "Fn + F1", "XF86AudioLowerVolume": "Fn + F2",
          "XF86AudioRaiseVolume": "Fn + F3", "XF86MonBrightnessDown": "Fn + F4",
          "XF86MonBrightnessUp": "Fn + F5", "XF86AudioMicMute": "Fn + F9"
        }[.] // .;
      map(select(.has_description))
      | map(
          (.key | test("^[0-9]$")) as $ws
          | {
              keys: ((.modmask | mods) + [ if $ws then "1-0" else (.key | keyname) end ] | join(" + ")),
              desc: (if $ws then .description | sub("workspace [0-9]+"; "workspace 1-10") else .description end)
            })
      | reduce .[] as $r ([]; if any(.[]; . == $r) then . else . + [$r] end)
      | (map(.keys | length) | max) as $w
      | .[] | .keys + (" " * ($w - (.keys | length) + 2)) + .desc
    ' | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt "Keys: " --width 72 --lines 20 >/dev/null
  '';

  # Ctrl + Alt + Delete session menu: fuzzel in its usual style, sized to
  # its entries instead of the launcher's full size, with no prompt line.
  # 13 columns fit "Shutdown now?". The padding around the highlight stays
  # at fuzzel's defaults, the same as the launcher.
  # Arrow keys move the selection, Enter runs it and Esc closes. Only the
  # listed entries can be picked. Logout, Reboot and Shutdown ask first,
  # with the question above No and Yes and No selected.
  sessionMenu = pkgs.writeShellScript "session-menu-run" ''
    menu() {
      lines=$1
      shift
      ${pkgs.fuzzel}/bin/fuzzel --dmenu --only-match --no-sort --hide-prompt \
        --width 13 --lines "$lines" "$@"
    }
    confirm() {
      [ "$(printf 'No\nYes\n' | menu 2 --mesg "$1 now?")" = Yes ]
    }
    choice=$(printf '%s\n' Lock Logout Suspend Reboot Shutdown | menu 5) || exit 0
    case "$choice" in
      Lock) ${pkgs.systemd}/bin/loginctl lock-session ;;
      Logout) confirm Logout && ${pkgs.uwsm}/bin/uwsm stop ;;
      Suspend) ${pkgs.systemd}/bin/systemctl suspend ;;
      Reboot) confirm Reboot && ${pkgs.systemd}/bin/systemctl reboot ;;
      Shutdown) confirm Shutdown && ${pkgs.systemd}/bin/systemctl poweroff ;;
    esac
  '';

  # A second press closes an open menu instead of stacking another one.
  # Like the launcher toggle, this closes any open fuzzel.
  session = pkgs.writeShellScript "session-menu" ''
    if ${pkgs.procps}/bin/pkill -x fuzzel; then
      exit 0
    fi
    ${app "${sessionMenu}"}
  '';

  # Special-workspace toggle: if a window with the given
  # class already exists, just toggle the special workspace's visibility;
  # otherwise launch the app first (the matching window_rule below silently
  # assigns it into that special workspace as soon as it opens) and then
  # toggle. `hyprctl dispatch` on this lua-configured Hyprland build only
  # accepts Lua-expression syntax, not the classic "dispatcher args" form
  # — confirmed live ("dispatch in lua is a shorthand for hl.dispatch(...),
  # your syntax might need to be updated"); `hl.dsp.workspace.toggle_special`
  # is the confirmed-working call. The label bar above the window is driven
  # entirely by Hyprland's own IPC events (desktop-tools.nix), not by this
  # script — so it stays correct however the workspace gets hidden.
  #
  # Whenever this shows the workspace, the app's window also gets keyboard
  # focus: the window rule's `silent` keeps a freshly launched one from
  # taking it, so the script waits for the window to map (up to 10s — a
  # cold Vesktop start is slow) and focuses it by address. It re-checks the
  # workspace is still shown first, so hiding it again mid-wait isn't undone.
  mkSpecialToggle =
    {
      class,
      workspace,
      launchCmd,
    }:
    pkgs.writeShellScript "toggle-special-${workspace}" ''
      hyprctl=${pkgs.hyprland}/bin/hyprctl
      jq=${pkgs.jq}/bin/jq
      window() {
        $hyprctl clients -j | $jq -r --arg c "${class}" 'first(.[] | select(.class == $c) | .address) // empty'
      }
      shown() {
        [ "$($hyprctl monitors -j | $jq -r '.[] | select(.focused) | .specialWorkspace.name')" = "special:${workspace}" ]
      }

      if [ -z "$(window)" ]; then
        ( ${launchCmd} ) &
      fi
      $hyprctl dispatch 'hl.dsp.workspace.toggle_special("${workspace}")' >/dev/null
      shown || exit 0

      for _ in $(${pkgs.coreutils}/bin/seq 100); do
        address=$(window)
        [ -n "$address" ] && break
        ${pkgs.coreutils}/bin/sleep 0.1
      done
      if [ -n "$address" ] && shown; then
        $hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null
      fi
    '';

  # foot's --app-id sets the Wayland app-id Hyprland reports as `class` —
  # confirmed live — so a TUI app running inside foot can still be matched
  # by its own distinct class instead of foot's generic one.
  footAs = appId: cmd: "${pkgs.foot}/bin/foot --app-id=${appId} ${cmd}";

  toggleMusic = mkSpecialToggle {
    class = "rmpc-special";
    workspace = "music";
    launchCmd = app (footAs "rmpc-special" "${pkgs-unstable.rmpc}/bin/rmpc");
  };

  toggleBtop = mkSpecialToggle {
    class = "btop-special";
    workspace = "btop";
    # --force-utf: btop refuses to start at all ("ERROR: No UTF-8 locale
    # detected!") because the system locale is LANG=en_IN with no .UTF-8
    # suffix. The flag unblocks btop alone and leaves the system locale
    # untouched.
    launchCmd = app (footAs "btop-special" "${pkgs-unstable.btop}/bin/btop --force-utf");
  };

  # A plain floating terminal, with the same treatment as music/btop.
  toggleGeneral = mkSpecialToggle {
    class = "general-special";
    workspace = "general";
    launchCmd = app (footAs "general-special" "");
  };

  # File manager overlay: lf (files.nix) in foot. Quitting lf closes the
  # window, so the next SUPER + E starts a fresh one.
  toggleFiles = mkSpecialToggle {
    class = "lf-special";
    workspace = "files";
    launchCmd = app (footAs "lf-special" "${config.programs.lf.package}/bin/lf");
  };

  # Discord via Vesktop, from the user profile (the flake's `apps` package)
  # so it updates without a rebuild. Its Wayland app-id is "vesktop",
  # confirmed live. Gets the same floating overlay as the terminals below.
  toggleDiscord = mkSpecialToggle {
    class = "vesktop";
    workspace = "discord";
    launchCmd = app "${profileBin}/vesktop";
  };

  # WhatsApp via ZapFast, also from the user profile. Its Wayland app-id is
  # "zapfast", confirmed live with `hyprctl clients` when the keyring screen
  # was up. Closing its window leaves the app in the system tray with no
  # window of its own, so the toggle's "is it running" check finds nothing
  # and launches it again. That second launch only asks the running instance
  # to show its window, and the wait below still catches it once it maps.
  toggleWhatsApp = mkSpecialToggle {
    class = "zapfast";
    workspace = "whatsapp";
    launchCmd = app "${profileBin}/zapfast";
  };

  # YouTube via youtube-tui in foot, from the user profile. Videos it opens
  # play in mpv, which youtube-tui starts with MPV_HOME pointing here instead
  # of ~/.config/mpv. The player window then reports its own app-id, and the
  # window rules below float it over the list. mpv started anywhere else
  # keeps the plain "mpv" app-id.
  youtubeMpv = pkgs.writeTextDir "mpv.conf" ''
    wayland-app-id=youtube-player
  '';

  toggleYouTube = mkSpecialToggle {
    class = "youtube-special";
    workspace = "youtube";
    launchCmd = app (
      footAs "youtube-special" "${pkgs.coreutils}/bin/env MPV_HOME=${youtubeMpv} ${profileBin}/youtube-tui"
    );
  };
in
{
  # Desktop binds on top of hyprland.nix's core set, using the plain desktop
  # tools (fuzzel, mako, waybar, grim/slurp).
  config = {
    home.packages = [ pkgs.playerctl ];

    # Enter saves and closes, Ctrl+C copies and Ctrl+S saves. Neither runs
    # on its own. Square corners match the rest of the rice.
    programs.satty = {
      enable = true;
      # The tty theme (gtk-tty.nix), installed by desktop-tools.nix.
      package = gtkTty.wrap pkgs.satty "satty";
      settings = {
        general = {
          output-filename = "${screenshotDir}/%F_%H-%M-%S.png";
          copy-command = "${pkgs.wl-clipboard}/bin/wl-copy";
          actions-on-enter = [
            "save-to-file"
            "exit"
          ];
          actions-on-escape = [ "exit" ];
          corner-roundness = 0;
          no-window-decoration = true;
        };
        font.family = "VGA";
        # Waybar's stat hues, with red first since it's the usual markup
        # colour. Keys 1 to 6 pick them in this order.
        color-palette.palette = [
          "#ff0000"
          "#e5c07b"
          "#5fd7ff"
          "#7ee787"
          "#c792ea"
          "#ffffff"
        ];
      };
    };

    wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
      for _, direction in ipairs({"left", "right", "up", "down"}) do
        hl.bind("SUPER + SHIFT + " .. direction, hl.dsp.window.move({ direction = direction }), { description = "Move window " .. direction })
      end

      -- Special-workspace window assignment: whenever these apps open (via
      -- their dedicated toggle keybinds below), they land silently in their
      -- own special workspace instead of the tiling layout.
      hl.window_rule({ name = "rmpc-special-ws", match = { class = "^rmpc-special$" }, workspace = "special:music silent" })
      hl.window_rule({ name = "btop-special-ws", match = { class = "^btop-special$" }, workspace = "special:btop silent" })
      hl.window_rule({ name = "general-special-ws", match = { class = "^general-special$" }, workspace = "special:general silent" })
      hl.window_rule({ name = "lf-special-ws", match = { class = "^lf-special$" }, workspace = "special:files silent" })
      hl.window_rule({ name = "discord-special-ws", match = { class = "^vesktop$" }, workspace = "special:discord silent" })
      hl.window_rule({ name = "zapfast-special-ws", match = { class = "^zapfast$" }, workspace = "special:whatsapp silent" })
      hl.window_rule({ name = "youtube-special-ws", match = { class = "^youtube-special$" }, workspace = "special:youtube silent" })
      -- Not silent: the list is on screen when it starts a video, so the
      -- player takes focus there.
      hl.window_rule({ name = "youtube-player-ws", match = { class = "^youtube-player$" }, workspace = "special:youtube" })

      -- Floating, centered, fuzzel-styled overlays for every special
      -- workspace, Vesktop and ZapFast included. Size and position come from
      -- overlay-geometry.nix, which also places the special-workspace
      -- label bar in desktop-tools.nix. The lf file chooser (files.nix)
      -- and the satty screenshot editor get the same frame but open on
      -- whatever workspace is in front.
      for _, cls in ipairs({"rmpc-special", "btop-special", "general-special", "lf-special", "vesktop", "zapfast", "youtube-special", "youtube-player", "filechooser", "com\\.gabm\\.satty"}) do
        hl.window_rule({
          name = "float-style-" .. cls,
          match = { class = "^" .. cls .. "$" },
          float = true,
          size = "${toString geometry.width} ${toString geometry.height}",
          move = "${toString geometry.x} ${toString geometry.y}",
          rounding = 0,
          border_size = 2,
          border_color = "rgba(ffffffee)",
        })
      end

      hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd("${toggleLauncher}"), { release = true, description = "App launcher" })
      hl.bind("SUPER + slash", hl.dsp.exec_cmd("${cheatsheet}"), { description = "This keybind list" })
      hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("${session}"), { description = "Session menu" })
      hl.bind("SUPER + N", hl.dsp.exec_cmd("${notify} restore"), { description = "Restore last notification" })
      hl.bind("CTRL + ALT + C", hl.dsp.exec_cmd("${notify} dismiss --all"), { locked = true, description = "Clear notifications" })
      hl.bind("SUPER + L", hl.dsp.exec_cmd("${pkgs.systemd}/bin/loginctl lock-session"), { description = "Lock screen" })

      hl.bind("Print", hl.dsp.exec_cmd("${screenshot}"), { description = "Screenshot" })
      hl.bind("SUPER + R", hl.dsp.exec_cmd("${screenrec.toggle} full"), { description = "Record screen (again to stop)" })
      hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("${screenrec.toggle} region"), { description = "Record region (again to stop)" })
      hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("${screenshot} region"), { description = "Screenshot region" })

      -- The laptop has no media keys, but headset buttons send these. They
      -- have no description, so the SUPER + / list leaves them out.
      hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("${media} play-pause"), { locked = true })
      hl.bind("XF86AudioNext", hl.dsp.exec_cmd("${media} next"), { locked = true })
      hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("${media} previous"), { locked = true })
      hl.bind("XF86AudioStop", hl.dsp.exec_cmd("${media} stop"), { locked = true })

      hl.bind("SUPER + T", hl.dsp.exec_cmd("${app "${pkgs.foot}/bin/foot"}"), { description = "Terminal" })
      hl.bind("SUPER + B", hl.dsp.exec_cmd("${app "${profileBin}/microsoft-edge-stable"}"), { description = "Browser" })
      hl.bind("SUPER + C", hl.dsp.exec_cmd("${app "${pkgs.foot}/bin/foot ${config.programs.vim.package}/bin/vim"}"), { description = "Editor (vim)" })
      hl.bind("SUPER + O", hl.dsp.exec_cmd("${app "${pkgs.libreoffice-fresh}/bin/libreoffice"}"), { description = "Office (LibreOffice)" })
      hl.bind("CTRL + ALT + V", hl.dsp.exec_cmd("${app "${gtkTty.wrap pkgs.pavucontrol "pavucontrol"}/bin/pavucontrol"}"), { description = "Volume mixer" })

      -- Special workspaces (toggle visibility, launch on first use).
      hl.bind("SUPER + M", hl.dsp.exec_cmd("${toggleMusic}"), { description = "Music (rmpc)" })
      hl.bind("SUPER + D", hl.dsp.exec_cmd("${toggleDiscord}"), { description = "Discord (Vesktop)" })
      hl.bind("SUPER + W", hl.dsp.exec_cmd("${toggleWhatsApp}"), { description = "WhatsApp (ZapFast)" })
      hl.bind("SUPER + Y", hl.dsp.exec_cmd("${toggleYouTube}"), { description = "YouTube (youtube-tui)" })
      hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd("${toggleBtop}"), { description = "System monitor (btop)" })
      hl.bind("SUPER + S", hl.dsp.exec_cmd("${toggleGeneral}"), { description = "Scratch terminal" })
      hl.bind("SUPER + E", hl.dsp.exec_cmd("${toggleFiles}"), { description = "Files (lf)" })

      -- The bar is the only shell piece here, so it gets a restart shortcut of
      -- its own rather than riding on the session menu.
      hl.bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd("${pkgs.systemd}/bin/systemctl --user restart waybar.service"), { release = true, description = "Restart bar" })
      hl.bind("CTRL + SUPER + SHIFT + L", hl.dsp.exec_cmd("${pkgs.systemd}/bin/systemctl suspend"), { description = "Suspend" })
    '';
  };
}

{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  palette,
  ...
}:
let
  geometry = import ./overlay-geometry.nix { inherit (config.desktop) screen; };
  screenrec = import ./screenrec.nix { inherit config pkgs; };
  gtkTty = import ./gtk-tty.nix { inherit pkgs palette; };
  inherit (import ./special-toggle.nix { inherit pkgs palette; })
    app
    mkSpecialToggle
    toggleVolume
    ;
  # Where home.packages binaries land, for the apps that apps.nix installs.
  profileBin = "${config.home.profileDirectory}/bin";
  swaync = "${config.services.swaync.package}/bin/swaync-client";
  media = "${pkgs.playerctl}/bin/playerctl";

  # Full screen or a slurp region, opened in satty to crop and annotate.
  # Nothing lands on disk or the clipboard until it's asked for there.
  # satty doesn't create the save directory itself.
  screenshotDir = "${config.xdg.userDirs.pictures}/Screenshots";

  # Region screenshots, as a cycle on one key. The first press freezes the
  # screen with wayfreeze and starts the slurp picker over it. The second
  # press thaws the screen and leaves the picker up, so it is still clear
  # that a shot can be taken. The third press ends the picker, like Escape.
  # A lock file keeps a second picker from starting while one is up.
  #
  # The CRT shader (crt.nix) is part of every capture, so the frozen frame
  # already has the CRT look. Drawn under the shader, the layer would be bent
  # twice. So the shader is hidden as the screen freezes and for as long as
  # it stays frozen. It comes back before the layer goes away, so the live
  # screen never shows without it. The frozen layer looks the same as the
  # live screen and nothing blinks.
  # A shot is cut out of that frame, so it shows the CRT look like the
  # screen does. The crop reads the picker's coordinates as pixels, which
  # holds at a scale of 1. The picker's dim layer and the pointer are drawn
  # without the shader while it is hidden. Thawing shows the shader again, and
  # a shot taken after a thaw is a live capture, which has the CRT look too.
  # The shader is only touched if it was on at the start. wayfreeze runs its
  # after-freeze command through sh, so sh has to be on the script's PATH.
  #
  # slurp takes the pointer and the keyboard, so without the freeze waybar
  # closes a tooltip and an app closes a menu before the shot is taken. The
  # screen thaws as soon as the shot is on disk, and a cancelled selection
  # thaws it too. The shot goes through a file in the runtime directory
  # because the freeze has to end before satty opens. satty reads it from
  # stdin, so deleting the file afterwards is safe.
  crt = import ./crt-control.nix { inherit pkgs; };
  screenshotRegion = pkgs.writeShellScript "screenshot-region" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.procps
        pkgs.util-linux
        pkgs.netpbm
        pkgs.grim
        pkgs.slurp
        pkgs.wayfreeze
      ]
    }
    exec 9>"$XDG_RUNTIME_DIR/screenshot.lock"
    if ! flock -n 9; then
      if pgrep -x wayfreeze >/dev/null; then
        [ -e "$XDG_RUNTIME_DIR/screenshot.hidden" ] && ${crt.show}
        pkill -x wayfreeze
      else
        pkill -x slurp
      fi
      exit 0
    fi

    raw=$(mktemp "$XDG_RUNTIME_DIR/screenshot.XXXXXX.ppm")
    shot=$(mktemp "$XDG_RUNTIME_DIR/screenshot.XXXXXX.png")
    ready="$XDG_RUNTIME_DIR/screenshot.ready"
    hidden="$XDG_RUNTIME_DIR/screenshot.hidden"
    rm -f "$ready" "$hidden"
    cleanup() {
      [ -e "$hidden" ] && ${crt.show}
      pkill -x wayfreeze
      rm -f "$raw" "$shot" "$ready" "$hidden"
    }
    trap cleanup EXIT

    after="touch $ready"
    if ${crt.isOn}; then
      touch "$hidden"
      after="${crt.hide}; touch $ready"
    fi
    wayfreeze --after-freeze-cmd "$after" 9>&- &
    for _ in $(seq 40); do
      [ -e "$ready" ] && break
      sleep 0.05
    done
    grim -t ppm "$raw"

    geometry=$(slurp -b '#00000066' -c '#${palette.bare.border}ff' -s '#00000000' -w 2)
    if [ -n "$geometry" ]; then
      if pgrep -x wayfreeze >/dev/null; then
        read -r position size <<<"$geometry"
        IFS=, read -r x y <<<"$position"
        IFS=x read -r width height <<<"$size"
        pamcut -left "$x" -top "$y" -width "$width" -height "$height" "$raw" | pnmtopng >"$shot"
      else
        grim -g "$geometry" "$shot"
      fi
    fi
    [ -e "$hidden" ] && ${crt.show}
    rm -f "$hidden"
    pkill -x wayfreeze
    [ -s "$shot" ] && ${app "${config.programs.satty.package}/bin/satty --filename -"} <"$shot" 9>&-
  '';
  screenshot = pkgs.writeShellScript "screenshot" ''
    ${pkgs.coreutils}/bin/mkdir -p "${screenshotDir}"
    if [ "$1" = region ]; then
      exec ${screenshotRegion}
    fi
    ${pkgs.grim}/bin/grim - | ${app "${config.programs.satty.package}/bin/satty --filename -"}
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
          "XF86AudioMute": "Media key", "XF86AudioLowerVolume": "Media key",
          "XF86AudioRaiseVolume": "Media key", "XF86MonBrightnessDown": "Media key",
          "XF86MonBrightnessUp": "Media key", "XF86AudioMicMute": "Media key"
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
  # entirely by Hyprland's own IPC events (waybar-side-bars.nix), not by this
  # script — so it stays correct however the workspace gets hidden.
  #
  # Whenever this shows the workspace, the app's window also gets keyboard
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

  # Discord via Vesktop, from apps.nix. Its Wayland app-id is "vesktop",
  # confirmed live. Gets the same floating overlay as the terminals below.
  toggleDiscord = mkSpecialToggle {
    class = "vesktop";
    workspace = "discord";
    launchCmd = app "${profileBin}/vesktop";
  };

  # WhatsApp via ZapFast, also from apps.nix. Its Wayland app-id is
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

  # YouTube via youtube-tui in foot, from apps.nix. Videos it opens
  # play in mpv, which youtube-tui starts with MPV_HOME pointing here instead
  # of ~/.config/mpv. It gets the same theme (mpv-theme.nix), since the
  # config directory is not shared. The player window then reports its own
  # app-id, and the window rules below float it over the list. mpv started anywhere else
  # keeps the plain "mpv" app-id.
  mpvTheme = import ./mpv-theme.nix { inherit palette; };
  youtubeMpv = pkgs.symlinkJoin {
    name = "youtube-mpv";
    paths = [
      (pkgs.writeTextDir "mpv.conf" (
        mpvTheme.config
        + ''
          wayland-app-id=youtube-player
        ''
      ))
      (pkgs.writeTextDir "script-opts/osc.conf" mpvTheme.osc)
    ];
  };

  toggleYouTube = mkSpecialToggle {
    class = "youtube-special";
    workspace = "youtube";
    launchCmd = app (
      footAs "youtube-special" "${pkgs.coreutils}/bin/env MPV_HOME=${youtubeMpv} ${profileBin}/youtube-tui"
    );
  };
  # Apps that tile. Super + key opens one into the layout. Super + Alt + key
  # opens it floating (floating.nix): the first window of a matching class
  # that opens within a few seconds floats as a golden rectangle in
  # floating.lua. A pattern is a Lua pattern on the window class, and
  # LibreOffice opens each component under its own class.
  launches = [
    {
      key = "T";
      description = "Terminal";
      command = app "${pkgs.foot}/bin/foot";
      classes = [ "^foot$" ];
    }
    {
      key = "B";
      description = "Browser";
      command = app "${profileBin}/microsoft-edge-stable";
      classes = [ "^microsoft%-edge$" ];
    }
    {
      key = "C";
      description = "Editor (nvim)";
      command = app "${pkgs.foot}/bin/foot ${config.programs.neovim.finalPackage}/bin/nvim";
      classes = [ "^foot$" ];
    }
    {
      key = "O";
      description = "Office (LibreOffice)";
      command = app "${pkgs.libreoffice-fresh}/bin/libreoffice";
      classes = [ "^libreoffice" ];
    }
  ];
  luaList = items: "{ " + lib.concatMapStringsSep ", " (item: ''"${item}"'') items + " }";
  launchBinds = lib.concatMapStringsSep "\n" (launch: ''
    hl.bind("SUPER + ${launch.key}", hl.dsp.exec_cmd("${launch.command}"), { description = "${launch.description}" })
    hl.bind("SUPER + ALT + ${launch.key}", function() floating.launch(${luaList launch.classes}, "${launch.command}") end, { description = "${launch.description}, floating" })
  '') launches;
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
          palette.alert
          palette.disk
          palette.cpu
          palette.gpu
          palette.memory
          palette.border
        ];
      };
    };

    wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
      for _, direction in ipairs({"left", "right", "up", "down"}) do
        hl.bind("SUPER + SHIFT + " .. direction, function() floating.nudge(direction) end, { repeating = true, description = "Move window " .. direction })
      end

      -- Super + = and Super + - change the width. Adding Shift changes the
      -- height. The = key is the + key without Shift. A tiled window moves
      -- its split, and a floating window grows around its centre.
      for key, sign in pairs({ equal = 1, minus = -1 }) do
        local word = sign > 0 and "Grow" or "Shrink"
        hl.bind("SUPER + " .. key, hl.dsp.window.resize({ x = sign * 40, y = 0, relative = true }), { repeating = true, description = word .. " window width" })
        hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.resize({ x = 0, y = sign * 40, relative = true }), { repeating = true, description = word .. " window height" })
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
      hl.window_rule({ name = "volume-special-ws", match = { class = "^org\\.pulseaudio\\.pavucontrol$" }, workspace = "special:volume silent" })

      -- A new window opens on the focused workspace, which is the special
      -- one while an overlay is up. A foot from Super + T or a link opened
      -- from Vesktop would then tile behind the floating overlay. Such a
      -- window moves to the regular workspace in front instead and takes
      -- focus. The overlay closes by itself when the workspace changes. The
      -- toggle only runs if it is somehow still up, since toggling a closed
      -- one would open it again. Floating windows stay put. Every overlay
      -- app floats through the rules below, and so do the lf file chooser
      -- and the youtube-tui player, which have to open over the overlay
      -- they came from. The window's floating state and workspace are
      -- already set when the event fires (confirmed live).
      hl.on("window.open", function(w)
        if w.floating or not w.workspace or not w.workspace.special then return end
        local shown = hl.get_active_special_workspace()
        if not shown or shown.name ~= w.workspace.name then return end
        local target = hl.get_active_workspace()
        hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
        hl.dispatch(hl.dsp.window.move({ workspace = target.id }))
        shown = hl.get_active_special_workspace()
        if shown and shown.name == w.workspace.name then
          hl.dispatch(hl.dsp.workspace.toggle_special((shown.name:gsub("^special:", ""))))
        end
      end)

      -- Floating, centered, fuzzel-styled overlays for every special
      -- workspace, Vesktop and ZapFast included. Size and position come from
      -- overlay-geometry.nix, which also places the special-workspace
      -- label bar in waybar-side-bars.nix. The lf file chooser (files.nix)
      -- and the satty screenshot editor get the same frame but open on
      -- whatever workspace is in front.
      local overlay_classes = {"rmpc-special", "btop-special", "general-special", "lf-special", "vesktop", "zapfast", "youtube-special", "youtube-player", "org.pulseaudio.pavucontrol", "filechooser", "com.gabm.satty"}
      for _, cls in ipairs(overlay_classes) do
        hl.window_rule({
          name = "float-style-" .. cls,
          match = { class = "^" .. cls:gsub("%.", "\\.") .. "$" },
          float = true,
          size = "${toString geometry.width} ${toString geometry.height}",
          move = "${toString geometry.x} ${toString geometry.y}",
          rounding = 0,
          border_size = 2,
          border_color = "rgba(${palette.bare.border}ee)",
        })
      end

      -- A window keeps the frame it opened with, so a reload that changes the
      -- frame leaves the open overlays behind. This puts them in the new one,
      -- flush with the label bar again.
      hl.on("config.reloaded", function()
        local is_overlay = {}
        for _, cls in ipairs(overlay_classes) do is_overlay[cls] = true end
        for _, w in ipairs(hl.get_windows()) do
          if w.floating and is_overlay[w.class] then
            hl.dispatch(hl.dsp.window.resize({ window = "address:" .. w.address, x = ${toString geometry.width}, y = ${toString geometry.height} }))
            hl.dispatch(hl.dsp.window.move({ window = "address:" .. w.address, x = ${toString geometry.x}, y = ${toString geometry.y} }))
          end
        end
      end)

      hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd("${toggleLauncher}"), { release = true, description = "App launcher" })
      hl.bind("SUPER + slash", hl.dsp.exec_cmd("${cheatsheet}"), { description = "This keybind list" })
      hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("${session}"), { description = "Session menu" })
      hl.bind("SUPER + N", hl.dsp.exec_cmd("${swaync} --toggle-panel --skip-wait"), { description = "Notification center" })
      hl.bind("CTRL + ALT + C", hl.dsp.exec_cmd("${swaync} --close-all --skip-wait"), { locked = true, description = "Clear notifications" })
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

      ${launchBinds}
      hl.bind("CTRL + ALT + V", hl.dsp.exec_cmd("${toggleVolume}"), { description = "Volume mixer" })

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

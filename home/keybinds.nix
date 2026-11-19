{
  config,
  lib,
  pkgs,
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

  # SUPER + / cheat sheet, read live from Hyprland so it can't drift from
  # the real config: every bind with a `description` (hyprland.nix and the
  # binds below), in config order. Modifiers are decoded from modmask
  # (SHIFT=1, CTRL=4, ALT=8, SUPER=64). The 1-0 workspace binds collapse to
  # one row per action, and rows that come out identical are dropped.
  # Display only; picking a row just closes it. Toggles like the launcher.
  #
  # Resolve optional physical key labels from the consuming configuration.
  cheatsheet = pkgs.writeShellScript "keybind-cheatsheet" ''
    if ${pkgs.procps}/bin/pkill -x fuzzel; then
      exit 0
    fi
    ${pkgs.hyprland}/bin/hyprctl binds -j | ${pkgs.jq}/bin/jq -r --argjson keyNames ${lib.escapeShellArg (builtins.toJSON config.desktop.keyNames)} '
      def mods: . as $m
        | [ {b: 64, n: "SUPER"}, {b: 4, n: "CTRL"}, {b: 8, n: "ALT"}, {b: 1, n: "SHIFT"} ]
        | map(select(($m / .b | floor) % 2 == 1) | .n);
      def keyname: ({
          "SUPER_L": "(tap)", "slash": "/", "RETURN": "Enter", "Escape": "Esc",
          "mouse:272": "Left drag", "mouse:273": "Right drag"
        } + $keyNames)[.] // .;
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

  # Encode configurable strings as Lua values. Compare bindings in one
  # modifier order before generating the launchers and workspace rules.
  lua = lib.generators.toLua { };
  canonicalKey =
    key:
    let
      parts = lib.splitString " + " (lib.toUpper key);
      modifiers = lib.init parts;
    in
    lib.concatStringsSep " + " (
      lib.filter (modifier: lib.elem modifier modifiers) [
        "CTRL"
        "SUPER"
        "ALT"
        "SHIFT"
      ]
      ++ [ (lib.last parts) ]
    );
  reservedKeys = [
    "SUPER + Q"
    "SUPER + V"
    "SUPER + F"
    "SUPER + SHIFT + E"
    "SUPER + SUPER_L"
    "SUPER + slash"
    "CTRL + ALT + Delete"
    "SUPER + N"
    "CTRL + ALT + C"
    "SUPER + L"
    "Print"
    "SUPER + R"
    "SUPER + SHIFT + R"
    "SUPER + SHIFT + S"
    "CTRL + ALT + V"
    "CTRL + SUPER + SHIFT + R"
    "CTRL + SUPER + SHIFT + L"
    "SUPER + SHIFT + W"
    "SUPER + SHIFT + T"
    "XF86AudioPlay"
    "XF86AudioNext"
    "XF86AudioPrev"
    "XF86AudioStop"
    "XF86AudioRaiseVolume"
    "XF86AudioLowerVolume"
    "XF86AudioMute"
    "XF86AudioMicMute"
    "XF86MonBrightnessUp"
    "XF86MonBrightnessDown"
    "SUPER + equal"
    "SUPER + minus"
    "SUPER + SHIFT + equal"
    "SUPER + SHIFT + minus"
    "SUPER + mouse:272"
    "SUPER + mouse:273"
  ]
  ++
    lib.concatMap
      (direction: [
        "SUPER + ${direction}"
        "SUPER + SHIFT + ${direction}"
      ])
      [
        "left"
        "right"
        "up"
        "down"
      ]
  ++ lib.concatMap (number: [
    "SUPER + ${toString number}"
    "SUPER + ALT + ${toString number}"
  ]) (lib.range 0 9);
  launches = config.desktop.launches;
  overlays = config.desktop.overlays;
  overlayWindows = config.desktop.overlayWindows ++ [
    {
      class = "org.pulseaudio.pavucontrol";
      workspace = "volume";
      silent = true;
    }
    {
      class = "com.gabm.satty";
      workspace = null;
      silent = false;
    }
  ];
  overlayClasses = map (item: item.class) (overlays ++ overlayWindows);
  workspaceRules = lib.concatMapStringsSep "\n" (
    item:
    lib.optionalString (item.workspace != null) ''
      hl.window_rule(${
        lua {
          name = "${item.class}-ws";
          match.class = "^${lib.escapeRegex item.class}$";
          workspace = "special:${item.workspace}${lib.optionalString (item.silent or true) " silent"}";
        }
      })
    ''
  ) (overlays ++ overlayWindows);
  launchBinds = lib.concatMapStringsSep "\n" (
    launch:
    let
      command = lua (app launch.command);
    in
    ''
      hl.bind(${lua "SUPER + ${launch.key}"}, hl.dsp.exec_cmd(${command}), { description = ${lua launch.description} })
      hl.bind(${lua "SUPER + ALT + ${launch.key}"}, function() floating.launch(${lua launch.classes}, ${command}) end, { description = ${lua "${launch.description}, floating"} })
    ''
  ) launches;
  overlayBinds = lib.concatMapStringsSep "\n" (
    overlay:
    let
      toggle = mkSpecialToggle {
        inherit (overlay) class workspace;
        launchCmd = app overlay.command;
      };
    in
    ''
      hl.bind(${lua overlay.key}, hl.dsp.exec_cmd(${lua (toString toggle)}), { description = ${lua overlay.description} })
    ''
  ) overlays;
in
{
  # Desktop binds on top of hyprland.nix's core set, using the plain desktop
  # tools (fuzzel, mako, waybar, grim/slurp).
  config = {
    assertions = [
      {
        assertion = lib.length overlayClasses == lib.length (lib.unique overlayClasses);
        message = "Overlay window classes must be unique.";
      }
      {
        assertion =
          let
            names = map (item: item.workspace) overlays ++ [ "volume" ];
          in
          lib.length names == lib.length (lib.unique names);
        message = "Toggle workspace names must be unique.";
      }
      {
        assertion =
          let
            keys =
              lib.concatMap (item: [
                "SUPER + ${item.key}"
                "SUPER + ALT + ${item.key}"
              ]) launches
              ++ map (item: item.key) overlays
              ++ reservedKeys;
            normalized = map canonicalKey keys;
          in
          lib.length normalized == lib.length (lib.unique normalized);
        message = "Application bindings must be unique and must not replace reserved desktop shortcuts.";
      }
    ];
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
      ${workspaceRules}

      -- A new window opens on the focused workspace, which is the special
      -- one while an overlay is up. A foot from Super + T or a link opened
      -- from Vesktop would then tile behind the floating overlay. Such a
      -- window moves to the regular workspace in front instead and takes
      -- focus. The overlay closes by itself when the workspace changes. The
      -- toggle only runs if it is somehow still up, since toggling a closed
      -- one would open it again. Floating windows stay put. Every overlay
      -- app floats through the rules below. Companion overlay windows
      -- receive the same treatment. The floating state and workspace are
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
      -- workspace. Size and position come from
      -- overlay-geometry.nix, which also places the special-workspace
      -- label bar in waybar-side-bars.nix. Unassigned companions
      -- and the satty screenshot editor get the same frame but open on
      -- whatever workspace is in front.
      local overlay_classes = ${lua overlayClasses}
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
      ${overlayBinds}

      -- The bar is the only shell piece here, so it gets a restart shortcut of
      -- its own rather than riding on the session menu.
      hl.bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd("${pkgs.systemd}/bin/systemctl --user restart waybar.service"), { release = true, description = "Restart bar" })
      hl.bind("CTRL + SUPER + SHIFT + L", hl.dsp.exec_cmd("${pkgs.systemd}/bin/systemctl suspend"), { description = "Suspend" })
    '';
  };
}

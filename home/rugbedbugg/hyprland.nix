{ pkgs, ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    # NixOS owns the compositor and portals; UWSM owns the session lifecycle.
    package = null;
    portalPackage = null;
    systemd.enable = false;
    configType = "lua";
    settings = {
      monitor = {
        output = "";
        mode = "preferred";
        position = "auto";
        scale = 1;
      };
      config = {
        general = {
          gaps_in = 0;
          gaps_out = 0;
          border_size = 2;
          layout = "dwindle";
          col = {
            active_border = "rgba(ffffffee)";
            inactive_border = "rgba(44444499)";
          };
        };
        decoration = {
          rounding = 0;
          blur.enabled = false;
        };
        animations.enabled = false;
        input = {
          kb_layout = "us";
          follow_mouse = 1;
          touchpad = {
            natural_scroll = true;
            tap_to_click = true;
          };
        };
        misc = {
          disable_hyprland_logo = true;
          force_default_wallpaper = 0;
          # If ly-lock crashes the session stays locked. This lets a new
          # ly-lock take over the lock, started from a TTY with
          # `hyprctl --instance 0 dispatch exec ly-lock`.
          allow_session_lock_restore = true;
        };
        cursor = {
          # This AMD iGPU's hardware cursor plane goes stale and ignores
          # theme/image changes entirely — confirmed live via hyprctl before
          # declaring this. Forcing software rendering is the actual fix;
          # hyprcursor is also disabled since Vanilla-DMZ only ships the
          # plain Xcursor format anyway.
          no_hardware_cursors = true;
          enable_hyprcursor = false;
        };
        dwindle.preserve_split = true;
      };
    };
    # Lua syntax and dispatchers match the pinned Hyprland 0.55.4 example.
    # Every bind carries a `description`: the SUPER + / cheat sheet
    # (keybinds.nix) is built from `hyprctl binds -j`, and only lists binds
    # that have one.
    extraConfig = ''
      hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("uwsm app -- ${pkgs.foot}/bin/foot"), { description = "Terminal" })
      hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Close window" })
      hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
      hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Lock screen" })
      hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd("uwsm stop"), { description = "Log out" })

      for _, direction in ipairs({"left", "right", "up", "down"}) do
        hl.bind("SUPER + " .. direction, hl.dsp.focus({ direction = direction }), { description = "Focus " .. direction })
      end
      for i = 1, 10 do
        local key = i % 10
        hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = i }), { description = "Go to workspace " .. i })
        hl.bind("SUPER + ALT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Move window to workspace " .. i })
      end
      hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Drag window" })
      hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

      hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true, description = "Volume up" })
      hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true, description = "Volume down" })
      hl.bind("XF86AudioMute", hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, description = "Mute output" })
      hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, description = "Mute microphone" })
      hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("${pkgs.brightnessctl}/bin/brightnessctl set +5%"), { locked = true, repeating = true, description = "Brightness up" })
      hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("${pkgs.brightnessctl}/bin/brightnessctl --min-value=1 set 5%-"), { locked = true, repeating = true, description = "Brightness down" })
    '';
  };

  # Session environment is imported by UWSM before its graphical target starts.
  # home.pointerCursor's own session variables don't reach UWSM's separate
  # environment-loading mechanism, so the cursor theme has to be set here too
  # — without it Hyprland falls back to whatever generic theme (e.g. Breeze)
  # is on the system, ignoring home.pointerCursor entirely.
  xdg.configFile."uwsm/env".text = ''
    export XCURSOR_SIZE=24
    export XCURSOR_THEME=Vanilla-DMZ
    export HYPRCURSOR_THEME=Vanilla-DMZ
    export HYPRCURSOR_SIZE=24
    export NIXOS_OZONE_WL=1
  '';
}

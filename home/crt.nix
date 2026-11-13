# Runs crt.frag over the whole screen. The Konami code turns it off and on
# again, with a notification each time. The shader explains the look and
# crt-control.nix holds the commands that switch it.
#
# The code is up, up, down, down, left, right, left, right, b, a. The keys
# are bound without a modifier and still reach the window that has focus.
# The code only counts while no window has focus, such as on an empty
# workspace, so typing in an app never trips it. A pause of two seconds
# forgets the keys pressed so far.
#
# Without the code there is no other key. Running the toggle script from a
# terminal does the same, and so does a config reload, which turns the
# shader back on.
{ pkgs, ... }:
let
  crt = import ./crt-control.nix { inherit pkgs; };

  toggle = pkgs.writeShellScript "crt-toggle" ''
    if ${crt.isOn}; then
      ${crt.off}
      message="Deactivated overlay"
    else
      ${crt.on}
      message="Activated CRT overlay"
    fi
    ${pkgs.libnotify}/bin/notify-send -a CRT -t 2500 "$message"
  '';
in
{
  wayland.windowManager.hyprland = {
    settings.config = {
      decoration.screen_shader = crt.shader;
      debug = {
        vfr = false;
        damage_tracking = 0;
      };
    };
    extraConfig = ''
      local konami = { "up", "up", "down", "down", "left", "right", "left", "right", "b", "a" }
      local pressed = {}
      local presses = 0

      local function konami_key(key)
        presses = presses + 1
        local mine = presses
        hl.timer(function()
          if mine == presses then pressed = {} end
        end, { timeout = 2000, type = "oneshot" })
        if hl.get_active_window() then
          pressed = {}
          return
        end
        table.insert(pressed, key)
        if #pressed > #konami then table.remove(pressed, 1) end
        if #pressed == #konami then
          for i, expected in ipairs(konami) do
            if pressed[i] ~= expected then return end
          end
          pressed = {}
          hl.dispatch(hl.dsp.exec_cmd("${toggle}"))
        end
      end

      for _, key in ipairs({ "up", "down", "left", "right", "b", "a" }) do
        hl.bind(key, function() konami_key(key) end, { non_consuming = true })
      end
    '';
  };
}

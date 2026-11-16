# Launching and toggling the special-workspace windows. keybinds.nix binds
# one toggle per app. waybar.nix reuses the volume toggle for a click on the
# volume module.
{ pkgs, palette }:
let
  gtkTty = import ./gtk-tty.nix { inherit pkgs palette; };
  # uwsm-app asks uwsm's resident app daemon for the launch command, which
  # takes ~30ms. `uwsm app` starts a Python process for every launch and
  # takes ~125ms.
  app = cmd: "${pkgs.uwsm}/bin/uwsm-app -- ${pkgs.runtimeShell} -c ${pkgs.lib.escapeShellArg cmd}";

  # A toggle for the special workspace that holds one app's window. The
  # first press launches the app. Later presses show or hide the workspace.
  # On show, the script moves focus to the window: the window rule's
  # `silent` keeps a freshly launched one from taking it, so the script
  # waits for the window to map (up to 10s, since a cold Vesktop start is
  # slow) and focuses it by address. It re-checks the workspace is still
  # shown first, so hiding it again mid-wait isn't undone.
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
        $hyprctl clients -j | $jq -r --arg c ${pkgs.lib.escapeShellArg class} 'first(.[] | select(.class == $c) | .address) // empty'
      }
      shown() {
        [ "$($hyprctl monitors -j | $jq -r '.[] | select(.focused) | .specialWorkspace.name')" = ${pkgs.lib.escapeShellArg "special:${workspace}"} ]
      }

      if [ -z "$(window)" ]; then
        ( ${launchCmd} ) &
      fi
      $hyprctl dispatch ${pkgs.lib.escapeShellArg "hl.dsp.workspace.toggle_special(${pkgs.lib.generators.toLua { } workspace})"} >/dev/null
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

  # The volume mixer, in the rice's GTK theme. Its Wayland app-id is
  # org.pulseaudio.pavucontrol, the name of the application.
  toggleVolume = mkSpecialToggle {
    class = "org.pulseaudio.pavucontrol";
    workspace = "volume";
    launchCmd = app "${gtkTty.wrap pkgs.pavucontrol "pavucontrol"}/bin/pavucontrol";
  };
in
{
  inherit app mkSpecialToggle toggleVolume;
}

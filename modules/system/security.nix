{ pkgs-unstable, ... }:
let
  # Lynis discovers regular plugin files, so copy the bundled plugins alongside
  # the local one. The installed Lynis package stays unchanged.
  lynisPlugins = pkgs-unstable.runCommand "lynis-plugins" { } ''
    mkdir -p "$out"
    cp -r --no-preserve=mode ${pkgs-unstable.lynis}/share/lynis/plugins/. "$out/"
    cp ${./lynis-pam.sh} "$out/plugin_nixospam_phase1"
  '';
in
{
  # The engines follow unstable so they can update without moving the rest
  # of the system off its pinned package set.
  environment.systemPackages = with pkgs-unstable; [
    lynis
    yara
    file
    nftables
  ];

  environment.etc."lynis/custom.prf".text = builtins.readFile ./lynis.prf + ''
    plugin-dir=${lynisPlugins}
  '';

  # Keep signatures current independently of system rebuilds. Scans run
  # through clamscan on demand, without keeping an engine in memory.
  services.clamav = {
    package = pkgs-unstable.clamav;
    updater.enable = true;
    daemon.enable = false;
    scanner.enable = false;
    clamonacc.enable = false;
  };
}

{ pkgs-unstable, signature-base, ... }:
let
  # Lynis discovers regular plugin files, so copy the bundled plugins alongside
  # the local one. The installed Lynis package stays unchanged.
  lynisPlugins = pkgs-unstable.runCommand "lynis-plugins" { } ''
    mkdir -p "$out"
    cp -r --no-preserve=mode ${pkgs-unstable.lynis}/share/lynis/plugins/. "$out/"
    cp ${./lynis-pam.sh} "$out/plugin_nixospam_phase1"
  '';
  # The yara CLI takes a single rules file, so include every rule in the pinned
  # signature set from one index and compile it at build time. A rule that
  # fails to compile then fails the build instead of every later scan. Some
  # rules read external variables that only the THOR scanner fills in. Define
  # them as empty strings so the rules compile. Those rules match on content
  # alone.
  yaraRules = pkgs-unstable.runCommand "yara-rules" { nativeBuildInputs = [ pkgs-unstable.yara ]; } ''
    for f in ${signature-base}/yara/*.yar; do
      printf 'include "%s"\n' "$f"
    done > index.yar
    mkdir -p "$out"
    yarac -w \
      -d filename= -d filepath= -d extension= -d filetype= -d owner= \
      index.yar "$out/rules.yarc"
  '';
in
{
  # The engines follow unstable so they can update without moving the rest
  # of the system off its pinned package set.
  environment.systemPackages = with pkgs-unstable; [
    lynis
    yara
    (writeShellScriptBin "yara-scan" ''
      exec ${yara}/bin/yara -C -r -w /etc/yara/rules.yarc "$@"
    '')
    file
    nftables
  ];

  environment.etc."yara/rules.yarc".source = "${yaraRules}/rules.yarc";

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

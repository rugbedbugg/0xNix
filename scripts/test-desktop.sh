#!/usr/bin/env bash
# Runtime test of the exact prebuilt closure. Run as the user on tty2.
set -euo pipefail
umask 077

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
baseline=/nix/store/ngnfpwd270k8agjj8bbbyr3lnpdhkch4-nixos-system-nixos-26.05.11985.26f4107e47e3
target=/nix/store/604fi57fqsn6ym1wzpnq2ryka7wi3v89-nixos-system-nixos-26.05.20261015.26f4107
rebuild=/nix/store/bfmy3lkvwjd00pspa874jn4s7sbizv2d-nixos-rebuild-ng-26.05/bin/nixos-rebuild
python=/nix/store/jy00n3jp5xj8s40n1fbldmkcr5n7avxc-python3-3.13.15/bin/python3
find_bin=/nix/store/nl0wq6d4bpjrxmlax141liq0qr9z87gn-findutils-4.10.0/bin/find
sha_bin=/nix/store/bhv6xyvqw6gjs3j488gi1z6wdv18bdpa-coreutils-9.11/bin/sha256sum

if [[ $# != 0 || $EUID != 1000 || $(tty) != /dev/tty2 ]]; then
  printf 'Run as the desktop user from tty2 (Ctrl+Alt+F2), without arguments or an outer sudo.\n' >&2
  exit 1
fi

for pointer in /run/current-system /run/booted-system /nix/var/nix/profiles/system; do
  if [[ $(readlink -f "$pointer") != "$baseline" ]]; then
    printf 'Baseline changed: %s. Stop for review.\n' "$pointer" >&2
    exit 1
  fi
done
if [[ $(findmnt --mountpoint /boot -rn -o UUID) != D1D5-BFD8 ]]; then
  printf 'Unexpected EFI mount. Stop for review.\n' >&2
  exit 1
fi
"$sha_bin" --check <<'HASHES'
d4e3004a936af0834d80244d4bd6a34ca4bb90f0123981e139ee529a5f7af939  /etc/nixos/configuration.nix
f2259cfbb7793b365dc62171a9d527f163c58fe97db141d699563b38f7d5d11a  /etc/nixos/hardware-configuration.nix
HASHES

run_dir=$(mktemp -d "$repo/artifacts/runtime-test.XXXXXXXX")
exec > >(tee "$run_dir/activation.log") 2>&1
printf 'Runtime test records: %s\n' "$run_dir"
"$python" "$repo/scripts/prepare-runtime-test.py" "$run_dir"
printf 'SDDM may replace tty1. Return to this recovery terminal with Ctrl+Alt+F2.\n'
printf 'Authenticate locally for the already approved runtime test.\n'
sudo -v

snapshot_efi() {
  sudo "$find_bin" /boot -xdev -type f -exec "$sha_bin" -- '{}' + | LC_ALL=C sort
}
snapshot_efi >"$run_dir/efi-before.sha256"
readlink -f /run/booted-system /nix/var/nix/profiles/system >"$run_dir/boot-before.txt"

# --store-path uses the immutable build already validated; no flake update/build.
# The test action never selects the boot installer or updates the system profile.
status=0
sudo "$rebuild" test --store-path "$target" --no-reexec || status=$?
printf 'nixos-rebuild test exit status: %s\n' "$status"

# A console-only boot does not enter graphical.target when its configuration
# changes. Start it explicitly for this desktop test, without isolation.
if [[ $status == 0 ]]; then
  # A user bus inherited from the console generation needs its updated service
  # search paths before it can discover portals and Mako. Preserve the live bus.
  systemctl --user reload dbus.service || status=$?
  sudo /run/current-system/systemd/bin/systemctl start graphical.target || status=$?
fi

snapshot_efi >"$run_dir/efi-after.sha256"
readlink -f /run/booted-system /nix/var/nix/profiles/system >"$run_dir/boot-after.txt"
diff -u "$run_dir/efi-before.sha256" "$run_dir/efi-after.sha256" || status=1
diff -u "$run_dir/boot-before.txt" "$run_dir/boot-after.txt" || status=1
systemctl --failed --no-pager
systemctl --no-pager --full status display-manager.service home-manager-$USER.service || status=1
if [[ $(readlink -f /run/current-system) != "$target" ]]; then
  printf 'The requested system is not active.\n'
  status=1
fi
printf '%s\n' "$status" >"$run_dir/exit-status"
printf 'Review records in %s\n' "$run_dir"
printf 'Runtime recovery command: sudo /run/booted-system/bin/switch-to-configuration test\n'
printf 'System recovery does not remove Home Manager files; their prior state is in home-before.json and home-before.tar.\n'
exit "$status"

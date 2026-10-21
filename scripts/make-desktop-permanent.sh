#!/usr/bin/env bash
# One-time promotion of the already tested closure. Run as the desktop user.
# Output files intentionally belong to the invoking user, not root.
# shellcheck disable=SC2024
set -euo pipefail
umask 077

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
baseline=/nix/store/ngnfpwd270k8agjj8bbbyr3lnpdhkch4-nixos-system-nixos-26.05.11985.26f4107e47e3
target=/nix/store/604fi57fqsn6ym1wzpnq2ryka7wi3v89-nixos-system-nixos-26.05.20261015.26f4107
rebuild=/nix/store/bfmy3lkvwjd00pspa874jn4s7sbizv2d-nixos-rebuild-ng-26.05/bin/nixos-rebuild
python=/nix/store/jy00n3jp5xj8s40n1fbldmkcr5n7avxc-python3-3.13.15/bin/python3
find_bin=/nix/store/nl0wq6d4bpjrxmlax141liq0qr9z87gn-findutils-4.10.0/bin/find
sha_bin=/nix/store/bhv6xyvqw6gjs3j488gi1z6wdv18bdpa-coreutils-9.11/bin/sha256sum
tar_bin=/nix/store/rc7c5al4hdcv0dc42g1jabx2r68l45jq-gnutar-1.35/bin/tar
bootctl=/nix/store/kmzlca218j6j1ar292fxj7707qzypij8-systemd-260.5/bin/bootctl

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ $# == 0 && $EUID == 1000 && -t 0 ]] || die 'Run interactively as the desktop user, without arguments or an outer sudo.'
[[ $(readlink -f /run/current-system) == "$target" ]] || die 'The tested desktop is not active; stop for review.'
[[ $(readlink -f "$repo/result-system") == "$target" ]] || die 'The reviewed build changed; stop for review.'
for pointer in /run/booted-system /nix/var/nix/profiles/system; do
  [[ $(readlink -f "$pointer") == "$baseline" ]] || die "Baseline changed: $pointer. Stop for review."
done
generations=(/nix/var/nix/profiles/system-*-link)
[[ ${#generations[@]} == 1 && ${generations[0]} == /nix/var/nix/profiles/system-1-link ]] || die 'Unexpected system generations; stop for review.'
[[ ! -d /nix/var/nix/profiles/system-profiles ]] || die 'Additional system profiles need review.'
[[ $(findmnt --mountpoint /boot -rn -o UUID) == D1D5-BFD8 ]] || die 'Unexpected EFI mount.'
[[ ,$(findmnt --mountpoint /boot -rn -o OPTIONS), == *,rw,* ]] || die 'EFI is read-only; this helper will not remount it.'
"$sha_bin" --check <<'HASHES'
d4e3004a936af0834d80244d4bd6a34ca4bb90f0123981e139ee529a5f7af939  /etc/nixos/configuration.nix
f2259cfbb7793b365dc62171a9d527f163c58fe97db141d699563b38f7d5d11a  /etc/nixos/hardware-configuration.nix
HASHES

cat <<'PLAN'
This promotes the running, tested Hyprland build to generation 2:
  - Add /boot/loader/entries/nixos-generation-2.conf.
  - Change loader.conf default from generation 1 to generation 2.
  - Keep timeout 5 and console-mode keep; retain generation 1.
  - Add machine-ID metadata to generation 1; keep its original boot target.
  - Keep both Arch UKIs, shared EFI binaries, kernel/initrd and firmware boot variables unchanged.
No bootloader reinstall, partition operation, configuration edit or reboot is included.
The complete EFI tree will be backed up before the switch.
PLAN
read -r -p 'Approve these exact boot changes? Type SWITCH: ' approval
[[ $approval == SWITCH ]] || die 'Cancelled before permanent changes.'

run_dir=$(mktemp -d "$repo/artifacts/permanent-switch.XXXXXXXX")
exec > >(tee "$run_dir/activation.log") 2>&1
printf 'Records and EFI backup: %s\n' "$run_dir"
# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329
record_exit() {
  local result=$?
  printf '%s\n' "$result" >"$run_dir/exit-status"
  if ((result != 0)); then
    printf 'Stopped. Review records in %s before rebooting.\n' "$run_dir"
  fi
}
trap record_exit EXIT
sudo -v

snapshot_efi() {
  sudo "$find_bin" /boot -xdev -type f -exec "$sha_bin" -- '{}' + | LC_ALL=C sort
}
snapshot_firmware() {
  sudo "$find_bin" /sys/firmware/efi/efivars -maxdepth 1 -type f -name 'Boot*' -exec "$sha_bin" -- '{}' + | LC_ALL=C sort
}
snapshot_efi >"$run_dir/efi-before.sha256"
diff -u "$repo/artifacts/runtime-test.1b4o2h9c/efi-after.sha256" "$run_dir/efi-before.sha256"
snapshot_firmware >"$run_dir/firmware-before.sha256"
[[ -s $run_dir/firmware-before.sha256 ]] || die 'Firmware boot variables could not be inventoried.'
sudo "$bootctl" --esp-path=/boot status >"$run_dir/boot-status-before.txt"
# Matching binary bytes and version ensure the installer skips bootctl update.
sudo cmp "${bootctl%/bin/bootctl}/lib/systemd/boot/efi/systemd-bootx64.efi" /boot/EFI/systemd/systemd-bootx64.efi
sudo cmp /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI
grep -Eq '/EFI/(BOOT|systemd)/.*\.efi \(systemd-boot 260\.5\)' "$run_dir/boot-status-before.txt" || die 'Installed bootloader version needs review.'
for name in LoaderEntryDefault LoaderEntryOneShot; do
  sudo test ! -e "/sys/firmware/efi/efivars/$name-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f" || die 'An EFI variable overrides boot selection; stop for review.'
done

# Produce the exact entry contents from the immutable bootspecs, matching the
# pinned systemd-boot builder. The initial entry predates machine-ID creation.
"$python" - "$baseline" "$target" "$run_dir" <<'PY'
import datetime
import json
import pathlib
import sys

destination = pathlib.Path(sys.argv[3])
machine_id = pathlib.Path('/etc/machine-id').read_text().strip()
for generation, name in enumerate(sys.argv[1:3], 1):
    system = pathlib.Path(name)
    boot = json.loads((system / 'boot.json').read_text())['org.nixos.bootspec.v1']
    def efi_name(value):
        path = pathlib.Path(value).resolve()
        store_name = path.relative_to('/nix/store').parts[0]
        suffix = store_name if path.name == store_name else f'{store_name}-{path.name}'
        return f'/EFI/nixos/{suffix}.efi'
    build_date = datetime.datetime.fromtimestamp(system.stat().st_ctime).strftime('%F')
    content = (
        f'title NixOS\nsort-key nixos\n'
        f'version Generation {generation} {boot["label"]}, built on {build_date}\n'
        f'linux {efi_name(boot["kernel"])}\ninitrd {efi_name(boot["initrd"])}\n'
        f'options init={boot["init"]} {" ".join(boot["kernelParams"])}\n'
    )
    if generation == 1:
        (destination / 'nixos-generation-1.before.conf').write_text(content)
    (destination / f'nixos-generation-{generation}.conf').write_text(
        content + f'machine-id {machine_id}\n'
    )
PY
sudo cmp "$run_dir/nixos-generation-1.before.conf" /boot/loader/entries/nixos-generation-1.conf
printf 'timeout 5\ndefault nixos-generation-2.conf\nconsole-mode keep\n' >"$run_dir/loader.conf.expected"
sudo "$tar_bin" --one-file-system -C /boot -cf - . >"$run_dir/efi-before.tar"
"$tar_bin" -tf "$run_dir/efi-before.tar" >"$run_dir/efi-backup-files.txt"
"$sha_bin" "$run_dir/efi-before.tar" >"$run_dir/efi-backup.sha256"
# Recheck after the backup and immediately before the mutation.
snapshot_efi >"$run_dir/efi-recheck.sha256"
diff -u "$run_dir/efi-before.sha256" "$run_dir/efi-recheck.sha256"

status=0
sudo "$rebuild" switch --store-path "$target" --no-reexec || status=$?
printf 'nixos-rebuild switch exit status: %s\n' "$status"
snapshot_efi >"$run_dir/efi-after.sha256"
snapshot_firmware >"$run_dir/firmware-after.sha256"
awk '$2 != "/boot/loader/loader.conf" && $2 != "/boot/loader/entries/nixos-generation-1.conf"' "$run_dir/efi-before.sha256" >"$run_dir/protected-before.sha256"
awk '$2 != "/boot/loader/loader.conf" && $2 != "/boot/loader/entries/nixos-generation-1.conf" && $2 != "/boot/loader/entries/nixos-generation-2.conf"' "$run_dir/efi-after.sha256" >"$run_dir/protected-after.sha256"
diff -u "$run_dir/protected-before.sha256" "$run_dir/protected-after.sha256" || status=1
diff -u "$run_dir/firmware-before.sha256" "$run_dir/firmware-after.sha256" || status=1
sudo cmp "$run_dir/loader.conf.expected" /boot/loader/loader.conf || status=1
sudo cmp "$run_dir/nixos-generation-1.conf" /boot/loader/entries/nixos-generation-1.conf || status=1
sudo cmp "$run_dir/nixos-generation-2.conf" /boot/loader/entries/nixos-generation-2.conf || status=1
[[ $(readlink -f /nix/var/nix/profiles/system) == "$target" ]] || status=1
[[ $(readlink /nix/var/nix/profiles/system) == system-2-link ]] || status=1
[[ $(readlink -f /run/current-system) == "$target" ]] || status=1
[[ $(readlink -f /run/booted-system) == "$baseline" ]] || status=1
[[ $(readlink -f /nix/var/nix/profiles/system-1-link) == "$baseline" ]] || status=1
sudo "$bootctl" --esp-path=/boot status >"$run_dir/boot-status-after.txt" || status=1
sudo "$bootctl" --esp-path=/boot list --no-pager >"$run_dir/boot-entries-after.txt" || status=1
systemctl --failed --no-pager
systemctl --user --failed --no-pager
systemctl is-active display-manager.service home-manager-$USER.service || status=1
if [[ $status == 0 ]]; then
  printf 'Permanent generation 2 installed. Protected EFI files and firmware boot variables match.\n'
  printf 'Generation 1 is retained. No reboot was performed.\n'
fi
exit "$status"

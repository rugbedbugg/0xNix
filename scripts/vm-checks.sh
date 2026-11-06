#!/usr/bin/env bash
# Runs the VM checks one at a time and prints a result for each. They boot
# the laptop host, boot the fresh install host and install a minimal system
# on the fresh host's disk layout. CI only evaluates them. The two system VMs
# get 4 GiB each, so running them one after another keeps a small machine
# from running out of RAM.
#
# Pass check names to run a subset: scripts/vm-checks.sh vm disk-layout
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
checks=(vm vm-fresh disk-layout)
nix_flags=(--extra-experimental-features 'nix-command flakes')

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

usage() {
  die "Usage: scripts/vm-checks.sh [${checks[*]}]"
}

selected=("$@")
if ((${#selected[@]} == 0)); then
  selected=("${checks[@]}")
fi
for name in "${selected[@]}"; do
  [[ " ${checks[*]} " == *" $name "* ]] || usage
done

command -v nix >/dev/null || die 'Missing command: nix'
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  die 'The VM checks need read and write access to /dev/kvm.'
fi

# Flakes skip files that git does not track, so the build would not see them.
untracked=$(git -C "$repo" ls-files --others --exclude-standard '*.nix')
if [[ -n $untracked ]]; then
  printf 'Warning: git does not track these files, so the checks ignore them:\n%s\n' "$untracked" >&2
fi

passed=()
failed=()
for name in "${selected[@]}"; do
  printf '\n== %s\n' "$name"
  if nix "${nix_flags[@]}" build "$repo#checks.x86_64-linux.$name" --no-link --max-jobs 2 --cores 2 -L; then
    passed+=("$name")
  else
    failed+=("$name")
  fi
done

printf '\n'
for name in "${passed[@]}"; do
  printf 'passed: %s\n' "$name"
done
for name in "${failed[@]}"; do
  printf 'failed: %s\n' "$name"
done
((${#failed[@]} == 0))

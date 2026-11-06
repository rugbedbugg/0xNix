#!/usr/bin/env bash
# Installs the agents and apps profile packages and checks the binaries that
# the keybinds launch. Safe to run again: a package that is already in the
# user profile is skipped. Update them later with `nix profile upgrade --all`.
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
packages=(agents apps)
binaries=(microsoft-edge vesktop)

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

if [[ $# != 0 ]]; then
  die 'Usage: scripts/install-profiles.sh'
fi
for tool in nix jq; do
  command -v "$tool" >/dev/null || die "Missing command: $tool"
done

# Version 3 of the profile JSON keys the elements by name.
installed=$(nix profile list --json)
[[ $(jq -r '.version' <<<"$installed") == 3 ]] || die 'Unsupported nix profile list format.'

for name in "${packages[@]}"; do
  if jq -e --arg name "$name" '.elements | has($name)' <<<"$installed" >/dev/null; then
    printf 'Already installed: %s\n' "$name"
  else
    printf 'Installing: %s\n' "$name"
    nix profile add "$repo#$name"
  fi
done

for binary in "${binaries[@]}"; do
  [[ -x $HOME/.nix-profile/bin/$binary ]] || die "Missing from the profile: $binary"
  printf 'Found: %s\n' "$HOME/.nix-profile/bin/$binary"
done

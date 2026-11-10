#!/usr/bin/env bash
# Setup wizard for a NixOS machine that already runs. It asks for the details
# in vars.nix and for the git identity, shows a summary and writes both after
# a confirmation. The defaults come from the current vars.nix and the current
# identity file. It can then build and switch the system.
#
# The git email and signing key go to ~/.config/git/identity only. vars.nix
# is committed and ends up in the world-readable Nix store.
#
# --defaults accepts every default, rewrites vars.nix and stops. The build,
# the switch, the hardware scan and the identity file are skipped.
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
vars_file=$repo/vars.nix
hardware_file=$repo/hosts/nixos/hardware-configuration.nix
identity=${XDG_CONFIG_HOME:-$HOME/.config}/git/identity
nix_flags=(--extra-experimental-features 'nix-command flakes')
defaults=0
tmp_files=()

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

cleanup() {
  ((${#tmp_files[@]} == 0)) || rm -f -- "${tmp_files[@]}"
}
trap cleanup EXIT

case ${1-} in
  '') ;;
  --defaults) defaults=1 ;;
  *) die 'Usage: scripts/setup.sh [--defaults]' ;;
esac
if (($# > 1)); then
  die 'Usage: scripts/setup.sh [--defaults]'
fi

if ((EUID == 0)); then
  die 'Run as your own user. The git identity file belongs in your home.'
fi
[[ -e /etc/NIXOS ]] || die 'This wizard needs a running NixOS system.'
for tool in nix git sed; do
  command -v "$tool" >/dev/null || die "Missing command: $tool"
done

# Value of a vars.nix attribute as text. Null and a missing attribute give an
# empty string.
get_var() {
  nix "${nix_flags[@]}" eval --raw --file "$1" --apply "v: toString (v.$2 or \"\")"
}

# ask LABEL DEFAULT PATTERN HINT [optional]
# Prints the answer on stdout. Prompts go to stderr. Enter keeps the default.
# An optional value is cleared with "none".
ask() {
  local label=$1 default=$2 pattern=$3 hint=$4 optional=${5-}
  local reply shown=$default
  [[ -n $shown ]] || shown=none
  while true; do
    if ((defaults)); then
      reply=$default
    else
      if [[ -n $optional && -n $default ]]; then
        printf '%s [%s, "none" clears it]: ' "$label" "$shown" >&2
      else
        printf '%s [%s]: ' "$label" "$shown" >&2
      fi
      IFS= read -r reply || die 'Input ended before the wizard finished.'
      reply=${reply:-$default}
      if [[ -n $optional && $reply == none ]]; then
        reply=
      fi
    fi
    if [[ $reply =~ $pattern ]] && check_value "$label" "$reply"; then
      printf '%s\n' "$reply"
      return
    fi
    if ((defaults)); then
      die "Invalid default for $label: $reply"
    fi
    printf '  %s\n' "$hint" >&2
  done
}

# Checks beyond the pattern.
check_value() {
  local octet
  case $1 in
    'Phone Tailscale address')
      [[ -z $2 ]] && return 0
      local IFS=.
      for octet in $2; do
        ((10#$octet <= 255)) || return 1
      done
      ;;
    'Time zone')
      local dir
      for dir in /etc/zoneinfo /usr/share/zoneinfo; do
        [[ -d $dir ]] && [[ -e $dir/$2 ]] && return 0
      done
      [[ -d /etc/zoneinfo || -d /usr/share/zoneinfo ]] && return 1
      ;;
  esac
  return 0
}

# ask_yes LABEL DEFAULT, where DEFAULT is y or n.
ask_yes() {
  local label=$1 default=$2 reply hint='[y/N]'
  [[ $default == y ]] && hint='[Y/n]'
  while true; do
    printf '%s %s: ' "$label" "$hint" >&2
    IFS= read -r reply || die 'Input ended before the wizard finished.'
    reply=${reply:-$default}
    case ${reply,,} in
      y | yes) return 0 ;;
      n | no) return 1 ;;
    esac
    printf '  Answer y or n.\n' >&2
  done
}

# Read the current values. They are the defaults of every question.
cur_username=$(get_var "$vars_file" username)
cur_hostname=$(get_var "$vars_file" hostname)
cur_display=$(get_var "$vars_file" displayName)
cur_git_name=$(get_var "$vars_file" gitName)
cur_phone=$(get_var "$vars_file" phoneAddress)
cur_zone=$(get_var "$vars_file" timeZone)
cur_locale=$(get_var "$vars_file" locale)
cur_width=$(get_var "$vars_file" screen.width)
cur_height=$(get_var "$vars_file" screen.height)
cur_email=
cur_key=
if [[ -f $identity ]]; then
  cur_email=$(git config -f "$identity" --get user.email || true)
  cur_key=$(git config -f "$identity" --get user.signingkey || true)
fi

if ((!defaults)); then
  printf 'Setup wizard. Press Enter to keep the value in brackets.\n\n' >&2
fi

username=$(ask 'Username' "$cur_username" '^[a-z_][a-z0-9_-]{0,31}$' \
  'Use lowercase letters, digits, "_" and "-". Start with a letter or "_".')
hostname=$(ask 'Hostname' "$cur_hostname" '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$' \
  'Use letters, digits and "-". Do not start or end with "-".')
display_name=$(ask 'Login display name' "$cur_display" '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$' \
  'Use letters, digits, spaces, ".", "_" and "-".')
git_name=$(ask 'Git commit author name' "$cur_git_name" '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$' \
  'Use letters, digits, spaces, ".", "_" and "-".')
phone=$(ask 'Phone Tailscale address' "$cur_phone" '^$|^([0-9]{1,3}\.){3}[0-9]{1,3}$' \
  'Enter an IPv4 address such as 100.64.0.1, or "none".' optional)
zone=$(ask 'Time zone' "$cur_zone" '^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+){0,2}$' \
  'Enter a zone name such as Europe/Berlin. Check "timedatectl list-timezones".')
locale=$(ask 'Locale' "$cur_locale" '^[a-z]{2,3}_[A-Z]{2}$' \
  'Enter a locale such as en_US.')
width=$(ask 'Screen width in logical pixels' "$cur_width" '^[1-9][0-9]{2,4}$' \
  'Enter a whole number such as 1920.')
height=$(ask 'Screen height in logical pixels' "$cur_height" '^[1-9][0-9]{2,4}$' \
  'Enter a whole number such as 1080.')

email=$cur_email
signing_key=$cur_key
if ((!defaults)); then
  printf '\nGit identity. It stays in %s and out of the repository.\n' "$identity" >&2
  email=$(ask 'Git email' "$cur_email" '^[^[:space:]@]+@[^[:space:]@]+$' \
    'Enter an address such as you@example.com.')
  signing_key=$(ask 'GPG signing key fingerprint' "$cur_key" '^$|^[0-9A-Fa-f]{16,40}$' \
    'Enter 16 to 40 hex digits, or "none" to leave commits unsigned.' optional)
  if [[ -n $signing_key ]] && command -v gpg >/dev/null &&
    ! gpg --list-secret-keys "$signing_key" >/dev/null 2>&1; then
    printf 'Warning: gpg has no secret key %s yet. Import it before you commit.\n' "$signing_key" >&2
  fi
fi

if ((!defaults)); then
  printf '\nSummary\n' >&2
  printf '  username       %s\n' "$username" >&2
  printf '  hostname       %s\n' "$hostname" >&2
  printf '  display name   %s\n' "$display_name" >&2
  printf '  git name       %s\n' "$git_name" >&2
  printf '  phone address  %s\n' "${phone:-none}" >&2
  printf '  time zone      %s\n' "$zone" >&2
  printf '  locale         %s\n' "$locale" >&2
  printf '  screen         %sx%s\n' "$width" "$height" >&2
  printf '  git email      %s\n' "$email" >&2
  printf '  signing key    %s\n\n' "${signing_key:-none, commits stay unsigned}" >&2
  ask_yes 'Write these values?' n || die 'Nothing written.'
fi

# Rewrite the values in place, so the comments stay in vars.nix. Every value
# passed its pattern, so none holds a character that sed or Nix treats
# specially.
phone_nix=null
[[ -z $phone ]] || phone_nix=\"$phone\"
new_vars=$(mktemp "$repo/vars.nix.XXXXXX")
tmp_files+=("$new_vars")
sed \
  -e "s|^  username = \".*\";|  username = \"$username\";|" \
  -e "s|^  hostname = \".*\";|  hostname = \"$hostname\";|" \
  -e "s|^  displayName = \".*\";|  displayName = \"$display_name\";|" \
  -e "s|^  gitName = \".*\";|  gitName = \"$git_name\";|" \
  -e "s|^  phoneAddress = .*;|  phoneAddress = $phone_nix;|" \
  -e "s|^  timeZone = \".*\";|  timeZone = \"$zone\";|" \
  -e "s|^  locale = \".*\";|  locale = \"$locale\";|" \
  -e "s|^    width = .*;|    width = $width;|" \
  -e "s|^    height = .*;|    height = $height;|" \
  "$vars_file" >"$new_vars"

# The file must read back as the answers before it replaces vars.nix.
expected=(
  username "$username" hostname "$hostname" displayName "$display_name"
  gitName "$git_name" phoneAddress "$phone" timeZone "$zone" locale "$locale"
  screen.width "$width" screen.height "$height"
)
for ((i = 0; i < ${#expected[@]}; i += 2)); do
  [[ $(get_var "$new_vars" "${expected[i]}") == "${expected[i + 1]}" ]] ||
    die "vars.nix would not read back ${expected[i]} correctly. Nothing written."
done
chmod --reference="$vars_file" "$new_vars"
mv -- "$new_vars" "$vars_file"
printf 'Wrote %s\n' "$vars_file"

if ((defaults)); then
  exit 0
fi

# Edit the identity file with git config, so any other entry in it survives.
# The subshell keeps the strict umask away from the later sudo call.
(
  umask 077
  mkdir -p -- "$(dirname -- "$identity")"
  touch -- "$identity"
  chmod 600 -- "$identity"
  git config -f "$identity" user.email "$email"
  if [[ -n $signing_key ]]; then
    git config -f "$identity" user.signingkey "$signing_key"
    git config -f "$identity" --unset-all commit.gpgsign || true
    git config -f "$identity" --unset-all tag.gpgSign || true
  else
    # The include comes last in the generated git config, so these win over
    # signByDefault.
    git config -f "$identity" --unset-all user.signingkey || true
    git config -f "$identity" commit.gpgsign false
    git config -f "$identity" tag.gpgSign false
  fi
)
printf 'Wrote %s\n' "$identity"

# hardware-configuration.nix belongs to one machine. Keep it when it already
# names this machine's root filesystem.
#
# A switch with the wrong hardware file or the wrong account can leave the
# machine unbootable or locked out, so each case blocks the switch.
blockers=()
root_uuid=$(findmnt -no UUID / 2>/dev/null || true)
if [[ -n $root_uuid ]] && grep -q "by-uuid/$root_uuid" "$hardware_file"; then
  printf 'The hardware file already matches this machine. Keeping it.\n'
else
  blockers+=('hardware-configuration.nix does not name the root filesystem of this machine')
  if command -v nixos-generate-config >/dev/null; then
    printf '\nhardware-configuration.nix does not name the root filesystem of this machine.\n'
    printf 'checks.configuration-safety pins the original machine. It fails after a new scan\n'
    printf 'until you update the baseline in checks/default.nix.\n'
    if ask_yes 'Replace it with a scan of this machine?' n; then
      new_hardware=$(mktemp "$repo/hosts/nixos/hardware.XXXXXX")
      tmp_files+=("$new_hardware")
      nixos-generate-config --show-hardware-config >"$new_hardware"
      chmod --reference="$hardware_file" "$new_hardware"
      mv -- "$new_hardware" "$hardware_file"
      printf 'Wrote %s\n' "$hardware_file"
      blockers=()
    fi
  fi
fi
login_user=${USER:-$(id -un)}
if [[ $username != "$login_user" ]]; then
  blockers+=("the username $username differs from your login $login_user, so the new account has no password and the old one may go")
fi

if ask_yes $'\nBuild the system now?' y; then
  nix "${nix_flags[@]}" build "$repo#system" --no-link --max-jobs 2 --cores 2
  printf 'The build succeeded.\n'
  if ((${#blockers[@]} == 0)) && ask_yes 'Switch to it now? This runs sudo.' n; then
    sudo nixos-rebuild switch --flake "$repo#nixos" --option experimental-features 'nix-command flakes'
    switched=1
  fi
fi

if ((${#blockers[@]} > 0)); then
  printf '\nThe wizard does not offer the switch because:\n'
  printf '  - %s\n' "${blockers[@]}"
fi
if [[ -z ${switched-} ]]; then
  if ((${#blockers[@]} > 0)); then
    printf '\nFix the reasons above. Then run:\n'
  else
    printf '\nNext, run:\n'
  fi
  printf "  sudo nixos-rebuild switch --flake %s#nixos --option experimental-features 'nix-command flakes'\n" "$repo"
  exit 0
fi

printf 'Next: restore the state listed in the README, such as the GPG key and tailscale up.\n'

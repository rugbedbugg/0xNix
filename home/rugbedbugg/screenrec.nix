# Screen recorder shared by the record keybinds (keybinds.nix) and the
# waybar timer (waybar-side-bars.nix). Both import it from here so they agree
# on where a running recording keeps its state.
#
# wl-screenrec encodes H.264 on the GPU through VA-API, so recording barely
# touches the CPU. Recordings land in ~/Videos/Recordings with the same
# date-time names as screenshots. Nothing is copied to the clipboard.
{ config, pkgs }:
let
  # Lives in the runtime dir while a recording runs: the recorder's pid,
  # its start time, the file it writes and the tooltip rows that describe
  # it. The toggle and the bar timer both read it.
  run = "$XDG_RUNTIME_DIR/screenrec";
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  flock = "${pkgs.util-linux}/bin/flock";
  # Starts or stops the timer bar in waybar-side-bars.nix.
  timerBar = action: "${pkgs.systemd}/bin/systemctl --user ${action} waybar-recording.service";
in
{
  # `screenrec full` or `screenrec region` starts a recording, or stops the
  # running one. `screenrec stop` only stops.
  #
  # Before starting, a fuzzel menu in the session menu's style asks what
  # audio to record, with the last answer preselected. wl-screenrec takes a
  # single PulseAudio source, so "System + mic" builds a temporary mix: a
  # null sink with the speaker monitor and the default mic looped into it,
  # recorded from its monitor and unloaded when the recording ends. None of
  # this changes the default sink or source.
  #
  # A lock serializes the steps before the recorder starts: the audio menu,
  # the region pick and the pid write. A press that finds the lock taken
  # cancels the region pick, like a second press closes the audio menu, and
  # exits. The stop path comes before the lock, since a running recording
  # holds none. The lock file sits outside the state directory, which is
  # removed when a recording ends.
  #
  # An exit trap stops the recorder and unloads the temporary audio modules
  # on any exit, including SIGTERM and SIGHUP. SIGKILL cannot be trapped.
  toggle = pkgs.writeShellScript "screenrec" ''
    run="${run}"
    pref="${config.xdg.stateHome}/screenrec-audio"
    modules=()
    recorder=
    started=

    if [ -r "$run/pid" ] && kill -0 "$(< "$run/pid")" 2>/dev/null; then
      kill -INT "$(< "$run/pid")"
      exit 0
    fi
    [ "$1" = stop ] && exit 0

    # A second press while the audio menu is open closes it, like the
    # session menu. Like that one, it closes any open fuzzel.
    if ${pkgs.procps}/bin/pkill -x fuzzel; then
      exit 0
    fi

    exec 9> "$XDG_RUNTIME_DIR/screenrec.lock"
    if ! ${flock} -n 9; then
      ${pkgs.procps}/bin/pkill -x slurp
      exit 0
    fi

    cleanup() {
      if [ -n "$recorder" ]; then
        kill -INT "$recorder" 2>/dev/null
        wait "$recorder" 2>/dev/null
        recorder=
      fi
      if [ -n "$started" ]; then
        ${timerBar "stop"}
        ${pkgs.coreutils}/bin/rm -rf "$run"
        started=
      fi
      for module in "''${modules[@]}"; do
        ${pactl} unload-module "$module"
      done
      modules=()
    }
    trap cleanup EXIT
    trap 'exit 143' TERM HUP

    # Load one audio module and remember it for cleanup.
    load() {
      local id
      id=$(${pactl} load-module "$@") || return 1
      modules+=("$id")
    }

    last=$(cat "$pref" 2>/dev/null) || last="No audio"
    choice=$(printf '%s\n' "No audio" "System audio" "Microphone" "System + mic" \
      | ${pkgs.fuzzel}/bin/fuzzel --dmenu --only-match --no-sort --hide-prompt \
        --width 20 --lines 4 --mesg "Record audio" --select "$last") || exit 0
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$pref")"
    printf '%s\n' "$choice" > "$pref"

    # The Radeon encoder only takes frames of 128px or more on each side,
    # so a smaller region encodes on the CPU instead. libx264 needs even
    # sizes, and slurp often returns odd ones.
    encoder="H.264, GPU"
    if [ "$1" = region ]; then
      geometry=$(${pkgs.slurp}/bin/slurp) || exit 0
      size=''${geometry#* }
      w=$((''${size%x*} / 2 * 2))
      h=$((''${size#*x} / 2 * 2))
      set -- -g "''${geometry% *} ''${w}x''${h}"
      area="Region ''${w}x''${h}"
      if [ "$w" -lt 128 ] || [ "$h" -lt 128 ]; then
        set -- "$@" --no-hw
        encoder="H.264, CPU"
      fi
    else
      set --
      area="Full screen"
    fi

    case "$choice" in
      "System audio")
        set -- "$@" --audio --audio-device @DEFAULT_MONITOR@
        ;;
      Microphone)
        set -- "$@" --audio
        ;;
      "System + mic")
        if ! { load module-null-sink sink_name=screenrec-mix sink_properties=device.description=screenrec-mix \
          && load module-loopback source=@DEFAULT_MONITOR@ sink=screenrec-mix latency_msec=20 \
          && load module-loopback source=@DEFAULT_SOURCE@ sink=screenrec-mix latency_msec=20; }; then
          ${pkgs.libnotify}/bin/notify-send -u critical "Recording failed" "PulseAudio refused the audio mix"
          exit 0
        fi
        set -- "$@" --audio --audio-device screenrec-mix.monitor
        ;;
    esac

    dir="${config.xdg.userDirs.videos}/Recordings"
    ${pkgs.coreutils}/bin/mkdir -p "$dir" "$run"
    file="$dir/$(${pkgs.coreutils}/bin/date +%F_%H-%M-%S).mp4"

    # The Radeon encoder has no low-power mode. Asking for it only fails
    # and falls back with a warning.
    # The recorder closes the lock's descriptor, or it would hold the lock
    # for the whole recording.
    ${pkgs.wl-screenrec}/bin/wl-screenrec --low-power=off "$@" -f "$file" 9>&- &
    recorder=$!
    started=1
    echo "$recorder" > "$run/pid"
    echo "$file" > "$run/file"
    printf '%s\t%s\n' File "''${file##*/}" Area "$area" Audio "$choice" Encoder "$encoder" > "$run/info"
    ${pkgs.coreutils}/bin/date +%s > "$run/start"
    ${timerBar "start"}
    exec 9>&-
    wait "$recorder"
    recorder=

    # The timer leaves the screen before the toast shows up. The short
    # sleep covers the bar's closing animation.
    cleanup
    ${pkgs.coreutils}/bin/sleep 0.2
    if [ ! -s "$file" ]; then
      ${pkgs.coreutils}/bin/rm -f "$file"
      ${pkgs.libnotify}/bin/notify-send -u critical "Recording failed" "wl-screenrec exited without writing a video"
      exit 0
    fi

    # Asks before keeping it, in the session menu's confirm style. Yes comes
    # first since deleting is the step that can't be undone. Closing the
    # menu with Esc or the record key keeps the video too.
    answer=$(printf 'Yes\nNo\n' \
      | ${pkgs.fuzzel}/bin/fuzzel --dmenu --only-match --no-sort --hide-prompt \
        --width 13 --lines 2 --mesg "Save video?")
    if [ "$answer" = No ]; then
      ${pkgs.coreutils}/bin/rm -f "$file"
      ${pkgs.libnotify}/bin/notify-send "Recording discarded" "''${file##*/}"
    else
      ${pkgs.libnotify}/bin/notify-send "Recording saved" "$file"
    fi
  '';

  # Waybar module script. Like the stat scripts, it runs for the bar's
  # whole lifetime and prints one JSON line a second: "REC m:ss" while a
  # recording runs, and empty text otherwise, which hides the module. The
  # tooltip lists what the recorder wrote down at the start, the file's
  # size so far and when it started.
  status = pkgs.writeShellScript "screenrec-status" ''
    run="${run}"
    iec() {
      ${pkgs.gawk}/bin/awk -v b="$1" 'BEGIN {
        split("B KiB MiB GiB TiB", u, " "); i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i]
      }'
    }
    while :; do
      if [ -r "$run/start" ] && read -r start < "$run/start"; then
        printf -v now '%(%s)T' -1
        s=$((now - start))
        bytes=$(${pkgs.coreutils}/bin/stat -c %s "$(< "$run/file")" 2>/dev/null || echo 0)
        tooltip=$(
          while IFS=$'\t' read -r label value; do
            printf '%-10s %s\n' "$label" "$value"
          done < "$run/info"
          printf '%-10s %s\n' Size "$(iec "$bytes")"
          printf '%-10s %(%H:%M)T\n' Started "$start"
          printf '\nClick or Super + R to stop'
        )
        ${pkgs.jq}/bin/jq -cn --arg text "$(printf 'REC %d:%02d' $((s / 60)) $((s % 60)))" \
          --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip, class: "recording"}'
      else
        printf '{"text":""}\n'
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';
}

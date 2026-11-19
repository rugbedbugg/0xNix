# tmux in the rice's TTY look. It inherits the terminal's VGA font, so only
# the status line, the borders and the message line carry a colour. Every
# colour comes from palette.nix. The active pane border is white, the rice's
# border rule, and the current window reads in reverse video like selected
# items elsewhere.
{
  config,
  lib,
  palette,
  ...
}:
{
  config = lib.mkIf config.programs.tmux.enable {
    programs.tmux = {
      terminal = "tmux-256color";
      extraConfig = ''
        # foot draws in true colour, so pass 24-bit colour through instead of
        # mapping the palette's hex values to the nearest 256.
        set -ga terminal-features "*:RGB"

        set -g status-style "bg=${palette.surface},fg=${palette.textMuted}"
        set -g status-left "#[fg=${palette.nix},bold] #S #[default] "
        set -g status-left-length 30
        set -g status-right "#[fg=${palette.textMuted}]%Y-%m-%d %H:%M "

        setw -g window-status-current-style "bg=${palette.text},fg=${palette.surface}"
        setw -g window-status-style "fg=${palette.textMuted}"
        setw -g window-status-format " #I:#W "
        setw -g window-status-current-format " #I:#W "

        set -g pane-border-style "fg=${palette.outlineVariant}"
        set -g pane-active-border-style "fg=${palette.border}"

        set -g message-style "bg=${palette.surfaceContainerHigh},fg=${palette.text}"
        set -g mode-style "bg=${palette.text},fg=${palette.surface}"
      '';
    };
  };
}

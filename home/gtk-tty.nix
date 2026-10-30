# A GTK4 theme in the rice's TTY look, shared by desktop-tools.nix (which
# installs it and the pavucontrol wrapper) and keybinds.nix (satty).
#
# It isn't the session's GTK theme. Only apps wrapped with `wrap` run with
# it, through GTK_THEME, so nothing else changes look. Being a theme, it
# also beats styles an app loads at fallback priority, like satty's own.
# It starts from GTK's dark default and restyles the widgets on top:
# opaque #20242c fill, 2px white borders, square corners, VGA font.
# Selected and checked things are in reverse video, like the focused
# workspace on waybar. Hover draws an inner white outline. Dimmed grey
# means disabled.
{ pkgs }:
{
  css = pkgs.writeText "tty-gtk.css" ''
    @import url("resource:///org/gtk/libgtk/theme/Default/Default-dark.css");

    * { font-family: "VGA", monospace; font-size: 11pt; border-radius: 0; box-shadow: none; text-shadow: none; -gtk-icon-shadow: none; outline-color: #ffffff; }
    window, .background, .view, list, listview, row { background: #20242c; color: #eceff4; }
    label:disabled { color: #6c7380; }
    separator { background: #6c7380; min-width: 1px; min-height: 1px; }

    headerbar { background: #20242c; color: #ffffff; border-bottom: 2px solid #ffffff; min-height: 28px; padding: 0 4px; }
    window.csd, window.csd decoration { border-radius: 0; box-shadow: none; }
    windowcontrols button { border: none; min-height: 20px; min-width: 20px; padding: 0; }

    button { background: #20242c; background-image: none; color: #ffffff; border: 2px solid #ffffff; border-radius: 0; padding: 2px 8px; min-height: 22px; }
    button:hover { box-shadow: inset 0 0 0 2px #ffffff; }
    button:checked, button:active, button.flat:checked, button.toggle:checked { background: #eceff4; color: #20242c; }
    button:disabled, button.flat:disabled { background: #20242c; color: #6c7380; border-color: #6c7380; }
    button:checked:disabled, button.flat:checked:disabled { background: #6c7380; color: #20242c; }
    button.flat { border-color: transparent; }
    dropdown > button > box > stack > row { background: transparent; }

    notebook, notebook > stack, notebook > stack:not(:only-child), scrolledwindow, viewport { background: #20242c; border: none; }
    notebook > header { background: #20242c; border: none; border-bottom: 2px solid #ffffff; box-shadow: none; }
    notebook > header tab { background: transparent; color: #eceff4; border: none; padding: 4px 12px; min-height: 0; }
    notebook > header tab:hover { box-shadow: inset 0 0 0 2px #ffffff; }
    notebook > header tab:checked { background: #eceff4; color: #20242c; }
    notebook > header tab:checked label { color: #20242c; }
    notebook > header.top > tabs > tab:checked { box-shadow: none; }
    /* Keyboard focus rings in white instead of the default blue. */
    notebook:focus:focus-visible > header > tabs > tab:checked, button:focus:focus-visible, label:focus:focus-visible { outline-color: #ffffff; }

    /* The default theme draws a slider with marks as an image, under its
       own :hover, :active and :disabled selectors. These match them. */
    scale > trough { background: #20242c; border: 2px solid #ffffff; min-height: 6px; min-width: 6px; }
    scale > trough > highlight, scale > trough > fill { background: #ffffff; border: none; min-height: 6px; }
    scale > trough > slider,
    scale > trough > slider:hover,
    scale > trough > slider:active,
    scale.horizontal.marks-after:not(.marks-before) > trough > slider,
    scale.horizontal.marks-after:not(.marks-before) > trough > slider:hover,
    scale.horizontal.marks-after:not(.marks-before) > trough > slider:active,
    scale.horizontal.marks-after:not(.marks-before).fine-tune > trough > slider { background: #ffffff; background-image: none; border: none; border-radius: 0; min-width: 8px; min-height: 20px; margin: -9px 0; }
    scale > trough > slider:disabled,
    scale.horizontal.marks-after:not(.marks-before) > trough > slider:disabled { background: #6c7380; background-image: none; border: none; border-radius: 0; min-width: 8px; min-height: 20px; margin: -9px 0; }
    scale marks, scale value { color: #6c7380; }

    /* pavucontrol's peak meters, in waybar's GPU green. */
    progressbar > trough, progressbar.horizontal > trough { background: #20242c; border: 1px solid #6c7380; border-radius: 0; min-height: 4px; }
    progressbar > trough > progress, progressbar.horizontal > trough > progress { background: #7ee787; border: none; border-radius: 0; min-height: 4px; }


    levelbar trough { background: #20242c; border: 2px solid #ffffff; padding: 0; min-height: 6px; }
    levelbar block { border: none; min-height: 6px; }
    levelbar block.filled, levelbar block.low, levelbar block.high, levelbar block.full { background: #7ee787; }
    levelbar block.empty { background: transparent; }

    check, radio { background: #20242c; background-image: none; color: #20242c; border: 2px solid #ffffff; border-radius: 0; min-width: 12px; min-height: 12px; }
    check:checked, radio:checked { background: #eceff4; color: #20242c; }

    entry, spinbutton { background: #20242c; color: #ffffff; border: 2px solid #ffffff; border-radius: 0; }
    entry:focus-within, spinbutton:focus-within { box-shadow: inset 0 0 0 2px #ffffff; }

    popover > contents, popover.menu > contents { background: #20242c; color: #ffffff; border: 2px solid #ffffff; border-radius: 0; padding: 0; }
    popover > arrow { background: transparent; border: none; }
    popover row, popover modelbutton { color: #ffffff; padding: 4px 12px; }
    popover row:hover, popover row:selected, popover modelbutton:hover { background: #eceff4; color: #20242c; }
    popover row:hover label, popover row:selected label { color: #20242c; }

    scrollbar { background: transparent; border: none; }
    scrollbar slider { background: #ffffff; border: none; border-radius: 0; min-width: 4px; min-height: 4px; }

    frame > border { border: 2px solid #ffffff; border-radius: 0; }
    tooltip, tooltip.background { background: #20242c; border: 2px solid #ffffff; border-radius: 0; box-shadow: none; }
    tooltip label { color: #ffffff; padding: 4px; }

    /* satty: toolbars float over the screenshot as boxes. The white
       border is on the box, so its buttons drop theirs. */
    .toolbar { background: #20242c; color: #ffffff; border: 2px solid #ffffff; border-radius: 0; padding: 2px; }
    .toolbar-top { border-top: none; }
    .toolbar-bottom { border-bottom: none; }
    .toolbar button { background: transparent; border: none; outline: none; min-height: 24px; min-width: 24px; padding: 2px 6px; }
    .toolbar button:checked { background: #eceff4; color: #20242c; }
    .toolbar separator { background: #ffffff; min-width: 2px; margin: 0 4px; }
    .toolbar label { color: #ffffff; }
    .toast { background: #20242c; color: #ffffff; border: 2px solid #ffffff; border-radius: 0; }
  '';

  # `wrap pkg exe` is pkg with its exe started under the tty theme. The
  # desktop entry calls the exe by name, so launching from fuzzel goes
  # through the wrapper too.
  wrap =
    pkg: exe:
    pkgs.symlinkJoin {
      name = "${pkg.pname or pkg.name}-tty";
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/${exe} --set GTK_THEME tty
      '';
      inherit (pkg) meta;
    };
}

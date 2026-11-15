# Notifications through SwayNotificationCenter. Toasts show at the top right:
# no buttons, 320px wide with 8px margins and padding, gone after five
# seconds. A toast shows the notification's image, or else its app's icon,
# in a square as tall as a summary and one body line. Its body stops at three
# lines. The notification center opens from the bottom bar's rightmost
# button (waybar-bottom.nix) or Super + N. It lists every notification,
# newest first, with an X to close each one and a button that clears them
# all. Empty, it shows a grey NixOS snowflake.
#
# The look matches the rest of the rice: opaque palette fill, 2px white
# border, square corners, the VGA font at 11pt, reverse video on hover and no
# animations. Critical notifications take the alert colour and stay until
# closed.
{
  config,
  pkgs,
  palette,
  ...
}:
let
  package = config.services.swaync.package;

  # The NixOS snowflake in the disabled grey, for the empty center. The
  # white logo shades each lambda with white gradients. Recolouring them
  # keeps the shading.
  emptyIcon = pkgs.runCommand "nix-snowflake-outline.svg" { } ''
    sed 's/#ffffff/${palette.outline}/g' \
      ${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake-white.svg > $out
  '';

  # The default stylesheet nests every notification rule this deep.
  notification = ".notification-row .notification-background .notification";
  action = "${notification} .notification-default-action";
  textBox = "${action} .notification-content .text-box";
  centerRow = ".control-center .control-center-list .notification-row";
in
{
  services.swaync = {
    enable = true;
    # No setting covers these, so a patch does. It caps a toast's body at
    # three lines and turns HTML and Markdown in a body into Pango markup.
    # The VGA font draws its underline on the line below, so links and
    # other underlined text take the link colour instead. The patch also
    # keeps the newest notification at the top of a bottom-anchored center,
    # pins the title above the list and puts the snowflake on the empty
    # center. It hides a row that only partly fits the list, so no text is
    # cut at its edges. It also removes a closed notification's row when
    # animations are off. Without the fix, the row fades out but keeps its
    # space. GetLatestNotification on org.erikreider.swaync.cc returns the
    # newest notification for the bottom bar's tooltip.
    package = pkgs.swaynotificationcenter.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./swaync.patch ];
      postPatch = (old.postPatch or "") + ''
        substituteInPlace data/ui/notifications_widget.blp \
          --replace-fail "@emptyIcon@" "${emptyIcon}"
        substituteInPlace src/notification/notification.vala \
          --replace-fail "@underlineColour@" "${palette.nix}"
      '';
    });
    settings = {
      positionX = "right";
      positionY = "top";
      # The default top layer sits below the minimap's overlay layer, so
      # the minimap would cover the toasts. On overlay they share its layer,
      # and minimap.nix keeps the minimap under them. They also show above
      # fullscreen windows.
      layer = "overlay";
      control-center-layer = "overlay";
      # The center opens next to the bar button that opens it. It keeps
      # clear of the bars' exclusive zones.
      control-center-positionX = "right";
      control-center-positionY = "bottom";
      control-center-margin-top = 8;
      control-center-margin-bottom = 8;
      control-center-margin-right = 8;
      # As wide as a toast. The height holds the title row and seven
      # one-line notifications. Longer lists scroll.
      control-center-width = 320;
      control-center-height = 360;
      fit-to-screen = false;
      # A toast is 320px wide, as mako's were. The window adds the 8px
      # margin on each side.
      notification-window-width = 336;
      # Toasts and the center appear and go at once, with no slide or fade.
      transition-time = 0;
      timeout = 5;
      timeout-low = 5;
      # Red is reserved for things that need action, so critical
      # notifications stay until they are closed.
      timeout-critical = 0;
      notification-grouping = false;
      # mako showed no buttons. These filters drop the extra action buttons,
      # the copy button for codes and the reply field. The pattern skips the
      # action named default, which a click on a toast runs, as it did with
      # mako.
      notification-action-filter.all = {
        use-regex = true;
        id-matcher = "^(?!default$).*";
      };
      notification-2fa-action = false;
      notification-inline-replies = false;
      text-empty = "No notifications";
      widgets = [
        "title"
        "notifications"
      ];
      widget-config.title = {
        text = "Notifications";
        clear-all-button = true;
        button-text = "Clear all";
      };
    };
    # The default stylesheet holds the layout. The rules after it set the
    # rice's colours, borders, corners, font and spacing. VGA has no bold
    # weight, so GTK fakes bold by smearing each glyph. Every label stays at
    # normal weight.
    style = ''
      @import url("${package}/etc/xdg/swaync/style.css");

      :root {
        --cc-bg: ${palette.surface};
        --noti-border-color: ${palette.border};
        --noti-bg-alpha: 1;
        --noti-bg-hover: ${palette.surface};
        --noti-bg-focus: transparent;
        --noti-close-bg: ${palette.surface};
        --noti-close-bg-hover: ${palette.border};
        --text-color: ${palette.border};
        --text-color-disabled: ${palette.outline};
        --border: 2px solid ${palette.border};
        --border-radius: 0;
        --notification-shadow: none;
        /* A summary line and one body line of the 16px VGA font. */
        --notification-icon-size: 32px;
        --notification-app-icon-size: 0;
        --notification-group-icon-size: 0;
        --font-size-body: 11pt;
        --font-size-summary: 11pt;
        --hover-tranistion: none;
        --group-collapse-tranistion: none;
      }

      * {
        font-family: "VGA", monospace;
        font-weight: normal;
        text-shadow: none;
        box-shadow: none;
        transition: none;
        animation: none;
      }

      /* Toasts: 8px from the screen edges and from each other, 8px of
         padding inside the border. */
      .floating-notifications {
        padding-top: 4px;
      }

      .floating-notifications .notification-row .notification-background {
        padding: 4px 8px;
      }

      ${notification} {
        background: ${palette.surface};
      }

      ${action} {
        padding: 8px;
      }

      ${action} .notification-content .image {
        margin: 0 8px 0 0;
        border-radius: 0;
      }

      /* Hide the app icon that swaync badges onto a notification's own
         image. */
      ${action} .notification-content .app-icon {
        margin: 0;
        min-width: 0;
        min-height: 0;
      }

      ${textBox} .summary,
      ${textBox} .time {
        font-weight: normal;
      }

      ${textBox} .time {
        color: ${palette.textMuted};
      }

      ${notification}.critical {
        border-color: ${palette.alert};
      }

      ${notification}.critical .notification-default-action .notification-content .text-box .summary,
      ${notification}.critical .notification-default-action .notification-content .text-box .body {
        color: ${palette.alert};
      }

      /* No blue focus ring. */
      .notification-row:focus,
      .notification-row:focus-visible {
        outline: none;
      }

      .close-button {
        background: ${palette.surface};
        color: ${palette.border};
        border: 2px solid ${palette.border};
        border-radius: 0;
        min-width: 18px;
        min-height: 18px;
        margin: 6px;
      }

      .close-button:hover {
        background: ${palette.border};
        color: ${palette.surface};
        border: 2px solid ${palette.border};
      }

      /* An outline takes no space, so the panel's content fills its height
         exactly and has nothing to scroll. */
      .control-center {
        outline: 2px solid ${palette.border};
        outline-offset: -2px;
      }

      /* The center is laid out as the bars are: a 32px title row and one
         row per notification, each closed by a 2px white rule. Clear all
         is a segment at the right end of the title row. The row under the
         pointer turns to reverse video, as a hovered menu item does. */
      .control-center .widget {
        margin: 0;
        padding: 0;
      }

      .widget-title {
        border-bottom: 2px solid ${palette.border};
      }

      ${centerRow} .notification-background {
        padding: 0;
        margin: 0;
        border-bottom: 2px solid ${palette.border};
      }

      /* Every row is at least as tall as the image, so a summary-only row
         still holds the close button. */
      ${centerRow} .notification-background .notification .notification-default-action {
        padding: 4px 12px;
        min-height: 32px;
      }

      ${centerRow} .notification-background .notification,
      ${centerRow} .notification-background .notification .notification-default-action {
        border: none;
        background: transparent;
      }

      ${centerRow} .notification-background .notification .notification-default-action:hover {
        background: ${palette.border};
      }

      ${centerRow} .notification-background .notification .notification-default-action:hover label {
        color: ${palette.surface};
      }

      .control-center .control-center-list-placeholder {
        opacity: 1;
        color: ${palette.outline};
      }

      /* The list scrolls with the wheel and shows no scrollbar. Its ends
         draw no glow. */
      .control-center overshoot,
      .control-center undershoot {
        background: none;
        box-shadow: none;
      }

      .control-center scrollbar,
      .control-center scrollbar slider {
        opacity: 0;
        min-width: 0;
        min-height: 0;
        background: none;
        border: none;
      }

      .widget-title > label {
        font-size: 11pt;
        margin: 0;
        padding: 0 12px;
      }

      .widget-title > button {
        background: ${palette.surface};
        color: ${palette.border};
        border: none;
        border-left: 2px solid ${palette.border};
        border-radius: 0;
        margin: 0;
        min-height: 0;
        /* swaync centres the button vertically. Padding around the 16px
           line makes it the full 30px above the rule, so its divider runs
           the row's height. */
        padding: 7px 10px;
      }

      .widget-title > button:hover {
        background: ${palette.border};
        color: ${palette.surface};
      }
    '';
  };
}

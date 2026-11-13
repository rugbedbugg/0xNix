# Notifications through SwayNotificationCenter. Toasts show at the top right
# and behave as mako's did: text only, no buttons, 320px wide with 8px
# margins and padding, gone after five seconds. The notification center opens
# from the bottom bar's rightmost button (waybar-bottom.nix) or Super + N. It
# lists every notification with an X to close each one and a button that
# clears them all.
#
# The look matches the rest of the rice: opaque palette fill, 2px white
# border, square corners, the VGA font at 11pt, reverse video on hover and no
# animations. Critical notifications take the alert colour and stay until
# closed.
{ config, palette, ... }:
let
  package = config.services.swaync.package;

  # The default stylesheet nests every notification rule this deep.
  notification = ".notification-row .notification-background .notification";
  action = "${notification} .notification-default-action";
  textBox = "${action} .notification-content .text-box";
  centerRow = ".control-center .control-center-list .notification-row";
in
{
  services.swaync = {
    enable = true;
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
      control-center-width = 420;
      control-center-height = 600;
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
    # normal weight. Icons are sized to nothing, so toasts carry text only,
    # as mako's did.
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
        --notification-icon-size: 0;
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

      ${action} .notification-content .image,
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

      .control-center {
        border: 2px solid ${palette.border};
      }

      /* In the center, the panel's own border frames the list. Each
         notification sits on the panel without a box, and margins keep
         them apart. The one under the pointer turns to reverse video, as a
         hovered menu item does. */
      ${centerRow} .notification-background {
        padding: 0;
        margin: 6px 12px;
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

      /* The list scrolls with the wheel and shows no scrollbar. */
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
      }

      .widget-title > button {
        background: ${palette.surface};
        color: ${palette.border};
        border: 2px solid ${palette.border};
        border-radius: 0;
        padding: 2px 10px;
      }

      .widget-title > button:hover {
        background: ${palette.border};
        color: ${palette.surface};
      }
    '';
  };
}

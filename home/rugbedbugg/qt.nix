# Qt 6 apps in the rice's TTY look, the same as gtk-tty.nix gives GTK4
# apps: opaque surface-colour fill, 2px white borders, square corners, VGA
# font. Selected and checked things are in reverse video. Dimmed grey means
# disabled. Kirigami apps such as KDE Connect take their colours from
# kdeglobals.
#
# Unlike gtk-tty.nix, no app is wrapped. The theme applies to every Qt app
# in the session. qt6ct reads it. It takes a palette, a font and a style
# sheet from plain files, so no theme package is needed. Fusion is Qt's own
# style and ships with Qt itself, which keeps the look working across Qt
# updates. The style sheet on top of it draws the borders.
#
# Only Qt 6 is themed. Home Manager lists the Qt 5 plugin directory before
# the Qt 6 one in QT_PLUGIN_PATH. A Qt 6 app that asks for the qt5ct name
# gets no theme. Only the Qt 6 plugin answers to qt6ct, so that is the name
# used. No Qt 5 app is installed.
{
  config,
  pkgs,
  palette,
  ...
}:
let
  c = palette.bare;
  argb = role: "#ff${c.${role}}";
  # The order of Qt's palette roles: WindowText, Button, Light, Midlight,
  # Dark, Mid, Text, BrightText, ButtonText, Base, Window, Shadow,
  # Highlight, HighlightedText, Link, LinkVisited, AlternateBase, NoRole,
  # ToolTipBase, ToolTipText, PlaceholderText.
  scheme =
    fg:
    builtins.concatStringsSep ", " (
      map argb [
        fg
        "surface"
        "surfaceContainerHighest"
        "surfaceContainerHigh"
        "black"
        "outlineVariant"
        fg
        "border"
        fg
        "surface"
        "surface"
        "black"
        "text"
        "surface"
        "nix"
        "memory"
        "surfaceContainer"
        "black"
        "surface"
        fg
        "outline"
      ]
    );
  colours = pkgs.writeText "tty.conf" ''
    [ColorScheme]
    active_colors=${scheme "border"}
    inactive_colors=${scheme "border"}
    disabled_colors=${scheme "outline"}
  '';
  sheet = pkgs.writeText "tty.qss" ''
    * { font-family: "VGA"; font-size: 11pt; }
    QWidget { background: ${palette.surface}; color: ${palette.border}; }
    QWidget:disabled { color: ${palette.outline}; }
    QToolTip { background: ${palette.surface}; color: ${palette.border}; border: 2px solid ${palette.border}; }

    QPushButton, QToolButton { background: ${palette.surface}; color: ${palette.border}; border: 2px solid ${palette.border}; border-radius: 0; padding: 2px 8px; min-height: 18px; }
    QPushButton:hover, QToolButton:hover { border: 4px solid ${palette.border}; padding: 0 6px; }
    QPushButton:checked, QPushButton:pressed, QToolButton:checked, QToolButton:pressed { background: ${palette.text}; color: ${palette.surface}; }
    QPushButton:disabled, QToolButton:disabled { color: ${palette.outline}; border-color: ${palette.outline}; }

    QLineEdit, QPlainTextEdit, QTextEdit, QSpinBox, QDoubleSpinBox, QComboBox { background: ${palette.surface}; color: ${palette.border}; border: 2px solid ${palette.border}; border-radius: 0; selection-background-color: ${palette.text}; selection-color: ${palette.surface}; }
    QComboBox QAbstractItemView, QListView, QTreeView, QTableView { background: ${palette.surface}; color: ${palette.border}; border: 2px solid ${palette.border}; selection-background-color: ${palette.text}; selection-color: ${palette.surface}; }
    QHeaderView::section { background: ${palette.surface}; color: ${palette.border}; border: none; border-bottom: 2px solid ${palette.border}; padding: 2px 6px; }

    QMenuBar { background: ${palette.surface}; border-bottom: 2px solid ${palette.border}; }
    QMenuBar::item:selected, QMenu::item:selected { background: ${palette.text}; color: ${palette.surface}; }
    QMenu { background: ${palette.surface}; border: 2px solid ${palette.border}; }
    QMenu::separator { background: ${palette.outline}; height: 1px; }

    QTabWidget::pane { border: 2px solid ${palette.border}; }
    QTabBar::tab { background: ${palette.surface}; color: ${palette.border}; border: none; padding: 4px 12px; }
    QTabBar::tab:selected { background: ${palette.text}; color: ${palette.surface}; }

    QCheckBox::indicator, QRadioButton::indicator { background: ${palette.surface}; border: 2px solid ${palette.border}; width: 12px; height: 12px; }
    QCheckBox::indicator:checked, QRadioButton::indicator:checked { background: ${palette.text}; }

    QSlider::groove:horizontal { background: ${palette.surface}; border: 2px solid ${palette.border}; height: 6px; }
    QSlider::sub-page:horizontal { background: ${palette.border}; }
    QSlider::handle:horizontal { background: ${palette.border}; width: 8px; margin: -9px 0; }
    QProgressBar { background: ${palette.surface}; border: 2px solid ${palette.border}; border-radius: 0; text-align: center; }
    QProgressBar::chunk { background: ${palette.gpu}; }

    QScrollBar { background: ${palette.surface}; border: none; }
    QScrollBar::handle { background: ${palette.border}; min-width: 8px; min-height: 8px; }
    QScrollBar::add-line, QScrollBar::sub-line { width: 0; height: 0; }
    QGroupBox { border: 2px solid ${palette.border}; margin-top: 12px; }
    QGroupBox::title { subcontrol-origin: margin; left: 8px; padding: 0 4px; }
  '';
  conf = pkgs.writeText "qtct.conf" ''
    [Appearance]
    color_scheme_path=${colours}
    custom_palette=true
    standard_dialogs=default
    style=Fusion

    [Fonts]
    fixed="VGA,11,-1,5,50,0,0,0,0,0"
    general="VGA,11,-1,5,50,0,0,0,0,0"

    [Interface]
    stylesheets=${sheet}
  '';
  # KDE Connect and other Kirigami apps ignore the Qt palette and the style
  # sheet. They read their colours from the KDE colour scheme in kdeglobals
  # instead. They keep their own rounded cards, since only widget apps get
  # the style sheet. The selection is in reverse video, as in the rest of
  # the rice.
  kde =
    let
      rgb = role: builtins.replaceStrings [ ";" ] [ "," ] palette.rgb.${role};
      group = name: bg: alt: fg: ''
        [Colors:${name}]
        BackgroundAlternate=${rgb alt}
        BackgroundNormal=${rgb bg}
        DecorationFocus=${rgb "nix"}
        DecorationHover=${rgb "border"}
        ForegroundActive=${rgb "nix"}
        ForegroundInactive=${rgb "outline"}
        ForegroundLink=${rgb "nix"}
        ForegroundNegative=${rgb "alert"}
        ForegroundNeutral=${rgb "disk"}
        ForegroundNormal=${rgb fg}
        ForegroundPositive=${rgb "gpu"}
        ForegroundVisited=${rgb "memory"}
      '';
      plain = name: group name "surface" "surfaceContainer" "border";
    in
    pkgs.writeText "kdeglobals" (
      builtins.concatStringsSep "\n" [
        (plain "Window")
        (plain "View")
        (plain "Button")
        (plain "Tooltip")
        (plain "Complementary")
        (plain "Header")
        (group "Selection" "text" "text" "surface")
      ]
    );
in
{
  qt = {
    enable = true;
    platformTheme = {
      name = "qt6ct";
      package = pkgs.qt6Packages.qt6ct;
    };
  };
  xdg.configFile = {
    "qt6ct/qt6ct.conf".source = conf;
    "kdeglobals".source = kde;
    # UWSM does not import the session variables that Home Manager sets.
    # Every launcher starts apps through uwsm-app with Hyprland's own
    # environment, so the Qt variables go in UWSM's env file too. Its lines
    # join the ones in hyprland.nix.
    "uwsm/env".text = ''
      export QT_QPA_PLATFORMTHEME=${config.qt.platformTheme.name}
      export QT_PLUGIN_PATH=${config.home.profileDirectory}/lib/qt-6/plugins
    '';
  };
}

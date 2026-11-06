# Tooltips styled as mako toasts: opaque fill, 2px white border, square
# corners, 8px padding, same font and size. The GTK theme otherwise gives
# them a translucent, rounded, shadowed box. Every bar with tooltips
# shares these.
{ palette }:
''
  tooltip, tooltip.background { background: ${palette.surface}; border: 2px solid ${palette.border}; border-radius: 0; box-shadow: none; opacity: 1; }
  tooltip label { color: ${palette.border}; font-size: 11pt; padding: 8px; }
''

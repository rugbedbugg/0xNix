#!/usr/bin/env python3
"""Floating minimap of one window.

usage: minimap STABLE-ID ADDRESS

A small live copy of the window with the given Hyprland stableId, drawn on
the overlay layer so it stays above every window. It is dressed as a VHS
camera feed: scanlines, a rolling tracking band and a vignette, a clock and
the window's size on top, the window's class and workspace below, set inside
viewfinder corners.

It sits in one of 16 slots around the screen edge: five along the top and the
bottom (corners included) and three along each side. Drag it with the left button and it
snaps to the nearest slot on release. The scroll wheel resizes it, and the
right button opens a menu with "Go to window" and "Stop tracking". It
closes by itself when the tracked window closes.

The window contents come from grim's toplevel capture, which also works for
windows on other workspaces. The slot and the size are kept in $STATE.
"""

import json
import math
import os
import signal
import socket
import subprocess
import sys

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("GLibUnix", "2.0")
gi.require_version("GtkLayerShell", "0.1")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import (  # noqa: E402
    Gdk,
    GdkPixbuf,
    Gio,
    GLib,
    GLibUnix,
    Gtk,
    GtkLayerShell,
    Pango,
    PangoCairo,
)

APP_ID = "minimap"
SCREEN_WIDTH = int("@screenWidth@")
SCREEN_HEIGHT = int("@screenHeight@")
# The bar on top of the screen. The top slots stay clear of it.
BAR = int("@bar@")
# The bar at the bottom. The bottom slots and the drag limit stay clear of it.
BOTTOM_BAR = int("@bottomBar@")
GRIM = "@grim@"
HYPRCTL = "@hyprctl@"
STATE = "@state@"

# Gap between the minimap and the screen edge.
PAD = 24
BORDER = 2
# Size is the long edge of the captured window, before the border.
MIN_SIZE = 160
MAX_SIZE = 640
DEFAULT_SIZE = 384
# One scroll notch changes the size by this factor.
STEP = 1.125
# Bottom right.
DEFAULT_SLOT = 8
# Capture interval. It backs off while the window does not change.
FAST_MS = 200
SLOW_MS = 1000
# Window size used for the placeholder before the first frame arrives.
UNKNOWN = (16, 9)

CSS = b"""
* { font-family: "VGA", monospace; font-size: 11pt; }
menu { background: @surface@; border: 2px solid @border@; border-radius: 0; box-shadow: none; padding: 0; }
menuitem { background: transparent; color: @border@; border-radius: 0; margin: 0; box-shadow: none; padding: 4px 12px; }
menuitem:hover { background: @text@; color: @surface@; }
.csd.popup decoration, window.popup decoration { box-shadow: none; border-radius: 0; margin: 0; }
"""

SURFACE = Gdk.RGBA()
SURFACE.parse("@surface@")
FRAME = Gdk.RGBA()
FRAME.parse("@border@")
DIM = Gdk.RGBA()
DIM.parse("@outline@")
INK = Gdk.RGBA()
INK.parse("@text@")
ALERT = Gdk.RGBA()
ALERT.parse("@alert@")

# The tape overlay. The text needs this much picture height. A smaller
# minimap would be mostly text, so it shows the picture and the corner marks
# only.
TEXT_MIN_H = 100
# The CRT look of the feed: dark rows in every few, and a faint band that
# rolls down once per roll period. The picture is redrawn this many times a
# second so the band moves.
FPS = 20
SCAN_PERIOD = 4
SCAN_ROWS = 2
SCAN_ALPHA = 0.3
ROLL_S = 9.0
BAND = 12
BAND_ALPHA = 0.10
# The vignette: clear in the middle and dark towards the corners.
VIGNETTE_CLEAR = 0.55
VIGNETTE_ALPHA = 0.6
# The corner marks are as thick as the rice's borders and sit in the corners
# of the surface, like a second border. Each arm is this long. The inset is
# to the middle of a mark, which leaves 2px of space around it.
MARK_ARM = 14
MARK_INSET = 5
# The text sits inside the angle of the marks, 3px below the horizontal arms
# and 4px past the vertical ones.
TEXT_TOP = MARK_INSET + 1 + 3
TEXT_PAD = MARK_INSET + 1 + 4
# The least room that is worth a label, which is three letters.
LABEL_MIN = 24


def clock(elapsed):
    """hh:mm:ss for a time in seconds."""
    whole = int(elapsed)
    return f"{whole // 3600:02d}:{whole // 60 % 60:02d}:{whole % 60:02d}"


def set_color(cr, color, alpha=1.0):
    cr.set_source_rgba(color.red, color.green, color.blue, alpha)


def text(cr, string, x, y, color, width=None, right=False):
    """Draw one line of text with its top at y. Returns its pixel size.

    A width makes a longer line end in an ellipsis. Right puts x at the
    right edge of the text.
    """
    layout = PangoCairo.create_layout(cr)
    layout.set_font_description(Pango.FontDescription("VGA 11"))
    layout.set_text(string, -1)
    if width is not None:
        layout.set_width(max(0, width) * Pango.SCALE)
        layout.set_ellipsize(Pango.EllipsizeMode.END)
    text_w, text_h = layout.get_pixel_size()
    left = x - text_w if right else x
    # A dark copy one pixel down and right keeps the text readable on any
    # picture.
    cr.move_to(left + 1, y + 1)
    set_color(cr, Gdk.RGBA(0, 0, 0, 1), 0.8)
    PangoCairo.show_layout(cr, layout)
    cr.move_to(left, y)
    set_color(cr, color)
    PangoCairo.show_layout(cr, layout)
    return text_w, text_h


def measure(cr, string):
    """Pixel width of a line of text."""
    layout = PangoCairo.create_layout(cr)
    layout.set_font_description(Pango.FontDescription("VGA 11"))
    layout.set_text(string, -1)
    return layout.get_pixel_size()[0]


def line_height(cr):
    layout = PangoCairo.create_layout(cr)
    layout.set_font_description(Pango.FontDescription("VGA 11"))
    layout.set_text("M", -1)
    return layout.get_pixel_size()[1]


def draw_tape(cr, x, y, w, h, elapsed, label, win_size, workspace):
    """Draw the VHS overlay over the picture in the box at x, y, w by h."""
    cr.save()
    cr.rectangle(x, y, w, h)
    cr.clip()

    # Scanlines.
    set_color(cr, Gdk.RGBA(0, 0, 0, 1), SCAN_ALPHA)
    for row in range(y, y + h, SCAN_PERIOD):
        cr.rectangle(x, row, w, SCAN_ROWS)
    cr.fill()

    # The tracking band, from just above the picture to its bottom.
    band = y - BAND + (elapsed % ROLL_S) / ROLL_S * (h + BAND)
    set_color(cr, INK, BAND_ALPHA)
    cr.rectangle(x, band, w, BAND)
    cr.fill()

    # The vignette, stretched to the shape of the picture.
    cr.save()
    cr.translate(x + w / 2, y + h / 2)
    cr.scale(w, h)
    vignette = cairo.RadialGradient(0, 0, 0, 0, 0, 0.62)
    vignette.add_color_stop_rgba(VIGNETTE_CLEAR, 0, 0, 0, 0)
    vignette.add_color_stop_rgba(1.0, 0, 0, 0, VIGNETTE_ALPHA)
    cr.set_source(vignette)
    cr.rectangle(-0.5, -0.5, 1, 1)
    cr.fill()
    cr.restore()

    line = line_height(cr)
    if h >= TEXT_MIN_H:
        # The top row: the clock on the left and the window's size on the
        # right. The size is left out when the clock would not fit beside it.
        # A text that does not fit is left out, not cut.
        top_row = y + TEXT_TOP
        live_w = measure(cr, "LIVE ")
        clock_w = measure(cr, clock(elapsed))
        room = w - 2 * TEXT_PAD - live_w - clock_w
        if room >= 0:
            text(cr, "LIVE ", x + TEXT_PAD, top_row, ALERT)
            text(cr, clock(elapsed), x + TEXT_PAD + live_w, top_row, INK)
            if win_size is not None:
                size = f"{win_size[0]}x{win_size[1]}"
                if room - 8 >= measure(cr, size):
                    text(cr, size, x + w - TEXT_PAD, top_row, INK, right=True)
        # The bottom row: the window's class on the left and the workspace on
        # the right. The workspace is left out when the class would not fit
        # whole beside it.
        bottom_row = y + h - TEXT_TOP - line
        room = w - 2 * TEXT_PAD
        if room >= LABEL_MIN:
            if workspace:
                short = workspace.removeprefix("special:")
                for name in (f"Workspace {short}", f"WS {short}"):
                    name_w = measure(cr, name) + 8
                    if room - name_w >= measure(cr, label):
                        text(cr, name, x + w - TEXT_PAD, bottom_row, DIM, right=True)
                        room -= name_w
                        break
            text(cr, label, x + TEXT_PAD, bottom_row, INK, width=room)

    # The viewfinder's corner marks.
    set_color(cr, FRAME)
    cr.set_line_width(BORDER)
    for cx, dx in ((x + MARK_INSET, 1), (x + w - MARK_INSET, -1)):
        for cy, dy in ((y + MARK_INSET, 1), (y + h - MARK_INSET, -1)):
            cr.move_to(cx, cy + dy * MARK_ARM)
            cr.line_to(cx, cy)
            cr.line_to(cx + dx * MARK_ARM, cy)
    cr.stroke()
    cr.restore()


def content(size, win_w, win_h):
    """Fit a win_w x win_h window into a box of size x size pixels."""
    scale = size / max(win_w, win_h)
    return max(1, round(win_w * scale)), max(1, round(win_h * scale))


def slots(outer_w, outer_h):
    """Top left corners of the 16 slots, clockwise from the top left.

    Slots 0-4 run along the top, 5-7 down the right side, 8-12 back along
    the bottom and 13-15 up the left side. The corners belong to the top
    and bottom rows. Every coordinate is the corner of a surface of the
    given outer size, so the minimap keeps its padding at any size.
    """
    left = PAD
    right = SCREEN_WIDTH - PAD - outer_w
    top = BAR + PAD
    bottom = SCREEN_HEIGHT - BOTTOM_BAR - PAD - outer_h

    def lerp(a, b, i):
        return math.floor(a + (b - a) * i / 4 + 0.5)

    row = [lerp(left, right, i) for i in range(5)]
    column = [lerp(top, bottom, j) for j in range(5)]
    return (
        [(x, top) for x in row]
        + [(right, y) for y in column[1:4]]
        + [(x, bottom) for x in reversed(row)]
        + [(left, y) for y in reversed(column[1:4])]
    )


def nearest(x, y, outer_w, outer_h):
    """Index of the slot closest to a surface whose top left is at x, y."""
    corners = slots(outer_w, outer_h)
    return min(range(len(corners)), key=lambda i: (corners[i][0] - x) ** 2 + (corners[i][1] - y) ** 2)


def clamp(value, low, high):
    return max(low, min(high, value))


def load_state():
    """The saved slot and size, or the defaults when the file is unusable."""
    try:
        with open(STATE) as f:
            data = json.load(f)
        slot = int(data["slot"])
        size = int(data["size"])
    except (OSError, ValueError, KeyError, TypeError):
        return DEFAULT_SLOT, DEFAULT_SIZE
    return clamp(slot, 0, 15), clamp(size, MIN_SIZE, MAX_SIZE)


def save_state(slot, size):
    try:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        tmp = STATE + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"slot": slot, "size": size}, f)
        os.replace(tmp, STATE)
    except OSError:
        pass


def hypr_path(name):
    runtime = os.environ["XDG_RUNTIME_DIR"]
    return os.path.join(runtime, "hypr", os.environ["HYPRLAND_INSTANCE_SIGNATURE"], name)


def hypr_request(command):
    """Send one request to Hyprland's command socket and return the reply."""
    with socket.socket(socket.AF_UNIX) as sock:
        sock.connect(hypr_path(".socket.sock"))
        sock.sendall(command.encode())
        chunks = []
        while True:
            data = sock.recv(65536)
            if not data:
                break
            chunks.append(data)
    return b"".join(chunks).decode()


def hypr_json(command):
    try:
        return json.loads(hypr_request(command))
    except (OSError, ValueError):
        return None


def dispatch(expression):
    """Run a Lua dispatcher. This Hyprland build only takes Lua syntax."""
    subprocess.run([HYPRCTL, "dispatch", expression], stdout=subprocess.DEVNULL, check=False)


def go_to(address):
    """Show and focus a window, whichever workspace it is on.

    A window on a special workspace needs that workspace toggled on. A
    window on a regular workspace is hidden behind the special workspace
    that is showing, so that one is toggled off before the focus moves.
    """
    clients = hypr_json("j/clients") or []
    monitors = hypr_json("j/monitors") or []
    target = next((c for c in clients if c["address"] == address), None)
    if target is None:
        return
    shown = next((m["specialWorkspace"]["name"] for m in monitors if m["focused"]), "")
    workspace = target["workspace"]["name"]
    if workspace.startswith("special:"):
        if shown != workspace:
            dispatch(f"hl.dsp.workspace.toggle_special({json.dumps(workspace[len('special:'):])})")
    elif shown:
        dispatch(f"hl.dsp.workspace.toggle_special({json.dumps(shown[len('special:'):])})")
    dispatch(f"hl.dsp.focus({{ window = {json.dumps('address:' + address)} }})")


class Minimap:
    def __init__(self, stable_id, address):
        self.stable_id = stable_id
        self.address = address
        self.slot, self.size = load_state()
        self.frame = None
        self.scaled = None
        self.last_bytes = None
        self.win_size = UNKNOWN
        self.failures = 0
        self.interval = FAST_MS
        self.dragging = False
        self.drag_cursor = (0, 0)
        self.drag_margin = (0, 0)
        self.scroll = 0.0
        self.save_timer = 0
        self.started = GLib.get_monotonic_time()
        info = next((c for c in hypr_json("j/clients") or [] if c["address"] == address), None)
        self.label = info["class"] if info else "window"
        self.workspace = info["workspace"]["name"] if info else ""
        self.ticks = 0

        self.window = Gtk.Window()
        self.window.set_title(APP_ID)
        self.window.set_decorated(False)
        GtkLayerShell.init_for_window(self.window)
        GtkLayerShell.set_namespace(self.window, APP_ID)
        GtkLayerShell.set_layer(self.window, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self.window, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self.window, GtkLayerShell.Edge.LEFT, True)
        # -1 makes the margins count from the screen edge instead of from
        # the edge of the bar's exclusive zone.
        GtkLayerShell.set_exclusive_zone(self.window, -1)
        GtkLayerShell.set_keyboard_mode(self.window, GtkLayerShell.KeyboardMode.NONE)

        self.area = Gtk.DrawingArea()
        self.area.add_events(
            Gdk.EventMask.BUTTON_PRESS_MASK
            | Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.POINTER_MOTION_MASK
            | Gdk.EventMask.SCROLL_MASK
            | Gdk.EventMask.SMOOTH_SCROLL_MASK
        )
        self.area.connect("draw", self.on_draw)
        self.area.connect("button-press-event", self.on_press)
        self.area.connect("button-release-event", self.on_release)
        self.area.connect("motion-notify-event", self.on_motion)
        self.area.connect("scroll-event", self.on_scroll)
        self.window.add(self.area)

        self.menu = Gtk.Menu()
        for text, action in (("Go to window", self.on_go), ("Stop tracking", self.quit)):
            item = Gtk.MenuItem.new_with_label(text)
            item.connect("activate", action)
            self.menu.append(item)
        self.menu.show_all()
        self.menu.attach_to_widget(self.area, None)

        self.layout()
        self.window.show_all()
        GLib.timeout_add(0, self.capture)
        GLib.timeout_add(1000 // FPS, self.tick)
        self.watch_events()

    # Geometry.

    def outer(self):
        """Width and height of the surface, border included."""
        w, h = content(self.size, *self.win_size)
        return w + 2 * BORDER, h + 2 * BORDER

    def layout(self):
        """Apply the size and put the surface on its slot."""
        w, h = content(self.size, *self.win_size)
        outer_w, outer_h = w + 2 * BORDER, h + 2 * BORDER
        self.area.set_size_request(outer_w, outer_h)
        self.window.set_size_request(outer_w, outer_h)
        self.window.resize(outer_w, outer_h)
        x, y = slots(outer_w, outer_h)[self.slot]
        self.place(x, y)
        if self.frame is not None:
            self.scaled = self.frame.scale_simple(w, h, GdkPixbuf.InterpType.BILINEAR)
        self.area.queue_draw()

    def place(self, x, y):
        GtkLayerShell.set_margin(self.window, GtkLayerShell.Edge.LEFT, x)
        GtkLayerShell.set_margin(self.window, GtkLayerShell.Edge.TOP, y)

    def margins(self):
        return (
            GtkLayerShell.get_margin(self.window, GtkLayerShell.Edge.LEFT),
            GtkLayerShell.get_margin(self.window, GtkLayerShell.Edge.TOP),
        )

    # Drawing.

    def elapsed(self):
        return (GLib.get_monotonic_time() - self.started) / 1e6

    def tick(self):
        """Redraw for the clock and the rolling band. Every two seconds it
        also looks up the workspace, which changes when the window moves."""
        self.ticks += 1
        if self.ticks % (2 * FPS) == 0:
            info = next((c for c in hypr_json("j/clients") or [] if c["address"] == self.address), None)
            if info is not None:
                self.workspace = info["workspace"]["name"]
        self.area.queue_draw()
        return True

    def on_draw(self, _area, cr):
        width, height = self.outer()
        Gdk.cairo_set_source_rgba(cr, SURFACE)
        cr.paint()
        if self.scaled is not None:
            Gdk.cairo_set_source_pixbuf(cr, self.scaled, BORDER, BORDER)
            cr.paint()
        else:
            layout = PangoCairo.create_layout(cr)
            layout.set_font_description(Pango.FontDescription("VGA 11"))
            layout.set_text(self.label, -1)
            text_w, text_h = layout.get_pixel_size()
            Gdk.cairo_set_source_rgba(cr, DIM)
            cr.move_to((width - text_w) / 2, (height - text_h) / 2)
            PangoCairo.show_layout(cr, layout)
        known = self.win_size if self.frame is not None else None
        draw_tape(cr, BORDER, BORDER, width - 2 * BORDER, height - 2 * BORDER, self.elapsed(), self.label, known, self.workspace)
        Gdk.cairo_set_source_rgba(cr, FRAME)
        cr.set_line_width(BORDER)
        cr.rectangle(BORDER / 2, BORDER / 2, width - BORDER, height - BORDER)
        cr.stroke()
        return False

    # Capture. At most one grim runs at a time and the next one is
    # scheduled when the last finishes, so a slow capture never piles up.

    def capture(self):
        if self.dragging:
            GLib.timeout_add(FAST_MS, self.capture)
            return False
        proc = Gio.Subprocess.new(
            [GRIM, "-T", self.stable_id, "-t", "ppm", "-"],
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE,
        )
        proc.communicate_async(None, None, self.captured)
        return False

    def captured(self, proc, result):
        frame = None
        try:
            _, out, _ = proc.communicate_finish(result)
            # grim can crash instead of exiting 1 when a capture fails, so
            # any status other than a clean exit counts as a failure.
            if proc.get_if_exited() and proc.get_exit_status() == 0:
                frame = self.parse(out)
        except GLib.Error:
            pass
        if frame is None:
            self.failures += 1
            self.interval = SLOW_MS
            if self.failures >= 3 and not self.exists():
                self.quit()
                return
        else:
            self.failures = 0
            self.show(frame)
        GLib.timeout_add(self.interval, self.capture)

    def parse(self, out):
        """Turn grim's P6 output into a pixbuf, or None if it is not one."""
        data = out.get_data()
        if data[:2] != b"P6":
            return None
        # A truncated or garbled header must end the scan and return None.
        # An exception here would skip the timer in captured() and freeze
        # the minimap.
        fields = []
        offset = 2
        size = len(data)
        while len(fields) < 3:
            while offset < size and data[offset : offset + 1].isspace():
                offset += 1
            end = offset
            while end < size and not data[end : end + 1].isspace():
                end += 1
            if end == size or not data[offset:end].isdigit():
                return None
            fields.append(int(data[offset:end]))
            offset = end
        offset += 1
        width, height, maxval = fields
        # The stride below assumes 8-bit samples.
        if width == 0 or height == 0 or maxval != 255:
            return None
        if size - offset < width * height * 3:
            return None
        body = GLib.Bytes.new_from_bytes(out, offset, width * height * 3)
        return GdkPixbuf.Pixbuf.new_from_bytes(
            body, GdkPixbuf.Colorspace.RGB, False, 8, width, height, width * 3
        ), out

    def show(self, parsed):
        pixbuf, out = parsed
        if self.last_bytes is not None and out.equal(self.last_bytes):
            self.interval = min(SLOW_MS, self.interval * 2)
            return
        self.last_bytes = out
        self.interval = FAST_MS
        self.frame = pixbuf
        size = (pixbuf.get_width(), pixbuf.get_height())
        if size != self.win_size:
            self.win_size = size
            self.layout()
        else:
            w, h = content(self.size, *size)
            self.scaled = pixbuf.scale_simple(w, h, GdkPixbuf.InterpType.BILINEAR)
            self.area.queue_draw()

    # Following the tracked window.

    def exists(self):
        clients = hypr_json("j/clients")
        return clients is None or any(c["address"] == self.address for c in clients)

    def watch_events(self):
        """Quit when Hyprland reports the tracked window closing."""
        try:
            conn = Gio.SocketClient().connect(Gio.UnixSocketAddress.new(hypr_path(".socket2.sock")), None)
        except GLib.Error:
            return
        self.events = Gio.DataInputStream.new(conn.get_input_stream())
        self.events.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_event)

    def on_event(self, stream, result):
        try:
            line, _ = stream.read_line_finish_utf8(result)
        except GLib.Error:
            return
        if line is None:
            return
        if line == "closewindow>>" + self.address.removeprefix("0x"):
            self.quit()
            return
        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_event)

    # Pointer.

    def cursor(self):
        pos = hypr_json("j/cursorpos")
        return (pos["x"], pos["y"]) if pos else self.drag_cursor

    def on_press(self, _area, event):
        if event.button == 1:
            self.dragging = True
            self.drag_cursor = self.cursor()
            self.drag_margin = self.margins()
        elif event.button == 3:
            self.menu.popup_at_pointer(event)
        return True

    def on_motion(self, _area, event):
        if not self.dragging:
            return False
        # A release the surface never saw would leave the drag stuck, so a
        # motion without the button held ends it.
        if not event.state & Gdk.ModifierType.BUTTON1_MASK:
            self.end_drag()
            return True
        x, y = self.cursor()
        outer_w, outer_h = self.outer()
        new_x = round(self.drag_margin[0] + x - self.drag_cursor[0])
        new_y = round(self.drag_margin[1] + y - self.drag_cursor[1])
        self.place(
            clamp(new_x, 0, SCREEN_WIDTH - outer_w),
            clamp(new_y, 0, SCREEN_HEIGHT - BOTTOM_BAR - outer_h),
        )
        return True

    def on_release(self, _area, event):
        if event.button == 1 and self.dragging:
            self.end_drag()
        return True

    def end_drag(self):
        self.dragging = False
        self.slot = nearest(*self.margins(), *self.outer())
        self.layout()
        save_state(self.slot, self.size)

    def on_scroll(self, _area, event):
        if event.direction == Gdk.ScrollDirection.UP:
            self.scroll -= 1
        elif event.direction == Gdk.ScrollDirection.DOWN:
            self.scroll += 1
        elif event.direction == Gdk.ScrollDirection.SMOOTH:
            _, _, dy = event.get_scroll_deltas()
            self.scroll += dy
        else:
            return False
        steps = int(self.scroll)
        if steps == 0:
            return True
        self.scroll -= steps
        # Scrolling up grows the minimap.
        size = round(self.size * STEP ** (-steps))
        self.size = clamp(size, MIN_SIZE, MAX_SIZE)
        self.layout()
        if self.save_timer:
            GLib.source_remove(self.save_timer)
        self.save_timer = GLib.timeout_add(500, self.save_later)
        return True

    def save_later(self):
        self.save_timer = 0
        save_state(self.slot, self.size)
        return False

    # Menu and exit.

    def on_go(self, _item):
        go_to(self.address)

    def quit(self, *_args):
        save_state(self.slot, self.size)
        Gtk.main_quit()
        return False


def main():
    if len(sys.argv) != 3:
        print(__doc__.split("\n\n")[0].split("\n")[0], file=sys.stderr)
        print("usage: minimap STABLE-ID ADDRESS", file=sys.stderr)
        sys.exit(2)
    GLib.set_prgname(APP_ID)
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )
    minimap = Minimap(sys.argv[1], sys.argv[2])
    for sig in (signal.SIGTERM, signal.SIGINT):
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, sig, minimap.quit)
    Gtk.main()


if __name__ == "__main__":
    main()

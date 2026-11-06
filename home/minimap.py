#!/usr/bin/env python3
"""Floating minimap of one window.

usage: minimap STABLE-ID ADDRESS

A small live copy of the window with the given Hyprland stableId, drawn on
the overlay layer so it stays above every window. It sits in one of 16
slots around the screen edge: five along the top and the bottom (corners
included) and three along each side. Drag it with the left button and it
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
    bottom = SCREEN_HEIGHT - PAD - outer_h

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
        info = next((c for c in hypr_json("j/clients") or [] if c["address"] == address), None)
        self.label = info["class"] if info else "window"

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
            clamp(new_y, 0, SCREEN_HEIGHT - outer_h),
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

-- Floating windows from the Super + Alt launch keys (keybinds.nix). Each one
-- opens as a golden rectangle: its width is a share of the work area and its
-- height is 0.618 of its width. It sits at the centre and ends up on top. The
-- other windows are left alone, and nothing is resized or moved after the
-- window has opened.
--
-- Windows that open on the same workspace would land on exactly the same
-- spot and hide one another. Each one takes the first free slot instead. Slot
-- 0 is the centre, and every further slot sits one step down and to the
-- right. The slots stop where the window would leave the work area. When all
-- are taken, the one with the fewest windows is used again. A slot is free
-- again when its window closes, is tiled again or moves to another
-- workspace. A config reload forgets the slots, so a window opened after it
-- can land on top of an older one.
--
-- Super + Shift + arrow moves a floating window by a fixed step. It moves a
-- tiled window to the neighbouring spot in the layout, as Hyprland does.
--
-- The nix module fills the @name@ values in. The area is the work area in
-- whole pixels.

local RATIO = @ratio@
local SHARE = @share@
local MOVE_STEP = @moveStep@
local STEP = @step@
local ARM_MS = @armMs@
local AREA = { x = @areaX@, y = @areaY@, w = @areaW@, h = @areaH@ }

local function round(x)
    return math.floor(x + 0.5)
end

-- The window size. A work area that is wider than it is tall by less than the
-- golden ratio would push the height out of the area, so both shrink.
local WIDTH = round(AREA.w * SHARE)
local HEIGHT = round(WIDTH * RATIO)
if HEIGHT > AREA.h then
    HEIGHT = AREA.h
    WIDTH = round(HEIGHT / RATIO)
end

-- The slot count follows from half of the room around the window, since the
-- slots start at the centre and move away from it in one direction.
local SLOTS = math.floor(math.min(AREA.w - WIDTH, AREA.h - HEIGHT) / 2 / STEP) + 1

local function slot_position(index)
    return AREA.x + round((AREA.w - WIDTH) / 2) + index * STEP, AREA.y + round((AREA.h - HEIGHT) / 2) + index * STEP
end

floating = {}

local function selector(window)
    return "address:" .. window.address
end

-- Special-workspace windows are overlays with a fixed frame.
local function is_special(window)
    return window.workspace and window.workspace.special
end

-- The slot of each window that was opened here, by address.
local slots = {}

-- The lowest slot that no floating window of the workspace holds. The live
-- window list is the source of truth, so a window that was closed, tiled
-- again or moved away has already freed its slot.
local function free_slot(workspace)
    local live = {}
    for _, window in ipairs(hl.get_workspace_windows(workspace)) do
        if window.floating then
            live[window.address] = true
        end
    end
    local used = {}
    for index = 0, SLOTS - 1 do
        used[index] = 0
    end
    for address, slot in pairs(slots) do
        if slot.workspace == workspace and live[address] then
            used[slot.index] = used[slot.index] + 1
        end
    end
    local best = 0
    for index = 1, SLOTS - 1 do
        if used[index] < used[best] then
            best = index
        end
    end
    return best
end

function floating.into_layout(window)
    local workspace = window.workspace and window.workspace.id
    local index = workspace and free_slot(workspace) or 0
    local x, y = slot_position(index)
    if workspace then
        slots[window.address] = { index = index, workspace = workspace }
    end
    hl.dispatch(hl.dsp.window.float({ window = selector(window), action = "enable" }))
    hl.dispatch(hl.dsp.window.resize({ window = selector(window), x = WIDTH, y = HEIGHT }))
    hl.dispatch(hl.dsp.window.move({ window = selector(window), x = x, y = y }))
    hl.dispatch(hl.dsp.window.alter_zorder({ window = selector(window), mode = "top" }))
end

-- A floating window has a position of its own, so it moves by pixels. Any
-- other window takes Hyprland's move in that direction.
local DIRECTIONS = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }

function floating.nudge(direction)
    local window = hl.get_active_window()
    if not window then
        return
    end
    if window.floating and not is_special(window) and window.at then
        local step = DIRECTIONS[direction]
        hl.dispatch(hl.dsp.window.move({
            window = selector(window),
            x = window.at.x + step[1] * MOVE_STEP,
            y = window.at.y + step[2] * MOVE_STEP,
        }))
    else
        hl.dispatch(hl.dsp.window.move({ direction = direction }))
    end
end

-- Launch a command and float the first window of the given classes that
-- opens in the next few seconds. Hyprland's own exec rules follow the
-- process it started. The launcher hands the command to a daemon, so that
-- process never owns the window and the rules would never match.
local armed = nil
local arm_count = 0

function floating.launch(patterns, command)
    arm_count = arm_count + 1
    local mine = arm_count
    armed = patterns
    hl.timer(function()
        if mine == arm_count then
            armed = nil
        end
    end, { timeout = ARM_MS, type = "oneshot" })
    hl.dispatch(hl.dsp.exec_cmd(command))
end

-- A terminal opened while an overlay is up first lands on the overlay's
-- special workspace. The window.open hook in keybinds.nix moves it to the
-- regular workspace and hides the overlay. That hook is registered first, so
-- it runs before this one, which then floats the window. A floating window
-- would stay on the special workspace, so the order matters.
hl.on("window.open", function(window)
    if not armed or window.floating then
        return
    end
    for _, pattern in ipairs(armed) do
        if string.find(window.class or "", pattern) then
            armed = nil
            floating.into_layout(window)
            return
        end
    end
end)

local function forget(window)
    slots[window.address] = nil
end

hl.on("window.close", forget)
hl.on("window.destroy", forget)

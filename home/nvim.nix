{
  config,
  lib,
  palette,
  ...
}:
let
  ansi = palette.ansi.regular ++ palette.ansi.bright;
  terminalColours = builtins.concatStringsSep "\n" (
    builtins.genList (i: ''vim.g.terminal_color_${toString i} = "${builtins.elemAt ansi i}"'') 16
  );
  # Neovim's colour scheme, generated from palette.nix so the hex values
  # live in one place. Each highlight group gets a colour role, the same
  # mapping as vim/0xNix.vim. The statusline and netrw groups exist only
  # here. The netrw name groups follow GNU ls's default colours. The editor
  # background stays transparent, so the terminal's shows through.
  # Tree-sitter captures link to the classic groups below, so only the
  # captures that need a different colour are set explicitly.
  colorscheme = ''
    vim.cmd.highlight("clear")
    if vim.fn.exists("syntax_on") == 1 then
      vim.cmd.syntax("reset")
    end
    vim.o.background = "dark"
    vim.g.colors_name = "0xNix"

    local groups = {
      -- Editor UI
      Normal = { fg = "${palette.text}", bg = "NONE" },
      NormalFloat = { fg = "${palette.text}", bg = "${palette.surface}" },
      FloatBorder = { fg = "${palette.border}", bg = "${palette.surface}" },
      CursorLine = { bg = "${palette.surfaceContainerHigh}" },
      CursorLineNr = { fg = "${palette.border}", bold = true },
      LineNr = { fg = "${palette.outline}" },
      -- The line between the numbers and the text matches window splits.
      LineNrSeparator = { link = "WinSeparator" },
      SignColumn = { bg = "NONE" },
      WinSeparator = { fg = "${palette.outlineVariant}", bg = "NONE" },
      MatchParen = { fg = "${palette.border}", bold = true, underline = true },
      NonText = { fg = "${palette.outline}", bg = "NONE" },
      EndOfBuffer = { fg = "${palette.outlineVariant}" },
      Whitespace = { fg = "${palette.outlineVariant}" },
      SpecialKey = { fg = "${palette.outlineVariant}" },
      ColorColumn = { bg = "${palette.surfaceContainer}" },
      Folded = { fg = "${palette.textDim}", bg = "${palette.surfaceContainer}" },
      Conceal = { fg = "${palette.textDim}", bg = "NONE" },

      -- Selection and search
      Visual = { fg = "${palette.surface}", bg = "${palette.text}" },
      Search = { fg = "${palette.surface}", bg = "${palette.disk}" },
      IncSearch = { fg = "${palette.surface}", bg = "${palette.border}" },
      CurSearch = { fg = "${palette.surface}", bg = "${palette.border}" },

      -- Completion menu
      Pmenu = { fg = "${palette.text}", bg = "${palette.surfaceContainerHigh}" },
      PmenuSel = { fg = "${palette.surface}", bg = "${palette.text}", bold = true },
      PmenuSbar = { bg = "${palette.surfaceContainerHighest}" },
      PmenuThumb = { bg = "${palette.outline}" },

      -- Statusline, tabline and messages
      StatusLine = { fg = "${palette.text}", bg = "NONE" },
      StatusLineNC = { fg = "${palette.textDim}", bg = "NONE" },
      StatusLineDim = { fg = "${palette.textDim}", bg = "NONE" },
      -- The mode block. Normal mode is reverse video, like fuzzel's
      -- selection. The other modes take waybar's stat hues.
      StatusModeNormal = { fg = "${palette.surface}", bg = "${palette.border}", bold = true },
      StatusModeInsert = { fg = "${palette.surface}", bg = "${palette.gpu}", bold = true },
      StatusModeVisual = { fg = "${palette.surface}", bg = "${palette.memory}", bold = true },
      StatusModeReplace = { fg = "${palette.surface}", bg = "${palette.swap}", bold = true },
      StatusModeCommand = { fg = "${palette.surface}", bg = "${palette.disk}", bold = true },
      StatusModeTerminal = { fg = "${palette.surface}", bg = "${palette.cpu}", bold = true },
      TabLine = { fg = "${palette.textDim}", bg = "NONE" },
      TabLineFill = { bg = "NONE" },
      TabLineSel = { fg = "${palette.border}", bg = "NONE", bold = true },
      ErrorMsg = { fg = "${palette.alert}" },
      WarningMsg = { fg = "${palette.disk}" },
      MoreMsg = { fg = "${palette.gpu}" },
      Question = { fg = "${palette.gpu}" },

      -- Spell
      SpellBad = { sp = "${palette.alert}", undercurl = true },
      SpellCap = { sp = "${palette.disk}", undercurl = true },
      SpellRare = { sp = "${palette.memory}", undercurl = true },
      SpellLocal = { sp = "${palette.swap}", undercurl = true },

      -- Diff
      DiffAdd = { bg = "${palette.diffAdd}" },
      DiffChange = { bg = "${palette.diffChange}" },
      DiffDelete = { bg = "${palette.diffDelete}" },
      DiffText = { bg = "${palette.diffText}" },
      Added = { fg = "${palette.gpu}" },
      Changed = { fg = "${palette.disk}" },
      Removed = { fg = "${palette.alert}" },

      -- Diagnostics
      DiagnosticError = { fg = "${palette.alert}" },
      DiagnosticWarn = { fg = "${palette.disk}" },
      DiagnosticInfo = { fg = "${palette.cpu}" },
      DiagnosticHint = { fg = "${palette.swap}" },
      DiagnosticOk = { fg = "${palette.gpu}" },
      DiagnosticUnderlineError = { sp = "${palette.alert}", undercurl = true },
      DiagnosticUnderlineWarn = { sp = "${palette.disk}", undercurl = true },
      DiagnosticUnderlineInfo = { sp = "${palette.cpu}", undercurl = true },
      DiagnosticUnderlineHint = { sp = "${palette.swap}", undercurl = true },
      DiagnosticUnderlineOk = { sp = "${palette.gpu}", undercurl = true },
      DiagnosticDeprecated = { sp = "${palette.textDim}", strikethrough = true },
      ["@lsp.mod.deprecated"] = { sp = "${palette.textDim}", strikethrough = true },

      -- Groups Neovim colours by default
      CursorColumn = { bg = "${palette.surfaceContainerHigh}" },
      QuickFixLine = { fg = "${palette.cpu}" },
      ModeMsg = { fg = "${palette.gpu}" },
      OkMsg = { fg = "${palette.gpu}" },
      WinBar = { fg = "${palette.text}", bg = "NONE" },
      WinBarNC = { fg = "${palette.textDim}", bg = "NONE" },
      FloatShadow = { bg = "${palette.surfaceContainerHighest}", blend = 80 },
      FloatShadowThrough = { bg = "${palette.surfaceContainerHighest}", blend = 100 },
      PmenuShadow = { bg = "${palette.surfaceContainerHighest}", blend = 80 },
      PmenuShadowThrough = { bg = "${palette.surfaceContainerHighest}", blend = 100 },
      RedrawDebugClear = { bg = "${palette.diffChange}" },
      RedrawDebugComposed = { bg = "${palette.diffAdd}" },
      RedrawDebugRecompose = { bg = "${palette.diffDelete}" },

      -- Syntax
      Comment = { fg = "${palette.textDim}", italic = true },
      String = { fg = "${palette.gpu}" },
      Number = { fg = "${palette.disk}" },
      Boolean = { fg = "${palette.disk}" },
      Constant = { fg = "${palette.disk}" },
      Function = { fg = "${palette.cpu}" },
      Statement = { fg = "${palette.memory}" },
      Operator = { fg = "${palette.swap}" },
      Type = { fg = "${palette.disk}" },
      PreProc = { fg = "${palette.alert}" },
      Special = { fg = "${palette.swap}" },
      Delimiter = { fg = "${palette.textDim}" },
      Error = { fg = "${palette.alert}", bg = "NONE" },
      Todo = { fg = "${palette.surface}", bg = "${palette.disk}", bold = true },
      Title = { fg = "${palette.border}", bold = true },
      Identifier = { fg = "${palette.text}" },
      Directory = { fg = "${palette.cpu}" },

      -- Tree-sitter captures that differ from their fallback groups
      ["@variable"] = { fg = "${palette.text}" },
      ["@variable.builtin"] = { fg = "${palette.swap}" },
      ["@property"] = { fg = "${palette.text}" },
      ["@constructor"] = { fg = "${palette.disk}" },
      ["@punctuation.bracket"] = { fg = "${palette.textDim}" },
      ["@markup.heading"] = { fg = "${palette.border}", bold = true },
      ["@markup.link"] = { fg = "${palette.cpu}", underline = true },

      -- netrw, in GNU ls's default colours as foot draws them. The thin
      -- listing takes each name's colour from ls itself. These cover the
      -- other styles. Executables would otherwise link to PreProc, which
      -- is the alert red.
      netrwDir = { fg = "${palette.nix}", bold = true },
      netrwPlain = { fg = "${palette.text}" },
      netrwSymLink = { fg = "${palette.cpu}", bold = true },
      netrwLink = { fg = "${palette.cpu}", bold = true },
      netrwExe = { fg = "${palette.gpu}", bold = true },
      netrwClassify = { fg = "${palette.textDim}" },
      netrwTreeBar = { fg = "${palette.outlineVariant}" },
      netrwMarkFile = { fg = "${palette.surface}", bg = "${palette.disk}" },
      netrwGray = { fg = "${palette.textDim}" },
      -- The banner box. Its border takes the swap purple. It is the one
      -- hue outside the terminal's 16, so no name in the listing shares it.
      -- The view's settings take waybar's stat hues. The column names sit
      -- on its last line.
      NetrwBorder = { fg = "${palette.swap}" },
      NetrwInfo = { fg = "${palette.textDim}" },
      NetrwLabel = { fg = "${palette.textMuted}" },
      NetrwSort = { fg = "${palette.cpu}", bold = true },
      NetrwDotfiles = { fg = "${palette.disk}", bold = true },
      NetrwView = { fg = "${palette.gpu}", bold = true },
      NetrwHeader = { fg = "${palette.textDim}", underline = true },
    }

    for group, spec in pairs(groups) do
      vim.api.nvim_set_hl(0, group, spec)
    end

    -- The colours of :terminal, the same 16 as foot's.
    ${terminalColours}
  '';
in
{
  config = lib.mkIf config.programs.neovim.enable {
    programs.neovim = {
      initLua = ''
        vim.o.termguicolors = true
        vim.cmd.colorscheme("0xNix")

        -- The cursor line shows its own number. Every other line shows its
        -- distance from the cursor, which is the count for motions like 5j.
        -- Only the number of the cursor line is highlighted, not the line.
        vim.o.number = true
        vim.o.relativenumber = true
        vim.o.cursorline = true
        vim.o.cursorlineopt = "number"
        -- Each number sits centred in a box with a space on either side. The
        -- box fits the buffer's last line number, with room for three digits
        -- at least. A line closes the box off from the text. The signs sit
        -- after the line, so an empty sign column does not push the number
        -- off centre. A two digit number in a three digit box leans left by
        -- half a cell, since a cell cannot split.
        function _G.statuscolumn()
          local win = vim.g.statusline_winid
          -- Neovim draws the column even in windows with numbers off, such
          -- as netrw's.
          if not (vim.wo[win].number or vim.wo[win].relativenumber) then
            return "%s"
          end
          local width = math.max(3, #tostring(vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))))
          local text = ""
          -- Wrapped and virtual lines get a blank column.
          if vim.v.virtnum == 0 then
            local n = vim.v.lnum
            if vim.wo[win].relativenumber and (vim.v.relnum ~= 0 or not vim.wo[win].number) then
              n = vim.v.relnum
            end
            text = tostring(n)
          end
          local left = math.floor((width - #text) / 2)
          local box = " " .. (" "):rep(left) .. text .. (" "):rep(width - #text - left) .. " "
          return box .. "%#LineNrSeparator#│%* %s"
        end
        vim.o.statuscolumn = "%!v:lua.statuscolumn()"

        vim.o.completeopt = "menu,menuone,noselect,popup"
        -- Every popup in the rice has a square border.
        vim.o.winborder = "single"
        vim.diagnostic.config({
          virtual_text = false,
          severity_sort = true,
        })

        -- The statusline. The active window shows the mode, the file, its
        -- diagnostics, the filetype and the cursor position. Other windows
        -- show only the file. In netrw it shows the directory and its total
        -- size, which stay in view when the banner scrolls away.
        vim.o.showmode = false
        local modes = {
          n = { "NORMAL", "StatusModeNormal" },
          i = { "INSERT", "StatusModeInsert" },
          v = { "VISUAL", "StatusModeVisual" },
          V = { "V-LINE", "StatusModeVisual" },
          ["\22"] = { "V-BLOCK", "StatusModeVisual" },
          s = { "SELECT", "StatusModeVisual" },
          S = { "S-LINE", "StatusModeVisual" },
          ["\19"] = { "S-BLOCK", "StatusModeVisual" },
          R = { "REPLACE", "StatusModeReplace" },
          c = { "COMMAND", "StatusModeCommand" },
          r = { "PROMPT", "StatusModeCommand" },
          ["!"] = { "SHELL", "StatusModeTerminal" },
          t = { "TERMINAL", "StatusModeTerminal" },
        }
        local severities = {
          { vim.diagnostic.severity.ERROR, "E", "DiagnosticError" },
          { vim.diagnostic.severity.WARN, "W", "DiagnosticWarn" },
          { vim.diagnostic.severity.INFO, "I", "DiagnosticInfo" },
          { vim.diagnostic.severity.HINT, "H", "DiagnosticHint" },
        }
        function _G.statusline()
          local win = vim.g.statusline_winid
          local buf = vim.api.nvim_win_get_buf(win)
          local netrw = vim.bo[buf].filetype == "netrw"
          local name = "%f %m%r"
          local path = ""
          if netrw then
            path = vim.fn.fnamemodify(vim.b[buf].netrw_shown or vim.b[buf].netrw_curdir or "", ":~")
            -- A literal % in the path would start a statusline item.
            name = path:gsub("%%", "%%%%")
          end
          if win ~= vim.api.nvim_get_current_win() then
            return "%#StatusLineNC# %<" .. name
          end

          local mode = modes[vim.api.nvim_get_mode().mode:sub(1, 1)] or modes.n
          local line = "%#" .. mode[2] .. "# " .. mode[1] .. " %#StatusLine# %<"
          if netrw then
            -- The directory and the total size ls reports. A narrow window
            -- drops the total. A long directory loses its start, so its own
            -- name stays in view.
            local total = vim.b[buf].netrw_total
            local room = vim.api.nvim_win_get_width(win) - #mode[1] - 3 - vim.fn.strdisplaywidth(path) - 2
            line = line .. "%#Title#" .. name
            if total and room >= #total + 8 then
              line = line .. "%#StatusLineDim#  total " .. total
            end
            return line
          end
          line = line .. name .. "%="
          local counts = vim.diagnostic.count(buf)
          for _, s in ipairs(severities) do
            if counts[s[1]] then
              line = line .. "%#" .. s[3] .. "#" .. s[2] .. counts[s[1]] .. " "
            end
          end
          return line .. " %#StatusLineDim#" .. vim.bo[buf].filetype .. "  %#StatusLine#%l:%v %P "
        end
        vim.o.statusline = "%!v:lua.statusline()"
        vim.api.nvim_create_autocmd({ "ModeChanged", "DiagnosticChanged" }, {
          callback = function()
            vim.cmd.redrawstatus()
          end,
        })

        -- netrw. Every entry takes its colour from ls. The tree takes its
        -- details from ls -lah too. The banner becomes a box with the
        -- directory, the view and the common keys, and its last line names
        -- the columns. ? opens a card of all the common keys. F1 still opens
        -- netrw's full help.
        vim.g.netrw_banner = 1
        -- The tree opens first, with the ls columns in front of each name.
        -- i switches to a wide grid of names and back.
        vim.g.netrw_liststyle = 3
        vim.g.netrw_sort_options = "i"
        -- Preview with p in a vertical split.
        vim.g.netrw_preview = 1

        -- ls colours a name with SGR codes. Each set of codes becomes a
        -- highlight group in the terminal's colours, so a name looks the same
        -- as in foot. A colour scheme change clears the groups, so they are
        -- made again after one.
        local function xterm(n)
          if n < 16 then
            return vim.g["terminal_color_" .. n]
          elseif n < 232 then
            local steps = { 0, 95, 135, 175, 215, 255 }
            n = n - 16
            return string.format(
              "#%02x%02x%02x",
              steps[math.floor(n / 36) + 1],
              steps[math.floor(n / 6) % 6 + 1],
              steps[n % 6 + 1]
            )
          end
          local grey = 8 + (n - 232) * 10
          return string.format("#%02x%02x%02x", grey, grey, grey)
        end
        local ls_groups = {}
        vim.api.nvim_create_autocmd("ColorScheme", {
          callback = function()
            ls_groups = {}
          end,
        })
        local function ls_group(codes)
          local name = "NetrwLs_" .. codes:gsub("%D", "_")
          if ls_groups[name] then
            return name
          end
          local list = {}
          for code in codes:gmatch("%d+") do
            table.insert(list, tonumber(code))
          end
          local spec, i = {}, 1
          while i <= #list do
            local c = list[i]
            if c == 1 then
              spec.bold = true
            elseif c == 3 then
              spec.italic = true
            elseif c == 4 then
              spec.underline = true
            elseif c == 7 then
              spec.reverse = true
            elseif c == 9 then
              spec.strikethrough = true
            elseif c >= 30 and c <= 37 then
              spec.fg = xterm(c - 30)
            elseif c >= 40 and c <= 47 then
              spec.bg = xterm(c - 40)
            elseif c >= 90 and c <= 97 then
              spec.fg = xterm(c - 82)
            elseif c >= 100 and c <= 107 then
              spec.bg = xterm(c - 92)
            elseif (c == 38 or c == 48) and list[i + 1] == 5 and list[i + 2] then
              spec[c == 38 and "fg" or "bg"] = xterm(list[i + 2])
              i = i + 2
            elseif (c == 38 or c == 48) and list[i + 1] == 2 and list[i + 4] then
              spec[c == 38 and "fg" or "bg"] = string.format("#%02x%02x%02x", list[i + 2], list[i + 3], list[i + 4])
              i = i + 4
            end
            i = i + 1
          end
          vim.api.nvim_set_hl(0, name, spec)
          ls_groups[name] = true
          return name
        end

        -- Run ls -lah on the directory and read each line back. A line holds
        -- the mode, links, owner, group and size, three date fields, then the
        -- name and a symlink's target. A device shows "major, minor" as its
        -- size. -N prints names without quotes, so they match netrw's.
        local function ls_entries(dir)
          -- A slow filesystem would hold up the listing. After a second the
          -- columns are skipped.
          local result = vim.system({ "ls", "-lahN", "--color=always", "--", dir }, { text = true }):wait(1000)
          if result.code ~= 0 then
            return nil
          end
          local entries, total = {}, nil
          for line in result.stdout:gmatch("[^\n]+") do
            total = total or line:match("^total (%S+)$")
            local fields = { line:match("^(%S+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%d+,%s+%d+)%s+(%S+%s+%S+%s+%S+) (.*)$") }
            if #fields == 0 then
              fields = { line:match("^(%S+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+%s+%S+%s+%S+) (.*)$") }
            end
            if #fields == 7 then
              local rest, codes = table.remove(fields), nil
              -- The name follows its colour codes and ends at the reset.
              -- An uncoloured symlink's name ends at the arrow.
              while true do
                local seq, after = rest:match("^\27%[([%d;]*)m(.*)$")
                if not seq then
                  break
                end
                if seq:match("[1-9]") then
                  codes = seq
                end
                rest = after
              end
              local stop = codes and rest:find("\27[", 1, true)
                or (fields[1]:sub(1, 1) == "l" and rest:find(" -> ", 1, true))
              local name, tail = rest, ""
              if stop then
                name, tail = rest:sub(1, stop - 1), rest:sub(stop)
              end
              fields.codes = codes
              fields.target = tail:gsub("\27%[[%d;]*[mK]", ""):match("^ %-> (.*)$")
              entries[name] = fields
            end
          end
          return entries, total
        end

        -- netrw sets the filetype before it writes a listing, so the
        -- decoration waits until the listing is done. netrw marks a name with
        -- a trailing / * @ | or =, and a symlink with a tab and its target.
        -- Those are hidden, and the target is drawn the way ls shows it.
        local netrw_ns = vim.api.nvim_create_namespace("netrw_ls")

        -- Find the ls entry for a name as netrw shows it. The result is the
        -- entry and the length of the name without netrw's mark.
        local function lookup(entries, shown)
          if not entries then
            return nil
          end
          if entries[shown] then
            return entries[shown], #shown
          end
          if shown:match("[/*@|=]$") and entries[shown:sub(1, -2)] then
            return entries[shown:sub(1, -2)], #shown - 1
          end
        end

        -- Lay out columns for a set of rows. Each column is as wide as its
        -- title or its widest value. The result turns a list of values into
        -- one padded row.
        local function grid(titles, right, items)
          local width = {}
          for i, title in ipairs(titles) do
            width[i] = #title
            for _, item in ipairs(items) do
              width[i] = math.max(width[i], vim.fn.strdisplaywidth(item.values[i]))
            end
          end
          return function(values)
            local out = {}
            for i = 1, #titles do
              local pad = (" "):rep(width[i] - vim.fn.strdisplaywidth(values[i]))
              out[i] = right[i] and pad .. values[i] or values[i] .. pad
            end
            return table.concat(out, " ")
          end
        end
        local function pick(entry, fields)
          local values = {}
          for i, field in ipairs(fields) do
            values[i] = entry[field]
          end
          return values
        end

        -- The tree puts ls -lah's columns in front of each name, except the
        -- size. ls gives a directory one block as its size. That says nothing
        -- about what it holds.
        local lah = {
          fields = { 1, 2, 3, 4, 6 },
          titles = { "Permissions", "Links", "User", "Group", "Modified" },
          right = { [2] = true },
        }

        -- Read each line of the listing into the entries it shows. A tree
        -- line starts with one bar per level. Its directory comes from the
        -- directories above it, so each expanded directory gets its own ls.
        local function netrw_items(style, dir, first, lines, cache, cell)
          local calls = vim.tbl_count(cache)
          local function listing(path)
            if cache[path] == nil then
              -- Each ls can take up to a second, so a tree stops asking
              -- after a few.
              calls = calls + 1
              local entries, total = nil, nil
              if calls <= 12 then
                entries, total = ls_entries(path)
              end
              cache[path] = entries and { entries, total } or false
            end
            return cache[path] and cache[path][1] or nil
          end

          local items = {}
          local function add(row, start, shown, entries)
            local entry, length = lookup(entries, shown)
            if entry then
              table.insert(items, { row = row, start = start, length = length, entry = entry })
            end
          end
          local dirs = { [0] = dir }
          for row = first, #lines do
            local line = lines[row]
            if style == 2 then
              -- The wide view holds names in cells of a fixed width.
              for start = 0, #line - 1, cell or #line do
                local shown = line:sub(start + 1, start + (cell or #line)):gsub("%s+$", "")
                if shown ~= "" then
                  add(row, start, shown, listing(dir))
                end
              end
            elseif style == 3 then
              local depth, pos = 0, 1
              while true do
                if line:sub(pos, pos + 1) == "| " then
                  pos = pos + 2
                elseif line:sub(pos, pos + 3) == "│ " then
                  pos = pos + 4
                else
                  break
                end
                depth = depth + 1
              end
              local shown = line:sub(pos):match("^[^\t]*")
              local item_count = #items
              if depth == 0 then
                -- The top two lines are the parent and the tree's own root.
                local entries = listing(dir)
                local name = shown == "../" and ".." or "."
                if entries and entries[name] then
                  table.insert(items, {
                    row = row,
                    start = pos - 1,
                    length = #shown - 1,
                    entry = entries[name],
                  })
                end
              elseif dirs[depth - 1] then
                add(row, pos - 1, shown, listing(dirs[depth - 1]))
                if shown:sub(-1) == "/" then
                  dirs[depth] = vim.fs.joinpath(dirs[depth - 1], shown:sub(1, -2))
                end
              end
              if #items > item_count then
                items[#items].bars = pos - 1
              end
            end
          end
          listing(dir)
          return items, cache[dir] and cache[dir][2] or nil
        end

        -- The banner's lines are netrw's own, so they sit at the top and
        -- scroll with the listing. Their text is hidden and the box is drawn
        -- over them. netrw's banner has six to eight lines. It grows for name
        -- sorting and for a hiding list. The box holds the directory and the
        -- view, then as many rows of keys as fit.
        local banner_tips = {
          { { "<CR>", "open" }, { "-", "up" }, { "%", "file" }, { "d", "dir" }, { "R", "rename" }, { "D", "delete" } },
          { { "mf", "mark" }, { "mt", "target" }, { "mc", "copy" }, { "mm", "move" }, { "x", "open with app" } },
          { { "gh", "dotfiles" }, { "s", "sort" }, { "r", "reverse" }, { "i", "view" }, { "I", "banner" } },
        }
        local view_names = { [2] = "wide", [3] = "tree" }
        local function chunks_width(chunks)
          local used = 0
          for _, chunk in ipairs(chunks) do
            used = used + vim.fn.strdisplaywidth(chunk[1])
          end
          return used
        end
        local function tip_chunks(tips, room, last)
          local chunks = {}
          if last then
            tips = vim.list_extend(vim.deepcopy(tips), { { "?", "all keys" } })
          end
          for i, tip in ipairs(tips) do
            local cost = #tip[1] + #tip[2] + 3
            -- The ? tip always fits, at the cost of the ones before it.
            if last and i < #tips then
              cost = cost + #"?  all keys  "
            end
            if cost > room then
              if not last then
                break
              end
            else
              table.insert(chunks, { tip[1], "Function" })
              table.insert(chunks, { " " .. tip[2] .. "  ", "NetrwInfo" })
              room = room - #tip[1] - #tip[2] - 3
            end
          end
          return chunks
        end
        local function draw_banner(buf, rows, lines, width, header, view)
          local inner = width - 4
          local function boxed(chunks)
            local out = { { "│ ", "NetrwBorder" } }
            vim.list_extend(out, chunks)
            table.insert(out, { (" "):rep(math.max(0, inner - chunks_width(chunks))) .. " │", "NetrwBorder" })
            return out
          end

          local path = vim.fn.fnamemodify(vim.b[buf].netrw_shown or "", ":~")
          local total = vim.b[buf].netrw_total and "total " .. vim.b[buf].netrw_total or ""
          local room = inner - #total - 2
          if vim.fn.strdisplaywidth(path) > room then
            path = "<" .. vim.fn.strcharpart(path, vim.fn.strchars(path) - room + 1)
          end
          local sort, dotfiles = "name", "shown"
          for i = 1, rows do
            sort = lines[i]:match("^\"%s+Sorted by%s+(%S+)") or sort
            if lines[i]:match("^\"%s+Hiding:") then
              dotfiles = "hidden"
            elseif lines[i]:match("^\"%s+Showing:") then
              dotfiles = "only matches"
            end
          end
          if vim.g.netrw_sort_direction == "reverse" then
            sort = sort .. ", reversed"
          end

          local content = {
            { { path, "Title" }, { (" "):rep(math.max(2, inner - vim.fn.strdisplaywidth(path) - #total)), "NetrwInfo" }, { total, "NetrwInfo" } },
            {
              { "sort ", "NetrwLabel" },
              { sort, "NetrwSort" },
              { "    dotfiles ", "NetrwLabel" },
              { dotfiles, "NetrwDotfiles" },
              { "    view ", "NetrwLabel" },
              { view, "NetrwView" },
            },
          }
          local slots = rows - 2 - (header and 1 or 0)
          local tip_rows = math.min(#banner_tips, slots - #content)
          for i = 1, tip_rows do
            table.insert(content, tip_chunks(banner_tips[i], inner, i == tip_rows))
          end

          local drawn = { { { "┌─ ", "NetrwBorder" }, { "netrw", "Title" }, { " " .. ("─"):rep(width - 10) .. "┐", "NetrwBorder" } } }
          for i = 1, slots do
            table.insert(drawn, boxed(content[i] or {}))
          end
          table.insert(drawn, { { "└" .. ("─"):rep(width - 2) .. "┘", "NetrwBorder" } })
          if header then
            table.insert(drawn, { { header, "NetrwHeader" } })
          end
          for i = 1, rows do
            vim.api.nvim_buf_set_extmark(buf, netrw_ns, i - 1, 0, { end_col = #lines[i], conceal = "" })
            vim.api.nvim_buf_set_extmark(buf, netrw_ns, i - 1, 0, {
              virt_text = drawn[i],
              virt_text_pos = "inline",
              hl_mode = "combine",
            })
          end
        end

        -- fresh marks a new listing from netrw. A resize redraws without it.
        local ls_cache = {}
        local function netrw_decorate(buf, fresh)
          if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "netrw" then
            return
          end
          vim.api.nvim_buf_clear_namespace(buf, netrw_ns, 0, -1)
          local win = vim.fn.bufwinid(buf)
          local style = win ~= -1 and vim.w[win].netrw_liststyle or vim.g.netrw_liststyle
          -- A tree keeps its root while netrw's current directory follows the
          -- last directory expanded. The box and the statusline show the root.
          local dir = vim.b[buf].netrw_curdir
          if style == 3 and win ~= -1 and vim.w[win].netrw_treetop then
            dir = vim.w[win].netrw_treetop
          end
          vim.b[buf].netrw_shown = dir
          vim.b[buf].netrw_total = nil

          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          local rows = 0
          while rows < #lines and lines[rows + 1]:sub(1, 1) == "\"" do
            rows = rows + 1
          end

          -- A huge directory, such as /nix/store, gets plain names. The
          -- details would add seconds to a listing that is already slow. A
          -- redraw reuses the ls output of the listing.
          local items, header = {}, nil
          if fresh or not ls_cache[buf] then
            ls_cache[buf] = {}
          end
          if dir and vim.fn.isdirectory(dir) == 1 and #lines <= 5000 then
            local total
            items, total = netrw_items(style, dir, rows + 1, lines, ls_cache[buf], vim.b[buf].netrw_cpf)
            vim.b[buf].netrw_total = total
          end

          local function mark(row, col, opts)
            vim.api.nvim_buf_set_extmark(buf, netrw_ns, row - 1, col, opts)
          end
          for _, item in ipairs(items) do
            item.values = pick(item.entry, lah.fields)
          end
          local row_of = grid(lah.titles, lah.right, items)
          local matched = {}
          for _, item in ipairs(items) do
            matched[item.row] = true
            local line = lines[item.row]
            local name_end = item.start + item.length
            mark(item.row, item.start, {
              end_col = name_end,
              hl_group = item.entry.codes and ls_group(item.entry.codes) or "Normal",
              priority = 200,
            })
            local target = item.entry.target and { " -> " .. item.entry.target, "Normal" }
            if style == 2 then
              -- A space in place of the mark keeps the cells aligned.
              if lines[item.row]:sub(name_end + 1, name_end + 1):match("[/*@|=]") then
                mark(item.row, name_end, { end_col = name_end + 1, conceal = " " })
              end
            else
              -- The cursor line's bar runs under the columns too.
              mark(item.row, 0, {
                virt_text = { { row_of(item.values) .. " ", "Normal" } },
                virt_text_pos = "inline",
                hl_mode = "combine",
              })
              if #line > name_end then
                mark(item.row, name_end, { end_col = #line, conceal = "" })
              end
              if target then
                mark(item.row, #line, { virt_text = { target }, virt_text_pos = "inline" })
              end
              -- netrw draws tree levels with | where the font has no │.
              for col = 0, (item.bars or 0) - 2, 2 do
                if line:sub(col + 1, col + 1) == "|" then
                  mark(item.row, col, { end_col = col + 1, conceal = "│" })
                end
              end
            end
          end
          -- A row ls could not match gets blank columns, so its name still
          -- sits under Name. netrw's time sort mangles a broken symlink's
          -- name, and a tree stops asking ls after a few directories.
          if #items > 0 and style == 3 then
            local blank = (" "):rep(vim.fn.strdisplaywidth(row_of(lah.titles)) + 1)
            for row = rows + 1, #lines do
              if not matched[row] then
                mark(row, 0, { virt_text = { { blank, "Normal" } }, virt_text_pos = "inline", hl_mode = "combine" })
              end
            end
          end
          if #items > 0 and style == 3 then
            header = row_of(lah.titles) .. " Name"
          end

          if rows >= 6 then
            -- The box spans the window, or the listing when that is wider. A
            -- narrow window scrolls sideways to show a name, and the box then
            -- scrolls with the listing.
            local width = 80
            if win ~= -1 then
              width = vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
            end
            width = math.max(width, header and vim.fn.strdisplaywidth(header) or 0, 24)
            draw_banner(buf, rows, lines, width, header, view_names[style] or "")
            -- netrw keeps the old scroll position after gh or a new sort,
            -- which pushes the box up. Bring it back while the cursor still
            -- fits on the screen.
            if fresh and win ~= -1 then
              vim.api.nvim_win_call(win, function()
                if vim.fn.line("w0") > 1 and vim.fn.line(".") <= vim.api.nvim_win_get_height(win) then
                  vim.fn.winrestview({ topline = 1 })
                end
              end)
            end
          end
          vim.cmd("redrawstatus!")
        end
        -- The box hides netrw's banner, whose lines still act on <CR>. One of
        -- them prompts for the sort order. The cursor skips the box and lands
        -- on the first entry.
        vim.api.nvim_create_autocmd("CursorMoved", {
          callback = function(args)
            local first = vim.w.netrw_bannercnt
            if vim.bo[args.buf].filetype == "netrw" and first and first > 1 and vim.fn.line(".") < first then
              vim.api.nvim_win_set_cursor(0, { math.min(first, vim.api.nvim_buf_line_count(args.buf)), 0 })
              -- A box row is wider than the window, so the stop there
              -- scrolled the view sideways. Neovim scrolls back only as far
              -- as the entry needs.
              vim.fn.winrestview({ leftcol = 0 })
            end
          end,
        })
        -- The box fills the window, so it is drawn again after a resize.
        vim.api.nvim_create_autocmd("WinResized", {
          callback = function()
            for _, win in ipairs(vim.v.event.windows) do
              if vim.api.nvim_win_is_valid(win) then
                local buf = vim.api.nvim_win_get_buf(win)
                if vim.bo[buf].filetype == "netrw" then
                  netrw_decorate(buf)
                end
              end
            end
          end,
        })
        local netrw_keys = {
          { "Browse", {
            { "<CR>", "open the file or directory" },
            { "-", "go up one directory" },
            { "u  U", "go back or forward in history" },
            { "p", "preview the file" },
            { "v  o  t", "open in a vertical split, a split or a tab" },
            { "x", "open with the default program" },
          } },
          { "Edit", {
            { "%", "create a file" },
            { "d", "create a directory" },
            { "R", "rename" },
            { "D", "delete" },
          } },
          { "Copy and move", {
            { "mf", "mark a file" },
            { "mu", "unmark all files" },
            { "mt", "make this directory the target" },
            { "mc  mm", "copy or move the marked files there" },
          } },
          { "View", {
            { "gh", "show or hide dotfiles" },
            { "i", "switch between the tree and the grid" },
            { "s  r", "cycle or reverse the sort order" },
            { "<C-l>", "refresh" },
            { "I", "hide or show the banner" },
            { "<F1>", "netrw's full help" },
          } },
        }
        local function netrw_help()
          local lines, keys, headings = {}, {}, {}
          for _, section in ipairs(netrw_keys) do
            if #lines > 0 then
              table.insert(lines, "")
            end
            table.insert(lines, section[1])
            headings[#lines] = true
            for _, entry in ipairs(section[2]) do
              table.insert(lines, string.format("  %-8s %s", entry[1], entry[2]))
              keys[#lines] = #entry[1]
            end
          end
          local buf = vim.lsp.util.open_floating_preview(lines, "", { title = " netrw ", focus_id = "netrw_help" })
          local ns = vim.api.nvim_create_namespace("netrw_help")
          for row = 1, #lines do
            if headings[row] then
              vim.hl.range(buf, ns, "Title", { row - 1, 0 }, { row - 1, #lines[row] })
            elseif keys[row] then
              vim.hl.range(buf, ns, "Function", { row - 1, 2 }, { row - 1, 2 + keys[row] })
            end
          end
        end
        -- i switches between the tree and the wide grid. netrw's own i steps
        -- through all four of its styles and lists the directory again at
        -- each step. From the tree, the step starts one style short of the
        -- grid, so a single listing reaches it.
        local function netrw_map_view()
          local own = vim.fn.maparg("i", "n", false, true)
          if not own.sid or not (own.rhs or ""):find("NetrwListStyle", 1, true) then
            return
          end
          local step = "<SNR>" .. own.sid .. "_NetrwListStyle"
          vim.keymap.set("n", "i", function()
            if vim.w.netrw_liststyle ~= 3 then
              vim.fn[step](1)
              return
            end
            -- netrw finds the name under the cursor with the rules of the
            -- style it thinks it is in, so it loses the entry here. Find it
            -- again in the grid, where each name starts a line or follows
            -- padding.
            local name = vim.fn.getline("."):gsub("^[|│ ]*", ""):match("^[^\t]*")
            vim.w.netrw_liststyle = 1
            vim.fn[step](1)
            if name ~= "" then
              vim.api.nvim_win_set_cursor(0, { math.max(vim.w.netrw_bannercnt or 1, 1), 0 })
              vim.fn.search([[\V\%(\^\|  \)\zs]] .. vim.fn.escape(name, [[\]]) .. [[\%( \|\$\)]], "cW")
            end
          end, { buffer = true, nowait = true })
        end
        -- netrw sets the filetype again on every listing, so the map stays.
        -- Its listing has no line numbers, so its cursor line lights the
        -- whole line instead.
        vim.api.nvim_create_autocmd("FileType", {
          pattern = "netrw",
          callback = function(args)
            vim.opt_local.cursorlineopt = "line"
            -- Hide netrw's banner text and the marks after each name, on the
            -- cursor line too.
            vim.opt_local.conceallevel = 2
            vim.opt_local.concealcursor = "nc"
            vim.keymap.set("n", "?", netrw_help, { buffer = args.buf, nowait = true })
            vim.schedule(function()
              netrw_decorate(args.buf, true)
              if vim.api.nvim_buf_is_valid(args.buf) then
                vim.api.nvim_buf_call(args.buf, netrw_map_view)
              end
            end)
          end,
        })
      '';
    };

    xdg.configFile."nvim/colors/0xNix.lua".text = colorscheme;
  };
}

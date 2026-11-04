{
  pkgs-unstable,
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
  # mapping as vim/0xNix.vim. The editor background stays transparent, so
  # the terminal's shows through. Tree-sitter captures link to the classic
  # groups below, so only the captures that need a different colour are set
  # explicitly.
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
    }

    for group, spec in pairs(groups) do
      vim.api.nvim_set_hl(0, group, spec)
    end

    -- The colours of :terminal, the same 16 as foot's.
    ${terminalColours}
  '';
in
{
  programs.neovim = {
    enable = true;
    # Sourced from nixpkgs-unstable, like vim in default.nix.
    package = pkgs-unstable.neovim-unwrapped;
    plugins = with pkgs-unstable.vimPlugins; [
      # Parsers come from nixpkgs, so nothing compiles at runtime.
      nvim-treesitter.withAllGrammars
      # Reads the indentation of the file itself when no .editorconfig
      # applies.
      guess-indent-nvim
      # Server definitions (command, filetypes, root markers) for
      # vim.lsp.enable. Neovim's own client does the rest.
      nvim-lspconfig
    ];
    # Servers with no per-language devshell (devshells/default.nix) live on
    # Neovim's PATH only, so they never reach the shell's. Every other server
    # comes from the devshell of the project, through direnv.
    extraPackages = with pkgs-unstable; [
      marksman
      jdt-language-server
      nil
      taplo
    ];
    initLua = ''
      vim.o.termguicolors = true
      vim.cmd.colorscheme("0xNix")

      -- Indentation is never set here. Neovim reads .editorconfig first,
      -- guess-indent reads the file next, and Neovim's own defaults apply
      -- when neither finds anything.
      require("guess-indent").setup({ auto_cmd = false })
      -- Its own autocmd runs before the filetype plugin and EditorConfig,
      -- which would then overwrite the result. Run it after both.
      -- A modeline is the file's own declaration, so it wins. Neovim marks
      -- options set by a modeline with script id -1.
      local function set_by_modeline(buf)
        for _, opt in ipairs({ "shiftwidth", "tabstop", "expandtab", "softtabstop" }) do
          if vim.api.nvim_get_option_info2(opt, { buf = buf }).last_set_sid == -1 then
            return true
          end
        end
        return false
      end
      vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function(args)
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(args.buf) and not set_by_modeline(args.buf) then
              require("guess-indent").set_from_buffer(args.buf, true, true)
            end
          end)
        end,
      })

      -- Start tree-sitter highlighting wherever a parser exists.
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
      })

      vim.o.completeopt = "menu,menuone,noselect,popup"
      -- Every popup in the rice has a square border.
      vim.o.winborder = "single"
      vim.diagnostic.config({
        virtual_text = false,
        severity_sort = true,
      })

      -- Index Markdown only inside a project that opts in with a
      -- .marksman.toml. The shared Git marker would otherwise turn any
      -- repository, or a stray marker in $HOME, into one workspace. Outside
      -- a marked project, marksman gets a private empty directory as its
      -- root and working directory, so it only reads the documents that are
      -- open. It lives in Neovim's own session temp directory, which Neovim
      -- removes on exit.
      local marksman_scratch
      local function marksman_root(bufnr, on_dir)
        local home = vim.uv.fs_realpath(vim.env.HOME)
        local path = vim.uv.fs_realpath(vim.api.nvim_buf_get_name(bufnr))
        local dir = path and vim.fs.dirname(path)
        while dir and dir ~= home and dir ~= vim.fs.dirname(dir) do
          if vim.uv.fs_stat(dir .. "/.marksman.toml") then
            return on_dir(dir)
          end
          dir = vim.fs.dirname(dir)
        end
        if not marksman_scratch then
          marksman_scratch = vim.fn.tempname()
          vim.fn.mkdir(marksman_scratch, "p", "0700")
        end
        on_dir(marksman_scratch)
      end
      vim.lsp.config("marksman", {
        root_dir = marksman_root,
        cmd = function(dispatchers, config)
          return vim.lsp.rpc.start({ "marksman", "server" }, dispatchers, { cwd = config.root_dir })
        end,
      })

      -- jdtls is the heavy server, so it starts only for Java files. It
      -- keeps one index per project, named after the full path so that two
      -- projects with the same folder name never share one. The launcher
      -- hardcodes a 1G initial heap. The later flags replace it, cap the
      -- heap and use the serial collector, which has the smallest footprint.
      -- JDTLS_JVM_ARGS adds more, such as a larger -Xmx for a big project or
      -- a Lombok agent. They come last, so they win. A property keeps
      -- jdtls from writing .classpath, .project and .settings into the
      -- project root.
      vim.lsp.config("jdtls", {
        cmd = function(dispatchers, config)
          local root = config.root_dir or "single-file"
          local data = vim.fn.stdpath("cache")
            .. "/jdtls/"
            .. vim.fs.basename(root)
            .. "-"
            .. vim.fn.sha256(root):sub(1, 12)
          local cmd = {
            "jdtls",
            "-data",
            data,
            "--jvm-arg=-Xms64m",
            "--jvm-arg=-Xmx1g",
            "--jvm-arg=-XX:+UseSerialGC",
            "--jvm-arg=-Djava.import.generatesMetadataFilesAtProjectRoot=false",
          }
          for arg in (vim.env.JDTLS_JVM_ARGS or ""):gmatch("%S+") do
            table.insert(cmd, "--jvm-arg=" .. arg)
          end
          return vim.lsp.rpc.start(cmd, dispatchers, { cwd = config.cmd_cwd, env = config.cmd_env })
        end,
      })

      -- One light server per language. A server is enabled only when its
      -- executable is on PATH, which a devshell provides, so a missing one
      -- costs nothing and raises no error.
      local servers = {
        clangd = "clangd",
        ruff = "ruff",
        ty = "ty",
        jdtls = "jdtls",
        rust_analyzer = "rust-analyzer",
        gopls = "gopls",
        ts_ls = "typescript-language-server",
        bashls = "bash-language-server",
        nil_ls = "nil",
        marksman = "marksman",
        taplo = "taplo",
        asm_lsp = "asm-lsp",
      }
      for name, executable in pairs(servers) do
        if vim.fn.executable(executable) == 1 then
          vim.lsp.enable(name)
        end
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          local function map(lhs, rhs)
            vim.keymap.set("n", lhs, rhs, { buffer = args.buf })
          end
          map("gd", vim.lsp.buf.definition)
          map("gr", vim.lsp.buf.references)
          map("<leader>rn", vim.lsp.buf.rename)
          map("<leader>ca", vim.lsp.buf.code_action)
          map("[g", function()
            vim.diagnostic.jump({ count = -1 })
          end)
          map("]g", function()
            vim.diagnostic.jump({ count = 1 })
          end)
          local win = vim.fn.bufwinid(args.buf)
          if win ~= -1 then
            vim.wo[win].signcolumn = "yes"
          end
          if client and client:supports_method("textDocument/completion") then
            vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
          end
        end,
      })
    '';
  };

  xdg.configFile."nvim/colors/0xNix.lua".text = colorscheme;
}

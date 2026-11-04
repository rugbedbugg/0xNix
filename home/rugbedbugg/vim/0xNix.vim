" 0xNix: this rice's vim colour scheme.
"
" Each highlight group gets a colour role from palette.nix. This file is a
" template: default.nix replaces every @role@ with the palette's value when
" it installs the scheme.
"
" Role -> use:
"   surface            bar/fuzzel background (only used for blends and for
"                      text on filled highlights. The editor background
"                      stays transparent)
"   surfaceContainer*  raised fills
"   text               text
"   textDim            dim text
"   outline            line numbers, disabled text
"   outlineVariant     inactive borders, as in Hyprland
"   border             emphasis. With surface on it: reverse video, like
"                      fuzzel's selection
"   disk               search
"   alert              the rice's alert red: errors, deletions only
"   cpu memory swap disk gpu
"                      waybar's stat hues (cyan purple dim-purple yellow
"                      green)

set background=dark
highlight clear
if exists('syntax_on')
  syntax reset
endif
let g:colors_name = '0xNix'

" Editor UI
highlight Normal       guifg=@text@ guibg=NONE    gui=NONE           ctermbg=NONE cterm=NONE
highlight CursorLine   guibg=@surfaceContainerHigh@ gui=NONE      cterm=NONE
highlight CursorLineNr guifg=@border@ gui=bold cterm=bold
highlight LineNr       guifg=@outline@
highlight SignColumn   guibg=NONE    ctermbg=NONE
highlight VertSplit    guifg=@outlineVariant@ guibg=NONE    gui=NONE           cterm=NONE
highlight MatchParen   guifg=@border@ guibg=NONE    gui=bold,underline cterm=bold,underline
highlight NonText      guifg=@outline@ guibg=NONE    ctermbg=NONE
highlight SpecialKey   guifg=@outlineVariant@
highlight ColorColumn  guibg=@surfaceContainer@
highlight Folded       guifg=@textDim@ guibg=@surfaceContainer@
highlight Conceal      guifg=@textDim@ guibg=NONE

" Selection / search
highlight Visual       guifg=@surface@ guibg=@text@ gui=NONE cterm=NONE
highlight VisualNOS    guifg=@surface@ guibg=@text@ gui=NONE cterm=NONE
highlight Search       guifg=@surface@ guibg=@disk@ gui=NONE cterm=NONE
highlight IncSearch    guifg=@surface@ guibg=@border@ gui=NONE cterm=NONE
highlight CurSearch    guifg=@surface@ guibg=@border@ gui=NONE cterm=NONE

" Completion menu
highlight Pmenu        guifg=@text@ guibg=@surfaceContainerHigh@
highlight PmenuSel     guifg=@surface@ guibg=@text@ gui=bold cterm=bold
highlight PmenuSbar    guibg=@surfaceContainerHighest@
highlight PmenuThumb   guibg=@outline@

" Statusline / tabline
highlight StatusLine   guifg=@text@ guibg=NONE    gui=NONE           cterm=NONE
highlight StatusLineNC guifg=@textDim@ guibg=NONE    gui=NONE           cterm=NONE
highlight TabLineSel   guifg=@border@ guibg=NONE    gui=bold cterm=bold

" Spell
highlight SpellBad     guisp=@alert@ gui=undercurl cterm=undercurl
highlight SpellCap     guisp=@disk@ gui=undercurl cterm=undercurl
highlight SpellRare    guisp=@memory@ gui=undercurl cterm=undercurl
highlight SpellLocal   guisp=@swap@ gui=undercurl cterm=undercurl

" Diff: each hue blended over @surface@ (25%, 20%, 25%, 45%, as upstream)
highlight DiffAdd      guifg=NONE guibg=@diffAdd@
highlight DiffChange   guifg=NONE guibg=@diffChange@
highlight DiffDelete   guifg=NONE guibg=@diffDelete@
highlight DiffText     guifg=NONE guibg=@diffText@ gui=NONE cterm=NONE

" Syntax
highlight Comment      guifg=@textDim@ gui=italic cterm=italic
highlight String       guifg=@gpu@
highlight Number       guifg=@disk@
highlight Boolean      guifg=@disk@
highlight Constant     guifg=@disk@
highlight Function     guifg=@cpu@
highlight Statement    guifg=@memory@ gui=NONE cterm=NONE
highlight Operator     guifg=@swap@
highlight Type         guifg=@disk@ gui=NONE cterm=NONE
highlight PreProc      guifg=@alert@
highlight Special      guifg=@swap@
highlight Delimiter    guifg=@textDim@
highlight Error        guifg=@alert@ guibg=NONE
highlight Todo         guifg=@surface@ guibg=@disk@ gui=bold cterm=bold
highlight Title        guifg=@border@ gui=bold cterm=bold
highlight Identifier   guifg=@text@ gui=NONE cterm=NONE
highlight Directory    guifg=@cpu@

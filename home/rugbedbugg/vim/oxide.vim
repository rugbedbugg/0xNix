" oxide: this rice's vim colour scheme.
"
" Each highlight group gets a colour role, filled from this rice's fixed
" palette.
"
" Role -> colour:
"   surface            #20242c   bar/fuzzel background (only used for blends;
"                                the editor background stays transparent)
"   surfaceContainer*  #262b34 #2c313b #343a45
"   onSurface          #eceff4   text
"   onSurfaceVariant   #8a8f99   dim text
"   outline            #6c7380
"   outlineVariant     #444444   inactive borders, as in Hyprland
"   primary            #ffffff   with #20242c on it: reverse video, like
"                                fuzzel's selection
"   tertiary           #e5c07b   search
"   error / term1      #ff0000   the rice's alert red: errors, deletions only
"   term2..term6       #7ee787 #e5c07b #5fd7ff #c792ea #9d8fbf
"                      waybar's stat hues (green yellow cyan purple dim-purple)

set background=dark
highlight clear
if exists('syntax_on')
  syntax reset
endif
let g:colors_name = 'oxide'

" Editor UI
highlight Normal       guifg=#eceff4 guibg=NONE    gui=NONE           ctermbg=NONE cterm=NONE
highlight CursorLine   guibg=#2c313b gui=NONE      cterm=NONE
highlight CursorLineNr guifg=#ffffff gui=bold cterm=bold
highlight LineNr       guifg=#6c7380
highlight SignColumn   guibg=NONE    ctermbg=NONE
highlight VertSplit    guifg=#444444 guibg=NONE    gui=NONE           cterm=NONE
highlight MatchParen   guifg=#ffffff guibg=NONE    gui=bold,underline cterm=bold,underline
highlight NonText      guifg=#6c7380 guibg=NONE    ctermbg=NONE
highlight SpecialKey   guifg=#444444
highlight ColorColumn  guibg=#262b34
highlight Folded       guifg=#8a8f99 guibg=#262b34
highlight Conceal      guifg=#8a8f99 guibg=NONE

" Selection / search
highlight Visual       guifg=#20242c guibg=#eceff4 gui=NONE cterm=NONE
highlight VisualNOS    guifg=#20242c guibg=#eceff4 gui=NONE cterm=NONE
highlight Search       guifg=#20242c guibg=#e5c07b gui=NONE cterm=NONE
highlight IncSearch    guifg=#20242c guibg=#ffffff gui=NONE cterm=NONE
highlight CurSearch    guifg=#20242c guibg=#ffffff gui=NONE cterm=NONE

" Completion menu
highlight Pmenu        guifg=#eceff4 guibg=#2c313b
highlight PmenuSel     guifg=#20242c guibg=#eceff4 gui=bold cterm=bold
highlight PmenuSbar    guibg=#343a45
highlight PmenuThumb   guibg=#6c7380

" Statusline / tabline
highlight StatusLine   guifg=#eceff4 guibg=NONE    gui=NONE           cterm=NONE
highlight StatusLineNC guifg=#8a8f99 guibg=NONE    gui=NONE           cterm=NONE
highlight TabLineSel   guifg=#ffffff guibg=NONE    gui=bold cterm=bold

" Spell
highlight SpellBad     guisp=#ff0000 gui=undercurl cterm=undercurl
highlight SpellCap     guisp=#e5c07b gui=undercurl cterm=undercurl
highlight SpellRare    guisp=#c792ea gui=undercurl cterm=undercurl
highlight SpellLocal   guisp=#9d8fbf gui=undercurl cterm=undercurl

" Diff: each hue blended over #20242c (25%, 20%, 25%, 45%, as upstream)
highlight DiffAdd      guifg=NONE guibg=#375442
highlight DiffChange   guifg=NONE guibg=#47433b
highlight DiffDelete   guifg=NONE guibg=#571b21
highlight DiffText     guifg=NONE guibg=#786a4f gui=NONE cterm=NONE

" Syntax
highlight Comment      guifg=#8a8f99 gui=italic cterm=italic
highlight String       guifg=#7ee787
highlight Number       guifg=#e5c07b
highlight Boolean      guifg=#e5c07b
highlight Constant     guifg=#e5c07b
highlight Function     guifg=#5fd7ff
highlight Statement    guifg=#c792ea gui=NONE cterm=NONE
highlight Operator     guifg=#9d8fbf
highlight Type         guifg=#e5c07b gui=NONE cterm=NONE
highlight PreProc      guifg=#ff0000
highlight Special      guifg=#9d8fbf
highlight Delimiter    guifg=#8a8f99
highlight Error        guifg=#ff0000 guibg=NONE
highlight Todo         guifg=#20242c guibg=#e5c07b gui=bold cterm=bold
highlight Title        guifg=#ffffff gui=bold cterm=bold
highlight Identifier   guifg=#eceff4 gui=NONE cterm=NONE
highlight Directory    guifg=#5fd7ff

{
  config,
  lib,
  palette,
  ...
}:
{
  config = lib.mkIf config.programs.vim.enable {
    programs.vim.extraConfig = ''
      let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
      let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
      set termguicolors
      syntax on
      colorscheme 0xNix
    '';
    home.file.".vim/colors/0xNix.vim".text =
      let
        colours = removeAttrs palette [
          "bare"
          "rgb"
          "ansi"
        ];
      in
      builtins.replaceStrings (map (name: "@${name}@") (
        builtins.attrNames colours
      )) (builtins.attrValues colours) (builtins.readFile ./vim/0xNix.vim);
  };
}

{ ... }:
{
  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        size = 14;
        normal = {
          family = "Hack";
          style = "Regular";
        };
        bold = {
          family = "Hack";
          style = "Bold";
        };
        italic = {
          family = "Hack";
          style = "Italic";
        };
        bold_italic = {
          family = "Hack";
          style = "Bold Italic";
        };
      };

      colors = {
        bright = {
          black = "#1d1f22";
          blue = "#4b6b88";
          cyan = "#4d7b74";
          green = "#798431";
          magenta = "#6e5079";
          red = "#8d2e32";
          white = "#5a626a";
          yellow = "#e58a50";
        };
        cursor = {
          cursor = "#b7bcba";
          text = "#1e1f22";
        };
        normal = {
          black = "#2a2e33";
          blue = "#6e90b0";
          cyan = "#7fbfb4";
          green = "#b3bf5a";
          magenta = "#a17eac";
          red = "#b84d51";
          white = "#b5b9b6";
          yellow = "#e4b55e";
        };
        primary = {
          background = "#161719";
          foreground = "#b7bcba";
        };
        selection = {
          background = "#1e1f22";
          text = "#b7bcba";
        };
      };
    };
  };
}

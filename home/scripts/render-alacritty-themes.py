#!/usr/bin/env python3
import os
import re
import sys

def parse_base16(path):
    palette = {}
    with open(path) as f:
        for line in f:
            m = re.search(r'(base0[0-9a-fA-F]):\s*["\']?#?([0-9a-fA-F]{6})["\']?', line)
            if m:
                palette[m.group(1).lower()] = "#" + m.group(2)
    return palette

def to_alacritty(p):
    return f"""[colors.primary]
background = "{p['base00']}"
foreground = "{p['base05']}"
bright_foreground = "{p['base07']}"

[colors.cursor]
cursor = "{p['base05']}"
text = "{p['base00']}"

[colors.selection]
background = "{p['base02']}"
text = "{p['base05']}"

[colors.normal]
black = "{p['base00']}"
red = "{p['base08']}"
green = "{p['base0b']}"
yellow = "{p['base0a']}"
blue = "{p['base0d']}"
magenta = "{p['base0e']}"
cyan = "{p['base0c']}"
white = "{p['base05']}"

[colors.bright]
black = "{p['base03']}"
red = "{p['base08']}"
green = "{p['base0b']}"
yellow = "{p['base0a']}"
blue = "{p['base0d']}"
magenta = "{p['base0e']}"
cyan = "{p['base0c']}"
white = "{p['base07']}"
"""

def main():
    if len(sys.argv) < 3:
        print("usage: render-alacritty-themes.py <themes_dir> <out_dir>", file=sys.stderr)
        sys.exit(1)

    themes_dir = sys.argv[1]
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    for filename in os.listdir(themes_dir):
        if filename.endswith(".yaml"):
            base = filename[:-5]
            filepath = os.path.join(themes_dir, filename)
            p = parse_base16(filepath)
            if len(p) == 16:
                with open(os.path.join(out_dir, f"{base}.toml"), "w") as out:
                    out.write(to_alacritty(p))

if __name__ == "__main__":
    main()

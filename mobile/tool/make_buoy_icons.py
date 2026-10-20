"""Rasterize the local CC0 Temaki buoy for Mapbox (dev only: pip install cairosvg).

No remote assets are read. Run from any directory with Python 3.
"""

from pathlib import Path
import xml.etree.ElementTree as ET

import cairosvg


ASSETS = Path(__file__).resolve().parents[1] / "assets/icons/buoys"
COLORS = {
    "red": "#D52E35",
    "green": "#00834B",
    "yellow": "#F5CB28",
    "black": "#20262C",
    "white": "#FFFFFF",
}
VARIANTS = {
    "red": (["red"], "horizontal"),
    "green": (["green"], "horizontal"),
    "yellow": (["yellow"], "horizontal"),
    "north": (["black", "yellow"], "horizontal"),
    "east": (["black", "yellow", "black"], "horizontal"),
    "south": (["yellow", "black"], "horizontal"),
    "west": (["yellow", "black", "yellow"], "horizontal"),
    "isolated-danger": (["black", "red", "black"], "horizontal"),
    "safe-water": (["red", "white", "red", "white"], "vertical"),
    "preferred-port": (["green", "red", "green"], "horizontal"),
    "preferred-starboard": (["red", "green", "red"], "horizontal"),
}


def make_neutral():
    # A 3-logical-pixel dot inside a 4-pixel canvas, registered at density 3.
    # No nautical silhouette, outline or halo for ambiguous features.
    svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4 4"><circle cx="2" cy="2" r="1.5" fill="#20262C"/></svg>'
    cairosvg.svg2png(bytestring=svg.encode(), write_to=str(ASSETS / "neutral.png"),
                    output_width=12, output_height=12)


def main():
    make_neutral()
    root = ET.parse(ASSETS / "buoy.svg").getroot()
    path = root.find("{http://www.w3.org/2000/svg}path").attrib["d"]
    # The original 15-unit silhouette, with a 1.5-unit margin and a white
    # halo, fits in 24 logical pixels. Three physical pixels per logical pixel.
    for name, (bands, direction) in VARIANTS.items():
        rects = []
        for i, color in enumerate(bands):
            if direction == "vertical":
                step = 15 / len(bands)
                rect = f'x="{i * step}" y="0" width="{step}" height="15"'
            else:
                # Bands cover the body, rather than wasting a band on waves.
                step = 11 / len(bands)
                rect = f'x="0" y="{1 + i * step}" width="15" height="{step}"'
            rects.append(f'<rect {rect} fill="{COLORS[color]}"/>')
        svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1.5 -1.5 18 18">
          <defs><path id="buoy" d="{path}"/>
            <clipPath id="silhouette"><use href="#buoy"/></clipPath></defs>
          <use href="#buoy" fill="#566773" stroke="white" stroke-width="1.4"
            stroke-linejoin="round"/>
          <g clip-path="url(#silhouette)">{''.join(rects)}</g>
          <use href="#buoy" fill="none" stroke="#344653" stroke-width="0.25"/>
        </svg>'''
        cairosvg.svg2png(bytestring=svg.encode(), write_to=str(ASSETS / f"{name}.png"),
                        output_width=72, output_height=72)


if __name__ == "__main__":
    main()

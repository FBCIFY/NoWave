"""Original NoWave fixed-aid SVG geometry -> PNG. Dev dependency: cairosvg."""
from pathlib import Path
import cairosvg

ASSETS = Path(__file__).resolve().parents[1] / 'assets/icons/fixed-aids'
COLORS = {'red': '#D52E35', 'green': '#00834B', 'yellow': '#F5CB28',
          'white': '#F2F0DA', 'grey': '#808991', 'default': '#91A5B0', 'black': '#20262C'}
BANDS = {'red': ['red'], 'green': ['green'], 'yellow': ['yellow'],
         'north': ['black', 'yellow'], 'east': ['black', 'yellow', 'black'],
         'south': ['yellow', 'black'], 'west': ['yellow', 'black', 'yellow'],
         'isolated-danger': ['black', 'red', 'black'], 'safe-water': ['red', 'white'],
         'preferred-port': ['green', 'red', 'green'],
         'preferred-starboard': ['red', 'green', 'red'],
         'green-white': ['green', 'white'], 'white-green': ['white', 'green'],
         'red-white': ['red', 'white'], 'white-red': ['white', 'red'],
         'green-grey': ['green', 'grey'], 'grey-green': ['grey', 'green'],
         'red-grey': ['red', 'grey'], 'grey-red': ['grey', 'red']}

def save(name, body, size=24):
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}">{body}</svg>'
    cairosvg.svg2png(bytestring=svg.encode(), write_to=str(ASSETS / f'{name}.png'),
                    output_width=size*3, output_height=size*3)

def cone(y, up):
    points = f'12,{y} 9.8,{y+3.5} 14.2,{y+3.5}' if up else f'9.8,{y} 14.2,{y} 12,{y+3.5}'
    return f'<polygon points="{points}" fill="#20262C" stroke="#F6F8FA" stroke-width="0.35"/>'

def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    for name, colors in BANDS.items():
        # Upright, narrow support on a foot: no floating hull or waves.
        body = '<path d="M10 10H14V20H10Z M8 21H16" fill="#F6F8FA" stroke="#F6F8FA" stroke-width="2.2"/>'
        for i, color in enumerate(colors):
            if name == 'safe-water':
                body += f'<rect x="{10+4*i/len(colors)}" y="10" width="{4/len(colors)}" height="10" fill="{COLORS[color]}"/>'
            else:
                body += f'<rect x="10" y="{10+10*i/len(colors)}" width="4" height="{10/len(colors)}" fill="{COLORS[color]}"/>'
        body += '<path d="M10 10H14V20H10Z M8 21H16" fill="none" stroke="#344653" stroke-width="0.65"/>'
        if name in ['north','south','east','west']:
            body += cone(1, name in ['north','east']) + cone(5.5, name in ['north','west'])
        elif name == 'isolated-danger':
            body += '<g fill="#20262C"><circle cx="12" cy="3" r="1.6"/><circle cx="12" cy="7" r="1.6"/></g>'
        elif name == 'safe-water':
            body += '<circle cx="12" cy="6" r="2" fill="#D52E35" stroke="#344653" stroke-width="0.5"/>'
        elif name == 'yellow':
            body += '<path d="M10 4L14 8M14 4L10 8" stroke="#344653" stroke-width="2"/><path d="M10 4L14 8M14 4L10 8" stroke="#F5CB28" stroke-width="1"/>'
        save('beacon-'+name, body)
    for name in ['default', 'red', 'green', 'yellow', 'white']:
        color = COLORS[name]
        save('lighthouse-'+name, f'<path d="M8 21L9.5 10H14.5L16 21Z" fill="#F1F4F5" stroke="#F6F8FA" stroke-width="2"/><path d="M8 21L9.5 10H14.5L16 21Z" fill="#F1F4F5" stroke="#344653" stroke-width="0.8"/><path d="M9 16H15" stroke="#567489" stroke-width="2"/><path d="M8.5 5L12 2L15.5 5Z" fill="#344653"/><rect x="9" y="5" width="6" height="5" rx="0.6" fill="{color}" stroke="#344653" stroke-width="0.8"/><path d="M7 21H17" stroke="#344653" stroke-width="1"/>')
        save('light-'+name, f'<path d="M6 1V2.2M6 9.8V11M1 6H2.2M9.8 6H11" stroke="#748B99" stroke-width="0.7"/><circle cx="6" cy="6" r="2.5" fill="#F6F8FA"/><circle cx="6" cy="6" r="2" fill="{color}" stroke="#344653" stroke-width="0.7"/>', 12)

if __name__ == '__main__':
    main()

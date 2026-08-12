"""
Generate app icons from assets/icon.svg.
Android: SVG rendering. Windows/macOS/Web: classic blue-circle style.
Requires: pip install Pillow
"""
import math, os
from PIL import Image, ImageDraw

def render_svg_icon(size):
    """Render the SVG icon at given size using PIL."""
    ratio = size / 192.0
    # Fill entire canvas white, then transparent corners via clip
    img = Image.new('RGBA', (size, size), (255, 255, 255, 255))
    draw = ImageDraw.Draw(img)
    blue = (33, 150, 243)
    cx = size // 2
    s = lambda v: int(v * ratio)

    # White background circle
    clip_r = s(90)
    draw.ellipse([cx-clip_r, cx-clip_r, cx+clip_r, cx+clip_r], fill=(255, 255, 255, 255))

    # Ring
    ring_r, ring_w = s(80.64), s(20.26)
    draw.ellipse([cx-ring_r-ring_w//2, cx-ring_r-ring_w//2,
                  cx+ring_r+ring_w//2, cx+ring_r+ring_w//2],
                 outline=blue, width=ring_w)

    # Outer dots
    dot_r = s(53.76)
    for x, y in [(s(96), s(15.36)), (s(165.84), s(136.32)), (s(26.16), s(136.32))]:
        draw.ellipse([x-dot_r, y-dot_r, x+dot_r, y+dot_r], fill=blue)

    # Center dot
    cr = s(26.88)
    draw.ellipse([cx-cr, cx-cr, cx+cr, cx+cr], fill=blue)

    # Clip circle r=90
    clip_r = s(90)
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).ellipse([cx-clip_r, cx-clip_r, cx+clip_r, cx+clip_r], fill=255)
    img.putalpha(mask)
    return img

def main():
    # Android
    android_sizes = {
        'mipmap-mdpi': 48, 'mipmap-hdpi': 72, 'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144, 'mipmap-xxxhdpi': 192,
    }
    for folder, size in android_sizes.items():
        render_svg_icon(size).save(f'android/app/src/main/res/{folder}/ic_launcher.png', 'PNG')
        print(f'Generated: {folder}/ic_launcher.png ({size}x{size})')

    # Android adaptive icon foreground (SVG scaled to 72dp safe zone within 108dp)
    import os
    os.makedirs('android/app/src/main/res/drawable-xxxhdpi', exist_ok=True)
    fg_size = 432
    safe = int(fg_size * 0.667)  # 72dp / 108dp
    fg_full = render_svg_icon(fg_size)
    fg_scaled = fg_full.resize((safe, safe), Image.LANCZOS)
    fg_canvas = Image.new('RGBA', (fg_size, fg_size), (0, 0, 0, 0))
    fg_canvas.paste(fg_scaled, ((fg_size - safe) // 2, (fg_size - safe) // 2))
    fg_canvas.save('android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png', 'PNG')
    print('Generated: adaptive foreground')

    os.makedirs('android/app/src/main/res/mipmap-anydpi-v26', exist_ok=True)
    for name in ['ic_launcher', 'ic_launcher_round']:
        with open(f'android/app/src/main/res/mipmap-anydpi-v26/{name}.xml', 'w') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                    '    <background android:drawable="@color/ic_launcher_background"/>\n'
                    '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
                    '</adaptive-icon>\n')
    print('Generated: adaptive icon XMLs')

    with open('android/app/src/main/res/values/ic_launcher_background.xml', 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<resources>\n'
                '    <color name="ic_launcher_background">#FFFFFF</color>\n'
                '</resources>\n')
    print('Generated: icon background color')

    # Windows .ico — SVG design
    ico_sizes = [16, 32, 48, 64, 128, 256]
    ico_images = [render_svg_icon(s) for s in ico_sizes]
    ico_images[-1].save('windows/runner/resources/app_icon.ico', format='ICO', sizes=[(s, s) for s in ico_sizes])
    print('Generated: windows .ico')
    # macOS icons (skip if dir missing)
    mp = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    if os.path.exists(mp):
        for fn,sz in{'app_icon_16.png':16,'app_icon_32.png':32,'app_icon_64.png':64,'app_icon_128.png':128,'app_icon_256.png':256,'app_icon_512.png':512,'app_icon_1024.png':1024}.items():
            render_svg_icon(sz).save(f'{mp}/{fn}','PNG')
    # Web icons
    os.makedirs('web/icons', exist_ok=True)
    render_svg_icon(32).save('web/favicon.png','PNG')
    render_svg_icon(192).save('web/icons/Icon-192.png','PNG')
    render_svg_icon(512).save('web/icons/Icon-512.png','PNG')
    render_svg_icon(512).save('icon_preview.png','PNG')

    # Logo for settings page — white background + blue elements
    os.makedirs('assets', exist_ok=True)
    logo = render_svg_icon(256)
    logo.save('assets/logo.png','PNG')
    # Tintable variant: remove white, keep blue elements on transparent
    logo_tint = logo.copy()
    px = logo_tint.load()
    for y in range(logo_tint.height):
        for x in range(logo_tint.width):
            r, g, b, a = px[x, y]
            if r > 240 and g > 240 and b > 240:
                px[x, y] = (r, g, b, 0)
    logo_tint.save('assets/logo_tint.png','PNG')

    print('Done!')

if __name__ == '__main__':
    main()

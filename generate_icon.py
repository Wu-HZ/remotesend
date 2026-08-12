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

    # Windows/macOS/Web — classic blue-circle + white dots
    bg=(33,150,243); w=(255,255,255); wt=(255,255,255,220)
    def old_icon(s):
        img=Image.new('RGBA',(s,s),(0,0,0,0)); d=ImageDraw.Draw(img)
        m=int(s*0.02); d.ellipse([m,m,s-m,s-m],fill=bg)
        c=s//2; o=int(s*0.18); cr=int(s*0.13); orb=int(s*0.28)
        for a in[270,30,150]:
            r=math.radians(a); x=c+int(orb*math.cos(r)); y=c+int(orb*math.sin(r))
            d.ellipse([x-o,y-o,x+o,y+o],fill=wt)
        d.ellipse([c-cr,c-cr,c+cr,c+cr],fill=w)
        return img
    ims=[old_icon(s) for s in[16,32,48,64,128,256]]
    ims[-1].save('windows/runner/resources/app_icon.ico',format='ICO',sizes=[(s,s)for s in[16,32,48,64,128,256]])
    print('Generated: windows .ico')
    for fn,sz in{'app_icon_16.png':16,'app_icon_32.png':32,'app_icon_64.png':64,'app_icon_128.png':128,'app_icon_256.png':256,'app_icon_512.png':512,'app_icon_1024.png':1024}.items():
        old_icon(sz).save(f'macos/Runner/Assets.xcassets/AppIcon.appiconset/{fn}','PNG')
    old_icon(32).save('web/favicon.png','PNG')
    old_icon(192).save('web/icons/Icon-192.png','PNG')
    old_icon(512).save('web/icons/Icon-512.png','PNG')
    render_svg_icon(512).save('icon_preview.png','PNG')
    print('Done!')

if __name__ == '__main__':
    main()

"""
Generate app icon: blue ring + blue dots on transparent background.
Requires: pip install Pillow
"""
import math, os
from PIL import Image, ImageDraw

def create_icon(size, dot_color=(33,150,243), trans_color=(33,150,243,200),
                draw_ring=True, custom_radii=None):
    """Create the RemoteSend icon — ring + dots on transparent background."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    center = size // 2

    if custom_radii:
        center_radius, outer_radius, orbit_radius = custom_radii
    else:
        outer_radius = int(size * 0.18)
        center_radius = int(size * 0.13)
        orbit_radius = int(size * 0.28)

    # Draw ring passing through outer dot centers, thick, outward
    if draw_ring:
        ring_w = max(2, int(outer_radius * 0.6))
        # Ring centered on orbit_radius, extending outward
        r_inner = orbit_radius - ring_w // 2
        r_outer = orbit_radius + ring_w // 2
        draw.ellipse([
            center - r_outer, center - r_outer,
            center + r_outer, center + r_outer
        ], outline=trans_color, width=ring_w)

    # Draw 3 outer dots (120 deg apart, starting from top)
    angles = [270, 30, 150]
    for angle in angles:
        rad = math.radians(angle)
        x = center + int(orbit_radius * math.cos(rad))
        y = center + int(orbit_radius * math.sin(rad))
        draw.ellipse([
            x - outer_radius, y - outer_radius,
            x + outer_radius, y + outer_radius
        ], fill=trans_color)

    # Draw center dot
    draw.ellipse([
        center - center_radius, center - center_radius,
        center + center_radius, center + center_radius
    ], fill=dot_color)

    return img

def main():
    dot_color = (33, 150, 243)        # Solid blue
    trans_color = (33, 150, 243, 220) # Semi-transparent blue

    # Android icons — ring + blue dots, no background circle
    android_sizes = {
        'mipmap-mdpi': 48, 'mipmap-hdpi': 72, 'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144, 'mipmap-xxxhdpi': 192,
    }
    for folder, size in android_sizes.items():
        # Scale up artwork — dots overflow canvas edge, launcher mask clips them
        icon = create_icon(size, dot_color, trans_color, draw_ring=True,
                           custom_radii=(int(size*0.14), int(size*0.28), int(size*0.42)))
        path = f'android/app/src/main/res/{folder}/ic_launcher.png'
        icon.save(path, 'PNG')
        print(f'Generated: {path}')

    # Windows .ico — keep blue-circle background + white dots (unchanged)
    bg_color = (33, 150, 243)
    white = (255,255,255); white_trans = (255,255,255,220)
    ico_sizes = [16, 32, 48, 64, 128, 256]
    # Use old-style icon for Windows
    from PIL import ImageDraw as ID
    def old_icon(s):
        img = Image.new('RGBA', (s, s), (0,0,0,0))
        d = ID.Draw(img)
        m = int(s*0.02); d.ellipse([m,m,s-m,s-m], fill=bg_color)
        c = s//2; o_r=int(s*0.18); c_r=int(s*0.13); orb=int(s*0.28)
        for a in [270,30,150]:
            r=math.radians(a); x=c+int(orb*math.cos(r)); y=c+int(orb*math.sin(r))
            d.ellipse([x-o_r,y-o_r,x+o_r,y+o_r], fill=white_trans)
        d.ellipse([c-c_r,c-c_r,c+c_r,c+c_r], fill=white)
        return img
    ico_images = [old_icon(s) for s in ico_sizes]
    ico_path = 'windows/runner/resources/app_icon.ico'
    ico_images[-1].save(ico_path, format='ICO', sizes=[(s,s) for s in ico_sizes])
    print(f'Generated: {ico_path}')

    # macOS — keep blue-circle
    macos_sizes = {'app_icon_16.png':16,'app_icon_32.png':32,'app_icon_64.png':64,
                   'app_icon_128.png':128,'app_icon_256.png':256,'app_icon_512.png':512,'app_icon_1024.png':1024}
    mp = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    for fn, sz in macos_sizes.items():
        old_icon(sz).save(f'{mp}/{fn}','PNG'); print(f'Generated: {mp}/{fn}')

    # Web
    old_icon(32).save('web/favicon.png','PNG'); print('Generated: web/favicon.png')
    old_icon(192).save('web/icons/Icon-192.png','PNG'); print('Generated: web/icons/Icon-192.png')
    old_icon(512).save('web/icons/Icon-512.png','PNG'); print('Generated: web/icons/Icon-512.png')
    old_icon(512).save('icon_preview.png','PNG'); print('Generated: icon_preview.png')
    print('\nDone!')

if __name__ == '__main__':
    main()

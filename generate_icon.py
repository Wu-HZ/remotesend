"""
Generate app icon: small circle in center with 3 big circles around it.
Requires: pip install Pillow
"""
import math
from PIL import Image, ImageDraw

def create_icon(size, bg_color=(33, 150, 243), center_color=(255, 255, 255), outer_color=(255, 255, 255, 200)):
    """Create the RemoteSend icon."""
    # Create image with transparent background
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Draw circular background
    margin = int(size * 0.02)
    draw.ellipse([margin, margin, size - margin, size - margin], fill=bg_color)

    center = size // 2

    # Outer circles parameters
    outer_radius = int(size * 0.18)  # Big circles radius (slightly smaller)
    center_radius = int(size * 0.13)  # Small center circle radius
    orbit_radius = int(size * 0.28)  # Distance from center to outer circles (further out)

    # Draw 3 outer circles (120 degrees apart, starting from top)
    angles = [270, 30, 150]  # Top, bottom-right, bottom-left (in degrees)
    for angle in angles:
        rad = math.radians(angle)
        x = center + int(orbit_radius * math.cos(rad))
        y = center + int(orbit_radius * math.sin(rad))
        draw.ellipse([
            x - outer_radius,
            y - outer_radius,
            x + outer_radius,
            y + outer_radius
        ], fill=outer_color)

    # Draw center circle (on top, clearly visible)
    draw.ellipse([
        center - center_radius,
        center - center_radius,
        center + center_radius,
        center + center_radius
    ], fill=center_color)

    return img

def create_ico(images, output_path):
    """Create ICO file with multiple sizes."""
    images[0].save(output_path, format='ICO', sizes=[(img.width, img.height) for img in images])

def main():
    # Blue theme matching the app
    bg_color = (33, 150, 243)  # Material Blue 500
    center_color = (255, 255, 255)  # White
    outer_color = (255, 255, 255, 220)  # Semi-transparent white

    # Generate Android icons
    android_sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }

    for folder, size in android_sizes.items():
        icon = create_icon(size, bg_color, center_color, outer_color)
        path = f'android/app/src/main/res/{folder}/ic_launcher.png'
        icon.save(path, 'PNG')
        print(f'Generated: {path}')

    # Generate Windows icon (multiple sizes in one .ico)
    ico_sizes = [16, 32, 48, 64, 128, 256]
    ico_images = [create_icon(s, bg_color, center_color, outer_color) for s in ico_sizes]
    ico_path = 'windows/runner/resources/app_icon.ico'
    ico_images[-1].save(ico_path, format='ICO', sizes=[(s, s) for s in ico_sizes])
    print(f'Generated: {ico_path}')

    # Generate macOS icons
    macos_sizes = {
        'app_icon_16.png': 16,
        'app_icon_32.png': 32,
        'app_icon_64.png': 64,
        'app_icon_128.png': 128,
        'app_icon_256.png': 256,
        'app_icon_512.png': 512,
        'app_icon_1024.png': 1024,
    }

    macos_path = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    for filename, size in macos_sizes.items():
        icon = create_icon(size, bg_color, center_color, outer_color)
        path = f'{macos_path}/{filename}'
        icon.save(path, 'PNG')
        print(f'Generated: {path}')

    # Generate web favicon
    favicon = create_icon(32, bg_color, center_color, outer_color)
    favicon.save('web/favicon.png', 'PNG')
    print('Generated: web/favicon.png')

    # Generate a larger web icon
    web_icon = create_icon(192, bg_color, center_color, outer_color)
    web_icon.save('web/icons/Icon-192.png', 'PNG')
    print('Generated: web/icons/Icon-192.png')

    web_icon_512 = create_icon(512, bg_color, center_color, outer_color)
    web_icon_512.save('web/icons/Icon-512.png', 'PNG')
    print('Generated: web/icons/Icon-512.png')

    # Also save a high-res preview
    preview = create_icon(512, bg_color, center_color, outer_color)
    preview.save('icon_preview.png', 'PNG')
    print('Generated: icon_preview.png (512x512 preview)')

    print('\nDone! All icons generated.')

if __name__ == '__main__':
    main()

import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ASSETS_DIR = Path(r"C:\Users\mohal\Documents\antigravity\CarSpeak\CarSpeak\Assets.xcassets")
ICONSET_DIR = ASSETS_DIR / "AppIcon.appiconset"
ICONSET_DIR.mkdir(parents=True, exist_ok=True)

def cubic_bezier(p0, p1, p2, p3, steps=80):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1.0 - t
        x = (mt**3)*p0[0] + 3*(mt**2)*t*p1[0] + 3*mt*(t**2)*p2[0] + (t**3)*p3[0]
        y = (mt**3)*p0[1] + 3*(mt**2)*t*p1[1] + 3*mt*(t**2)*p2[1] + (t**3)*p3[1]
        pts.append((x, y))
    return pts

def build_head_profile_polygon(scale=4.0):
    """
    Constructs a smooth, anatomical, sculptural side-profile silhouette of a human head
    facing RIGHT on a 1024*scale canvas, with an expressive speaking mouth contour.
    """
    def S(pt):
        return (pt[0] * scale, pt[1] * scale)

    segments = [
        # Start at back-bottom of neck (left side of neck base)
        ((235, 845), (265, 775), (275, 705), (255, 635)),
        # Occiput / back of cranium curve upward
        ((255, 635), (185, 550), (165, 415), (210, 300)),
        # Crown of head curving forward toward forehead
        ((210, 300), (255, 190), (395, 145), (505, 185)),
        # Forehead down to brow ridge
        ((505, 185), (565, 210), (595, 275), (588, 332)),
        # Brow indentation (nasion)
        ((588, 332), (582, 352), (572, 362), (584, 378)),
        # Nasal bridge extending right to nose tip (pronasale)
        ((584, 378), (612, 415), (648, 458), (654, 480)),
        # Nose tip rounding underneath (columella to subnasale)
        ((654, 480), (658, 500), (625, 512), (598, 514)),
        # Philtrum down to upper lip vermilion border
        ((598, 514), (594, 526), (608, 538), (618, 548)),
        # Upper lip curving slightly inward into open/speaking mouth
        ((618, 548), (624, 558), (605, 568), (572, 574)),
        # Open speaking mouth recess (inner mouth curve)
        ((572, 574), (558, 582), (558, 598), (575, 606)),
        # Lower lip projecting outward
        ((575, 606), (604, 612), (616, 622), (604, 638)),
        # Mentolabial sulcus (dip above chin) to chin prominence (pogonion)
        ((604, 638), (590, 650), (608, 675), (604, 702)),
        # Chin rounding underneath (menton) back along jawline
        ((604, 702), (598, 735), (545, 748), (470, 742)),
        # Mandibular angle / submental neck drop
        ((470, 742), (432, 740), (425, 795), (442, 845)),
        # Base of neck (clean sculptural curve back to start)
        ((442, 845), (380, 868), (295, 868), (235, 845)),
    ]

    poly = []
    for p0, p1, p2, p3 in segments:
        pts = cubic_bezier(S(p0), S(p1), S(p2), S(p3), steps=60)
        poly.extend(pts[:-1])
    return poly

def draw_rounded_arc(draw, center, radius, start_deg, end_deg, width, color, steps=180):
    cx, cy = center
    half_w = width / 2.0
    outer_pts = []
    inner_pts = []
    for i in range(steps + 1):
        ang = math.radians(start_deg + (end_deg - start_deg) * (i / steps))
        ca, sa = math.cos(ang), math.sin(ang)
        outer_pts.append((cx + (radius + half_w) * ca, cy + (radius + half_w) * sa))
        inner_pts.append((cx + (radius - half_w) * ca, cy + (radius - half_w) * sa))
    poly = outer_pts + list(reversed(inner_pts))
    draw.polygon(poly, fill=color)
    # Draw round endcaps at start and end angles
    for deg in (start_deg, end_deg):
        ang = math.radians(deg)
        px = cx + radius * math.cos(ang)
        py = cy + radius * math.sin(ang)
        draw.ellipse([px - half_w, py - half_w, px + half_w, py + half_w], fill=color)

def draw_rounded_line(draw, p1, p2, width, color):
    x1, y1 = p1
    x2, y2 = p2
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy)
    if length == 0:
        return
    half_w = width / 2.0
    nx, ny = -dy / length * half_w, dx / length * half_w
    poly = [
        (x1 + nx, y1 + ny),
        (x2 + nx, y2 + ny),
        (x2 - nx, y2 - ny),
        (x1 - nx, y1 - ny),
    ]
    draw.polygon(poly, fill=color)
    for px, py in (p1, p2):
        draw.ellipse([px - half_w, py - half_w, px + half_w, py + half_w], fill=color)

def generate_icon():
    scale = 4
    size = 1024 * scale

    # Light warm studio background (#F7F8FA with subtle radial luminance)
    img = Image.new("RGB", (size, size), (246, 247, 250))
    draw = ImageDraw.Draw(img)

    # Subtle soft radial vignette on the light background for tactile depth
    # (Strictly 100% opaque RGB — zero alpha channel)
    for r_step in range(30, 0, -1):
        frac = r_step / 30.0
        rad = int(size * 0.72 * frac)
        c_val = int(244 + (253 - 244) * (1.0 - frac))
        col = (c_val, c_val + 1, min(255, c_val + 2))
        cx, cy = int(size * 0.48), int(size * 0.46)
        draw.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=col)

    black = (16, 18, 22)

    # 1. Draw the sculptural black human head profile
    head_poly = build_head_profile_polygon(scale=scale)
    draw.polygon(head_poly, fill=black)

    # 2. Draw speaking lines / acoustic waves emanating from the mouth (around x=635, y=588)
    mouth_origin = (632 * scale, 588 * scale)
    stroke_w = int(26 * scale)

    # Central horizontal speaking ray + upper/lower angled speaking rays + concentric voice wave arcs
    # Inner radiant speaking lines emanating directly from mouth:
    rays = [
        ((668 * scale, 588 * scale), (748 * scale, 588 * scale)),  # Center speaking line
        ((662 * scale, 548 * scale), (734 * scale, 512 * scale)),  # Upper speaking line
        ((662 * scale, 628 * scale), (734 * scale, 664 * scale)),  # Lower speaking line
    ]
    for p1, p2 in rays:
        draw_rounded_line(draw, p1, p2, width=int(24 * scale), color=black)

    # Outer acoustic wave arcs framing the speaking lines
    draw_rounded_arc(
        draw,
        center=(620 * scale, 588 * scale),
        radius=185 * scale,
        start_deg=-34,
        end_deg=34,
        width=int(26 * scale),
        color=black
    )
    draw_rounded_arc(
        draw,
        center=(620 * scale, 588 * scale),
        radius=255 * scale,
        start_deg=-40,
        end_deg=40,
        width=int(26 * scale),
        color=black
    )

    # Downsample with Lanczos to crisp 1024x1024 24-bit RGB PNG
    final_icon = img.resize((1024, 1024), Image.Resampling.LANCZOS).convert("RGB")
    icon_path = ICONSET_DIR / "AppIcon.png"
    final_icon.save(icon_path, format="PNG", optimize=True)

    # Write Apple-compliant Contents.json for Xcode 16 single-size 1024x1024 universal icon
    contents = {
        "images": [
            {
                "filename": "AppIcon.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024"
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1
        }
    }
    (ICONSET_DIR / "Contents.json").write_text(json.dumps(contents, indent=2), encoding="utf-8")
    (ASSETS_DIR / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2),
        encoding="utf-8"
    )
    print(f"Generated 1024x1024 RGB AppIcon at {icon_path} (mode={final_icon.mode}, size={final_icon.size})")

if __name__ == "__main__":
    generate_icon()

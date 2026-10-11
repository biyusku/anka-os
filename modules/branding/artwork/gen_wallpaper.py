"""Generate the ANKA wallpaper SVG: silk ribbons rising like a phoenix wing.

Usage: python3 gen_wallpaper.py wallpaper.svg
"""
import math
import sys

W, H = 3840, 2160

def bez(p0, p1, p2, p3, t):
    u = 1 - t
    return tuple(u**3*a + 3*u*u*t*b + 3*u*t*t*c + t**3*d for a, b, c, d in zip(p0, p1, p2, p3))

def ribbon(p, width_start, width_end, n=48):
    """Closed path around the cubic centreline p with a tapering width."""
    pts = [bez(*p, i / n) for i in range(n + 1)]
    left, right = [], []
    for i, (x, y) in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1
        nx, ny = -dy / length, dx / length
        w = (width_start + (width_end - width_start) * (i / n) ** 0.8) / 2
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    ring = left + right[::-1]
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in ring) + " Z"

ribbons = []
for k in range(6):
    p0 = (380 + 230 * k, H + 160)
    p1 = (1250 + 170 * k, 1640 - 70 * k)
    p2 = (1650 + 210 * k, 760 - 40 * k)
    p3 = (3350 + 70 * k, 120 + 150 * k)
    width = 520 - 62 * k
    ribbons.append((ribbon((p0, p1, p2, p3), width, 18), k))

out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">',
       "  <title>ANKA</title>",
       "  <!-- Generated: silk ribbons rising like a phoenix wing (deep red to gold) -->",
       "  <defs>",
       '    <radialGradient id="sky" cx="0.28" cy="1.05" r="1.2">',
       '      <stop offset="0" stop-color="#4a120e"/><stop offset="0.45" stop-color="#1d0908"/>',
       '      <stop offset="1" stop-color="#070303"/>',
       "    </radialGradient>"]
palette = ["#7d1d16", "#a9281e", "#c0392b", "#dd5520", "#ee8a24", "#f6b93b"]
for k, col in enumerate(palette):
    out.append(f'    <linearGradient id="r{k}" x1="0" y1="1" x2="1" y2="0">'
               f'<stop offset="0" stop-color="{col}" stop-opacity="0"/>'
               f'<stop offset="0.35" stop-color="{col}" stop-opacity="0.95"/>'
               f'<stop offset="1" stop-color="#ffd79a" stop-opacity="0.85"/></linearGradient>')
out += ['    <filter id="blur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="110"/></filter>',
        '    <filter id="soft"><feGaussianBlur stdDeviation="3"/></filter>',
        "  </defs>",
        f'  <rect width="{W}" height="{H}" fill="url(#sky)"/>',
        '  <ellipse cx="1300" cy="2100" rx="1700" ry="560" fill="#c0392b" opacity="0.22" filter="url(#blur)"/>']
for d, k in ribbons:
    out.append(f'  <path d="{d}" fill="url(#r{k})" opacity="0.30" filter="url(#blur)"/>')
for d, k in ribbons:
    out.append(f'  <path d="{d}" fill="url(#r{k})" opacity="{0.55 + 0.07 * k:.2f}" filter="url(#soft)"/>')
out.append("</svg>")
open(sys.argv[1], "w").write("\n".join(out) + "\n")

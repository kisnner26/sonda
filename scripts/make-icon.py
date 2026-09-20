"""genera el icono de sonda: papel crema, anillos de señal en tinta y una flor pequeña en el centro."""
import math, sys
from PIL import Image, ImageDraw

INK, PAPER = (26, 18, 8), (245, 240, 232)
S = 2048            # se dibuja al doble y se reduce, para bordes suaves
out = sys.argv[1] if len(sys.argv) > 1 else "icon-1024.png"

img = Image.new("RGB", (S, S), PAPER)
d = ImageDraw.Draw(img)
cx = cy = S / 2

def arc(r, start, end, width):
    d.arc((cx - r, cy - r, cx + r, cy + r), start=start, end=end, fill=INK, width=width)

# anillos de señal: cada uno se interrumpe en un hueco distinto, como las ondas que salen de una sonda
for i, r in enumerate((420, 600, 780, 960)):
    gap = 50 - i * 8
    start = -100 + i * 37
    arc(r, start + gap, start + 360 - gap, 16)
    # un puntito en el extremo del arco, como el frente de la onda
    a = math.radians(start + gap)
    x, y = cx + r * math.cos(a), cy + r * math.sin(a)
    d.ellipse((x - 22, y - 22, x + 22, y + 22), fill=INK)

# flor central: ocho petalos de trazo alrededor de un disco
def petal(angle, inner, outer, half_w, fill):
    pts = []
    for k in range(64):
        t = 2 * math.pi * k / 64
        px = half_w * math.cos(t)
        py = -(inner + (outer - inner) / 2) + (outer - inner) / 2 * math.sin(t)
        pts.append((cx + px * math.cos(angle) - py * math.sin(angle), cy + px * math.sin(angle) + py * math.cos(angle)))
    d.polygon(pts, fill=fill, outline=INK, width=14)

for i in range(8):
    petal(2 * math.pi * i / 8, 118, 330, 82, INK if i % 2 == 0 else PAPER)
r = 128
d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=PAPER, outline=INK, width=14)
for k in range(12):
    a = 2 * math.pi * k / 12
    x, y = cx + 60 * math.cos(a), cy + 60 * math.sin(a)
    d.ellipse((x - 8, y - 8, x + 8, y + 8), fill=INK)

img.resize((1024, 1024), Image.LANCZOS).save(out)
print("icono", out)

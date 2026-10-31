"""Draws the manager icon: a snowflake on a navy tile with an orange mod badge.

Run from the repository root with Pillow installed:
    python manager/Assets/make_icon.py
Writes Manager.png (512 px) and Manager.ico (16-256 px) next to this file.
Small sizes use simpler shapes, so they stay readable instead of blurring.
"""
import math
import struct
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

HERE = Path(__file__).resolve().parent
SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)
TOP = (44, 86, 140)
BOTTOM = (18, 40, 74)
ICE = (234, 246, 255)
ORANGE = (245, 140, 40)


def tier(size):
    """Geometry in target pixels. Small icons drop the branches and the puzzle glyph."""
    if size <= 20:
        return dict(margin=0, radius=size * 0.22, center=size * 0.44, arm=size * 0.36, stroke=2.0,
                    branch=0, badge=size * 0.40, inset=0, ring=1.0, glyph=False)
    if size <= 40:
        return dict(margin=0.5, radius=size * 0.21, center=size * 0.43, arm=size * 0.33, stroke=size / 11,
                    branch=0.32 if size >= 32 else 0, badge=size * 0.38, inset=size * 0.03, ring=size / 22,
                    glyph=False)
    return dict(margin=size * 0.03, radius=size * 0.2, center=size * 0.42, arm=size * 0.30,
                stroke=size * 0.075, branch=0.33, badge=size * 0.36, inset=size * 0.05, ring=size * 0.04,
                glyph=size >= 64)


def segment(draw, a, b, width, fill):
    draw.line([a, b], fill=fill, width=max(1, round(width)))
    r = width / 2
    for x, y in (a, b):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def disc(canvas, cx, cy, r):
    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    return mask


def puzzle(canvas, cx, cy, body):
    """Puzzle piece with knobs on top and right, centered on cx, cy."""
    mask = Image.new("L", (canvas, canvas), 0)
    d = ImageDraw.Draw(mask)
    k, reach = body * 0.2, body * 0.3
    x, y = cx - (body + reach) / 2, cy - (body - reach) / 2
    d.rounded_rectangle([x, y, x + body, y + body], radius=body * 0.1, fill=255)
    neck = body * 0.13
    d.rectangle([x + body / 2 - neck, y - reach + k, x + body / 2 + neck, y], fill=255)
    d.ellipse([x + body / 2 - k, y - reach, x + body / 2 + k, y - reach + 2 * k], fill=255)
    d.rectangle([x + body, y + body / 2 - neck, x + body + reach - k, y + body / 2 + neck], fill=255)
    d.ellipse([x + body + reach - 2 * k, y + body / 2 - k, x + body + reach, y + body / 2 + k], fill=255)
    return mask


def render(size):
    g = tier(size)
    ss = max(4, 1024 // size)
    n = size * ss
    s = lambda v: v * ss

    # Navy tile with a vertical gradient.
    gradient = Image.new("RGB", (1, n))
    for y in range(n):
        t = y / (n - 1)
        gradient.putpixel((0, y), tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    gradient = gradient.resize((n, n))
    tile = Image.new("L", (n, n), 0)
    m = s(g["margin"])
    ImageDraw.Draw(tile).rounded_rectangle([m, m, n - m - 1, n - m - 1], radius=s(g["radius"]), fill=255)
    out = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    out.paste(gradient, (0, 0), tile)

    # Six-armed snowflake, one arm vertical.
    flake = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(flake)
    c, arm, width = s(g["center"]), s(g["arm"]), s(g["stroke"])
    for i in range(6):
        angle = math.radians(90 + 60 * i)
        dx, dy = math.cos(angle), -math.sin(angle)
        segment(d, (c, c), (c + dx * arm, c + dy * arm), width, 255)
        if g["branch"]:
            base = (c + dx * arm * 0.55, c + dy * arm * 0.55)
            for turn in (-50, 50):
                b = angle + math.radians(turn)
                length = arm * g["branch"]
                segment(d, base, (base[0] + math.cos(b) * length, base[1] - math.sin(b) * length), width * 0.85, 255)

    # Orange disc in the lower right; a ring of tile color cuts it free from the flake.
    r = s(g["badge"]) / 2
    center = n - m - s(g["inset"]) - r
    flake = ImageChops.subtract(flake, disc(n, center, center, r + s(g["ring"])))
    out.paste(Image.new("RGBA", (n, n), ICE + (255,)), (0, 0), ImageChops.multiply(flake, tile))
    out.paste(Image.new("RGBA", (n, n), ORANGE + (255,)), (0, 0), disc(n, center, center, r))
    if g["glyph"]:
        out.paste(Image.new("RGBA", (n, n), BOTTOM + (255,)), (0, 0), puzzle(n, center, center, r * 0.86))
    return out.reduce(ss)


def bmp_entry(image):
    """32-bit DIB frame; small sizes as BMP load everywhere, including old .NET Icon code paths."""
    w, h = image.size
    pixels = image.convert("RGBA").transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA")
    mask_row = ((w + 31) // 32) * 4
    header = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, len(pixels) + mask_row * h, 0, 0, 0, 0)
    return header + pixels + b"\0" * (mask_row * h)


def write_ico(path, frames):
    blobs = []
    for image in frames:
        if image.width >= 128:
            buffer = BytesIO()
            image.save(buffer, "PNG", optimize=True)
            blobs.append(buffer.getvalue())
        else:
            blobs.append(bmp_entry(image))
    offset = 6 + 16 * len(frames)
    data = struct.pack("<HHH", 0, 1, len(frames))
    for image, blob in zip(frames, blobs):
        side = 0 if image.width >= 256 else image.width
        data += struct.pack("<BBBBHHII", side, side, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
    path.write_bytes(data + b"".join(blobs))


if __name__ == "__main__":
    frames = [render(size) for size in SIZES]
    write_ico(HERE / "Manager.ico", frames)
    render(512).save(HERE / "Manager.png", optimize=True)

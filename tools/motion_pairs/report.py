"""Evidence images for a pair: the side-by-side GIF and the +0/50/100/200/300 ms strip. Needs Pillow and ``video.frames_at``."""

from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Dict, List, Sequence

from PIL import Image, ImageDraw, ImageFont

from . import video

STRIP_TIMES = (0, 50, 100, 200, 300)
REF_COLOUR = (255, 210, 90)
NAT_COLOUR = (120, 200, 255)


def _grab(clip: Path, onset_ms: float, offsets: Sequence[int], width: int) -> List[Image.Image]:
    with tempfile.TemporaryDirectory() as tmp:
        times = [max(onset_ms + o, 0) for o in offsets]
        got = video.frames_at(clip, Path(tmp), times, width)
        images = []
        for t in times:
            path = got.get(int(t))
            images.append(Image.open(path).convert("RGB") if path else Image.new("RGB", (width, int(width * 2.17)), (40, 40, 40)))
        return images


def make_strip(out: Path, rows: Sequence[Dict], times: Sequence[int] = STRIP_TIMES, width: int = 200) -> Path:
    """``rows``: dicts ``{label, clip, onsetMs, colour}``. Each row is one clip; time 0 is its own onset."""
    font = ImageFont.load_default()
    cells = [(r, _grab(Path(r["clip"]), r["onsetMs"], times, width)) for r in rows]
    h = max(im.height for _, ims in cells for im in ims)
    pad, head = 4, 16
    sheet = Image.new("RGB", (len(times) * (width + pad) + pad, head + len(cells) * (h + head + pad) + pad), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    for c, t in enumerate(times):
        dr.text((pad + c * (width + pad) + 4, 3), "+%d ms" % t, fill=(255, 255, 255), font=font)
    y = head
    for r, ims in cells:
        dr.text((pad + 4, y + 2), "%s (onset at clip %d ms)" % (r["label"], r["onsetMs"]), fill=tuple(r.get("colour", REF_COLOUR)), font=font)
        for c, im in enumerate(ims):
            sheet.paste(im, (pad + c * (width + pad), y + head))
        y += h + head + pad
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return out


def make_pair_gif(out: Path, reference: Dict, native: Dict, pre_ms: int = 300, post_ms: int = 1100, fps: int = 20, width: int = 220) -> Path:
    """Reference left, native right, both aligned at their own onset, one frame per ``1000 / fps`` ms from ``-pre_ms`` to ``+post_ms``."""
    step = 1000 // fps
    offsets = list(range(-pre_ms, post_ms + 1, step))
    left = _grab(Path(reference["clip"]), reference["onsetMs"], offsets, width)
    right = _grab(Path(native["clip"]), native["onsetMs"], offsets, width)
    font = ImageFont.load_default()
    frames = []
    for o, l, r in zip(offsets, left, right):
        w = l.width + r.width + 6
        im = Image.new("RGB", (w, l.height + 16), (20, 20, 20))
        im.paste(l, (0, 16))
        im.paste(r, (l.width + 6, 16))
        dr = ImageDraw.Draw(im)
        dr.text((3, 3), "reference", fill=REF_COLOUR, font=font)
        dr.text((l.width + 9, 3), "native", fill=NAT_COLOUR, font=font)
        dr.text((w - 60, 3), "%+d ms" % o, fill=(255, 255, 255), font=font)
        frames.append(im.quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    out.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=step, loop=0, optimize=True, disposal=1)
    return out

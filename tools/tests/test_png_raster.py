"""Tests for tools/png_raster.py: every supported PNG shape decodes to the same RGB, and damaged files are refused."""

from __future__ import annotations

import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import png_raster as pr  # noqa: E402

W, H = 5, 4


def make(kind: int, pixels: list, *, filt: int = 0, palette: bytes = b"", depth: int = 8, interlace: int = 0) -> bytes:
    """A PNG whose rows (lists of byte values) are filtered with ``filt`` the way an encoder would."""
    bpp = pr.CHANNELS[kind]
    raw, prior = b"", bytearray(W * bpp)
    for row in pixels:
        line = bytearray(row)
        out = bytearray(line)
        for i in range(len(line)):
            left = line[i - bpp] if i >= bpp else 0
            up = prior[i]
            corner = prior[i - bpp] if i >= bpp else 0
            predict = {0: 0, 1: left, 2: up, 3: (left + up) >> 1, 4: pr._paeth(left, up, corner)}[filt]
            out[i] = (line[i] - predict) & 255
        raw += bytes([filt]) + bytes(out)
        prior = line
    body = struct.pack(">IIBBBBB", W, H, depth, kind, 0, 0, interlace)
    extra = pr._chunk(b"PLTE", palette) if palette else b""
    return pr.SIGNATURE + pr._chunk(b"IHDR", body) + extra + pr._chunk(b"IDAT", zlib.compress(raw)) + pr._chunk(b"IEND", b"")


def rows_of(channels: int) -> list:
    return [[(x * 31 + y * 17 + c * 7) % 256 for x in range(W) for c in range(channels)] for y in range(H)]


class DecodeTests(unittest.TestCase):
    def test_every_filter_decodes_rgb_the_same(self) -> None:
        rows = rows_of(3)
        want = b"".join(bytes(r) for r in rows)
        for filt in range(5):
            raster = pr.decode(make(2, rows, filt=filt))
            self.assertEqual((raster.size, raster.data), ((W, H), want), filt)

    def test_rgba_drops_alpha(self) -> None:
        rows = rows_of(4)
        raster = pr.decode(make(6, rows, filt=4))
        self.assertEqual(raster.row(1), bytes(v for i, v in enumerate(rows[1]) if i % 4 != 3))

    def test_grey_and_grey_alpha_expand(self) -> None:
        grey = pr.decode(make(0, rows_of(1), filt=1))
        self.assertEqual(grey.row(0), bytes(v for v in rows_of(1)[0] for _ in range(3)))
        both = pr.decode(make(4, rows_of(2), filt=3))
        self.assertEqual(both.row(0), bytes(v for i, v in enumerate(rows_of(2)[0]) if i % 2 == 0 for _ in range(3)))

    def test_palette_expands(self) -> None:
        palette = bytes(range(0, 30))
        rows = [[(x + y) % 10 for x in range(W)] for y in range(H)]
        raster = pr.decode(make(3, rows, palette=palette))
        self.assertEqual(raster.row(0), bytes(palette[i * 3 + c] for i in rows[0] for c in range(3)))

    def test_round_trip_through_a_file(self) -> None:
        raster = pr.Raster(W, H, b"".join(bytes(r) for r in rows_of(3)))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.png"
            pr.write(raster, path)
            self.assertEqual(pr.read(path), raster)

    def test_refusals(self) -> None:
        good = make(2, rows_of(3))
        for blob in (b"nope", good[:40], make(2, rows_of(3), depth=16), make(2, rows_of(3), interlace=1),
                     make(3, rows_of(1)), good.replace(b"IDAT", b"IDAT", 1)[:-30] + b"\x00" * 18):
            with self.assertRaises(pr.PngError):
                pr.decode(blob)


if __name__ == "__main__":
    unittest.main()

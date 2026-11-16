"""png_raster: read and write 8-bit PNG frames with the standard library only (no Pillow).

``tools/expo_pair_compare.py`` judges simulator screenshots on a CI runner that has no third-party Python packages, so it
decodes frames here. A frame decodes to a :class:`Raster`: width, height and packed RGB bytes (alpha is dropped, grey and
palette images are expanded). Supported input: bit depth 8, colour types grey, RGB, palette, grey+alpha and RGBA, not
interlaced; anything else raises :class:`PngError`. Output is always 8-bit RGB.
"""

from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

SIGNATURE = b"\x89PNG\r\n\x1a\n"
#: Channels per pixel by PNG colour type (grey, RGB, palette, grey+alpha, RGBA).
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


class PngError(ValueError):
    """The file is not a PNG this module can read."""


@dataclass
class Raster:
    """A decoded frame: ``data`` is ``width * height * 3`` bytes of row-major RGB."""

    width: int
    height: int
    data: bytes

    @property
    def size(self) -> Tuple[int, int]:
        return self.width, self.height

    def row(self, y: int) -> bytes:
        """The RGB bytes of row ``y``."""
        stride = self.width * 3
        return self.data[y * stride:(y + 1) * stride]


# MARK: - Reading

def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)


def _unfilter(raw: bytes, width: int, height: int, bpp: int) -> List[bytearray]:
    """Undo the per-row PNG filters; each returned row holds ``width * bpp`` bytes."""
    stride = width * bpp
    if len(raw) < height * (stride + 1):
        raise PngError("truncated image data")
    rows: List[bytearray] = []
    prior = bytearray(stride)
    pos = 0
    for _ in range(height):
        kind = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += stride + 1
        if kind == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif kind == 2:
            line = bytearray((x + y) & 255 for x, y in zip(line, prior))
        elif kind == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prior[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(min(bpp, stride)):  # no left neighbour: Paeth reduces to Up
                line[i] = (line[i] + prior[i]) & 255
            for i in range(bpp, stride):
                a, b, c = line[i - bpp], prior[i], prior[i - bpp]
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - c - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        elif kind != 0:
            raise PngError(f"unknown filter {kind}")
        rows.append(line)
        prior = line
    return rows


def _to_rgb(rows: List[bytearray], width: int, kind: int, palette: Optional[bytes]) -> bytes:
    out = bytearray()
    for line in rows:
        if kind == 2:
            out += line
        elif kind == 6:
            rgb = bytearray(width * 3)
            rgb[0::3], rgb[1::3], rgb[2::3] = line[0::4], line[1::4], line[2::4]
            out += rgb
        elif kind in (0, 4):
            grey = line[0::2] if kind == 4 else line
            rgb = bytearray(width * 3)
            rgb[0::3] = rgb[1::3] = rgb[2::3] = grey
            out += rgb
        else:
            if palette is None:
                raise PngError("palette image without a PLTE chunk")
            for index in line:
                out += palette[index * 3:index * 3 + 3]
    return bytes(out)


def decode(blob: bytes) -> Raster:
    """Decode PNG bytes to a :class:`Raster`.

    Raises:
        PngError: The data is not an 8-bit, non-interlaced PNG, or it is damaged.
    """
    if not blob.startswith(SIGNATURE):
        raise PngError("not a PNG file")
    pos, header, palette, idat = len(SIGNATURE), None, None, bytearray()
    while pos + 8 <= len(blob):
        length, tag = struct.unpack(">I4s", blob[pos:pos + 8])
        body = blob[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif tag == b"PLTE":
            palette = bytes(body)
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
    if header is None:
        raise PngError("missing IHDR")
    width, height, depth, kind, _, _, interlace = header
    if depth != 8 or kind not in CHANNELS or interlace != 0:
        raise PngError(f"unsupported PNG (depth {depth}, colour type {kind}, interlace {interlace})")
    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error as error:
        raise PngError(f"damaged image data: {error}") from error
    rows = _unfilter(raw, width, height, CHANNELS[kind])
    return Raster(width, height, _to_rgb(rows, width, kind, palette))


def read(path: Path) -> Raster:
    """Decode the PNG at ``path``."""
    return decode(Path(path).read_bytes())


# MARK: - Writing

def _chunk(tag: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)


def encode(raster: Raster) -> bytes:
    """PNG bytes for an 8-bit RGB raster (no filtering)."""
    stride = raster.width * 3
    raw = b"".join(b"\x00" + raster.data[y * stride:(y + 1) * stride] for y in range(raster.height))
    header = struct.pack(">IIBBBBB", raster.width, raster.height, 8, 2, 0, 0, 0)
    return SIGNATURE + _chunk(b"IHDR", header) + _chunk(b"IDAT", zlib.compress(raw, 6)) + _chunk(b"IEND", b"")


def write(raster: Raster, path: Path) -> None:
    """Write ``raster`` to ``path`` as a PNG."""
    Path(path).write_bytes(encode(raster))

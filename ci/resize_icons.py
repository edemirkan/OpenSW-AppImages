#!/usr/bin/env python3
import array
import math
import struct
import zlib
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ICON_SIZES = (512, 256, 128, 96, 64, 48)
PROJECTS = ("opentie", "openxwa", "openxvt")


def read_rgba_png(path):
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"Not a PNG file: {path}")

    width = height = None
    image_data = bytearray()
    offset = len(PNG_SIGNATURE)
    while offset < len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        chunk_type = data[offset + 4:offset + 8]
        chunk_data = data[offset + 8:offset + 8 + length]
        crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        if zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF != crc:
            raise ValueError(f"Invalid PNG checksum in {path}")
        offset += length + 12

        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", chunk_data
            )
            if (bit_depth, color_type, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                raise ValueError(f"Expected non-interlaced 8-bit RGBA PNG: {path}")
        elif chunk_type == b"IDAT":
            image_data.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    if not width or not height:
        raise ValueError(f"PNG is missing a valid IHDR chunk: {path}")

    raw = zlib.decompress(image_data)
    stride = width * 4
    pixels = bytearray(height * stride)
    previous_row = bytearray(stride)
    raw_offset = 0

    for y in range(height):
        filter_type = raw[raw_offset]
        raw_offset += 1
        row = bytearray(raw[raw_offset:raw_offset + stride])
        raw_offset += stride

        for index in range(stride):
            left = row[index - 4] if index >= 4 else 0
            above = previous_row[index]
            upper_left = previous_row[index - 4] if index >= 4 else 0
            if filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                base = left + above - upper_left
                left_distance = abs(base - left)
                above_distance = abs(base - above)
                upper_left_distance = abs(base - upper_left)
                predictor = (
                    left if left_distance <= above_distance and left_distance <= upper_left_distance
                    else above if above_distance <= upper_left_distance
                    else upper_left
                )
            elif filter_type == 0:
                predictor = 0
            else:
                raise ValueError(f"Unsupported PNG filter {filter_type} in {path}")
            row[index] = (row[index] + predictor) & 0xFF

        pixels[y * stride:(y + 1) * stride] = row
        previous_row = row

    return width, height, pixels


def area_weights(source_size, target_size):
    scale = source_size / target_size
    weights = []
    for target_index in range(target_size):
        start = target_index * scale
        end = (target_index + 1) * scale
        first = math.floor(start)
        last = math.ceil(end)
        samples = []
        for source_index in range(first, last):
            overlap = min(end, source_index + 1) - max(start, source_index)
            if overlap > 0:
                samples.append((source_index, overlap / scale))
        weights.append(samples)
    return weights


def resize_rgba(pixels, source_width, source_height, size):
    horizontal_weights = area_weights(source_width, size)
    vertical_weights = area_weights(source_height, size)
    intermediate = array.array("f", [0.0]) * (source_height * size * 4)

    for y in range(source_height):
        source_row = y * source_width * 4
        target_row = y * size * 4
        for x, samples in enumerate(horizontal_weights):
            target_offset = target_row + x * 4
            for source_x, weight in samples:
                source_offset = source_row + source_x * 4
                alpha = pixels[source_offset + 3]
                intermediate[target_offset] += pixels[source_offset] * alpha / 255 * weight
                intermediate[target_offset + 1] += pixels[source_offset + 1] * alpha / 255 * weight
                intermediate[target_offset + 2] += pixels[source_offset + 2] * alpha / 255 * weight
                intermediate[target_offset + 3] += alpha * weight

    resized = array.array("f", [0.0]) * (size * size * 4)
    for y, samples in enumerate(vertical_weights):
        for x in range(size):
            target_offset = (y * size + x) * 4
            for source_y, weight in samples:
                source_offset = (source_y * size + x) * 4
                for channel in range(4):
                    resized[target_offset + channel] += intermediate[source_offset + channel] * weight

    output = bytearray(size * size * 4)
    for offset in range(0, len(output), 4):
        alpha = min(255, max(0, round(resized[offset + 3])))
        output[offset + 3] = alpha
        if alpha:
            for channel in range(3):
                output[offset + channel] = min(255, round(resized[offset + channel] * 255 / alpha))

    return output


def png_chunk(chunk_type, chunk_data):
    checksum = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
    return struct.pack(">I", len(chunk_data)) + chunk_type + chunk_data + struct.pack(">I", checksum)


def write_rgba_png(path, size, pixels):
    rows = bytearray()
    stride = size * 4
    for y in range(size):
        rows.append(0)
        rows.extend(pixels[y * stride:(y + 1) * stride])

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    path.write_bytes(
        PNG_SIGNATURE
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(rows, level=9))
        + png_chunk(b"IEND", b"")
    )


def main():
    root = Path(__file__).resolve().parents[1]
    for project in PROJECTS:
        source = root / "packaging" / "linux" / project / "icon-1024.png"
        width, height, pixels = read_rgba_png(source)
        if width != 1024 or height != 1024:
            raise ValueError(f"Expected 1024x1024 source icon: {source}")

        for size in ICON_SIZES:
            output = source.with_name(f"icon-{size}.png")
            write_rgba_png(output, size, resize_rgba(pixels, width, height, size))
            print(output.relative_to(root))


if __name__ == "__main__":
    main()
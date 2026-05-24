#!/usr/bin/env python3
"""
ADM BWF WAV → Spatial Mix Converter

Reads an ADM BWF WAV from Dolby Atmos Renderer, extracts:
- Individual object audio as M4A stems
- Stereo bed as M4A
- Position data from AXML metadata
- Generates manifest.json compatible with Cloud Apple TV Solo

Usage: python3 adm_convert.py <input.wav> <output_dir> [name]
"""

import sys
import os
import json
import struct
import math
import subprocess
import xml.etree.ElementTree as ET

def read_axml_chunk(wav_path):
    """Extract AXML chunk from BWF/BW64/RF64 file."""
    with open(wav_path, 'rb') as f:
        riff = f.read(4)
        if riff not in (b'RIFF', b'BW64', b'RF64'):
            raise ValueError(f"Not a WAV/BW64/RF64 file: {riff}")
        f.read(4)  # file size
        f.read(4)  # WAVE

        # For RF64: read ds64 to get actual data chunk size
        rf64_data_size = None

        while True:
            chunk_id = f.read(4)
            if len(chunk_id) < 4:
                break
            chunk_size_bytes = f.read(4)
            if len(chunk_size_bytes) < 4:
                break

            chunk_size = struct.unpack('<I', chunk_size_bytes)[0]

            if chunk_id == b'ds64':
                ds64_data = f.read(chunk_size + (chunk_size % 2))
                # ds64: riffSize(8) + dataSize(8) + sampleCount(8) + ...
                if len(ds64_data) >= 16:
                    rf64_data_size = struct.unpack('<Q', ds64_data[8:16])[0]
                    print(f"  RF64 data size: {rf64_data_size:,} bytes")
                continue

            # RF64: data chunk has 0xFFFFFFFF — use ds64 size
            if chunk_id == b'data' and chunk_size == 0xFFFFFFFF and rf64_data_size:
                chunk_size = rf64_data_size

            if chunk_id == b'axml':
                # For very large AXML (multi-GB), read it
                print(f"  Reading AXML chunk: {chunk_size:,} bytes...")
                data = f.read(chunk_size)
                return data.decode('utf-8', errors='replace')

            # Skip chunk (pad to even)
            f.seek(chunk_size + (chunk_size % 2), 1)

    return None


def parse_adm_positions(axml_str, duration, fps=30):
    """Parse ADM XML to extract object positions over time."""
    # Remove BOM if present
    if axml_str.startswith('\ufeff'):
        axml_str = axml_str[1:]

    print(f"  Parsing {len(axml_str):,} bytes of ADM XML...")
    root = ET.fromstring(axml_str)
    print(f"  XML parsed OK")

    # Namespace handling
    ns = {}
    for prefix, uri in [('', 'urn:ebu:metadata-schema:ebuCore_2015'),
                         ('adm', 'urn:ebu:metadata-schema:ebuCore_2015')]:
        ns[prefix] = uri

    # Try to find audioObject and audioBlockFormat elements
    # ADM uses various namespace patterns
    objects = {}

    # Find all audioBlockFormat elements with position data
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag

        if tag == 'audioObject':
            obj_id = elem.get('audioObjectID', '')
            obj_name = elem.get('audioObjectName', obj_id)
            # Find linked audioTrackUID
            for child in elem:
                child_tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if child_tag == 'audioTrackUIDRef':
                    track_uid = child.text.strip() if child.text else ''
                    objects[obj_id] = {'name': obj_name, 'track_uid': track_uid, 'blocks': []}

    # Find audioChannelFormat with audioBlockFormat position data
    channel_formats = {}
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag

        if tag == 'audioChannelFormat':
            cf_id = elem.get('audioChannelFormatID', '')
            cf_name = elem.get('audioChannelFormatName', '')
            blocks = []

            for child in elem:
                child_tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if child_tag == 'audioBlockFormat':
                    block = parse_block_format(child)
                    if block:
                        blocks.append(block)

            if blocks:
                channel_formats[cf_id] = {'name': cf_name, 'blocks': blocks}

    # Convert block positions to per-frame arrays
    total_frames = int(duration * fps)
    result = []

    for cf_id, cf_data in sorted(channel_formats.items()):
        blocks = cf_data['blocks']
        if not blocks:
            continue

        # Skip bed channels (type 0001 = DirectSpeakers)
        if 'AC_00010' in cf_id:
            continue

        x_frames = []
        y_frames = []
        z_frames = []

        for frame_idx in range(total_frames):
            t = frame_idx / fps

            # Find the block that covers this time
            block = find_block_at_time(blocks, t)
            if block:
                x, y, z = block['x'], block['y'], block['z']
            else:
                x, y, z = 0.0, 0.0, -2.0

            x_frames.append(round(x, 4))
            y_frames.append(round(y, 4))
            z_frames.append(round(z, 4))

        result.append({
            'name': cf_data['name'],
            'x': x_frames,
            'y': y_frames,
            'z': z_frames
        })

    return result


def parse_block_format(elem):
    """Parse an audioBlockFormat element for position data."""
    block = {'time': 0.0, 'duration': 0.0, 'x': 0.0, 'y': 0.0, 'z': 0.0}

    # Parse rtime (start time)
    rtime = elem.get('rtime', '00:00:00.00000')
    block['time'] = parse_adm_time(rtime)

    # Parse duration
    dur = elem.get('duration', '00:00:00.00000')
    block['duration'] = parse_adm_time(dur)

    # Check for cartesian flag
    is_cartesian = False
    for child in elem:
        tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
        if tag == 'cartesian':
            is_cartesian = child.text and child.text.strip() == '1'

    # Parse position
    for child in elem:
        tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
        if tag == 'position':
            coord = child.get('coordinate', '')
            val = float(child.text.strip()) if child.text else 0.0

            if is_cartesian:
                if coord == 'X': block['x'] = val * 4.0  # Scale to mixer range
                elif coord == 'Y': block['z'] = -val * 4.0  # Y in ADM → -Z in our space
                elif coord == 'Z': block['y'] = val * 4.0  # Z in ADM → Y (height)
            else:
                # Polar: azimuth, elevation, distance
                if coord == 'azimuth': block['_az'] = val
                elif coord == 'elevation': block['_el'] = val
                elif coord == 'distance': block['_dist'] = val

    # Convert polar to cartesian if needed
    if '_az' in block:
        az = math.radians(block.get('_az', 0))
        el = math.radians(block.get('_el', 0))
        dist = block.get('_dist', 1.0) * 4.0  # Scale to mixer range

        block['x'] = round(dist * math.sin(az) * math.cos(el), 4)
        block['y'] = round(dist * math.sin(el), 4)
        block['z'] = round(-dist * math.cos(az) * math.cos(el), 4)

    return block


def find_block_at_time(blocks, t):
    """Find the audioBlockFormat that covers time t."""
    for block in reversed(blocks):
        if block['time'] <= t:
            return block
    return blocks[0] if blocks else None


def parse_adm_time(time_str):
    """Parse ADM time format HH:MM:SS.SSSSS to seconds."""
    try:
        parts = time_str.replace('S', '').split(':')
        if len(parts) == 3:
            return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
        return float(time_str)
    except:
        return 0.0


def probe_audio(wav_path):
    """Get channel count and duration via ffprobe."""
    result = subprocess.run([
        'ffprobe', '-v', 'quiet', '-print_format', 'json',
        '-show_streams', '-select_streams', 'a:0', wav_path
    ], capture_output=True, text=True)

    info = json.loads(result.stdout)
    stream = info['streams'][0]
    return {
        'channels': int(stream.get('channels', 2)),
        'duration': float(stream.get('duration', 0)),
        'sample_rate': int(stream.get('sample_rate', 48000))
    }


def extract_stems(wav_path, output_dir, channel_count):
    """Extract bed (stereo) + N object stems as M4A in a SINGLE ffmpeg pass.

    Reads the input WAV exactly once and runs all AAC encoders in parallel
    inside ffmpeg via -filter_complex multi-output. For an 8 GB input with
    8 objects, this turns ~72 GB of redundant disk reads into ~8 GB.
    """
    bed_channels = min(2, channel_count)
    object_count = max(0, channel_count - bed_channels)

    # Build -filter_complex string: one pan per output, labeled [bed], [o1]..[oN].
    filter_parts = ['[0:a]pan=stereo|c0=c0|c1=c1[bed]']
    for i in range(object_count):
        ch_idx = bed_channels + i
        filter_parts.append(f'[0:a]pan=mono|c0=c{ch_idx}[o{i+1}]')
    filter_complex = ';'.join(filter_parts)

    # Build the ffmpeg command with one -map per labeled output.
    cmd = [
        'ffmpeg', '-nostdin', '-y',
        '-i', wav_path,
        '-filter_complex', filter_complex,
        '-map', '[bed]', '-c:a', 'aac', '-b:a', '256k', '-ar', '48000',
        os.path.join(output_dir, 'bed.m4a'),
    ]
    for i in range(object_count):
        cmd.extend([
            '-map', f'[o{i+1}]', '-c:a', 'aac', '-b:a', '128k', '-ar', '48000',
            os.path.join(output_dir, f'obj-{i+1:02d}.m4a'),
        ])

    print(f"  Splitting bed + {object_count} objects in a single ffmpeg pass...")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        # Surface failure so the Swift side can mark the job as .failed.
        tail = (result.stderr or '').splitlines()[-20:]
        raise RuntimeError(
            f"ffmpeg single-pass split failed (exit {result.returncode}):\n"
            + '\n'.join(tail)
        )
    print(f"  Wrote bed.m4a + obj-01..{object_count:02d}.m4a")

    return object_count


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 adm_convert.py <input.wav> <output_dir> [name]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_dir = sys.argv[2]
    name = sys.argv[3] if len(sys.argv) > 3 else os.path.splitext(os.path.basename(input_path))[0]

    os.makedirs(output_dir, exist_ok=True)

    # Step 1: Probe audio
    print(f"Probing {input_path}...")
    info = probe_audio(input_path)
    print(f"  Channels: {info['channels']}, Duration: {info['duration']:.1f}s")

    # Step 2: Extract AXML
    print("Reading AXML metadata...")
    axml = read_axml_chunk(input_path)
    has_adm = axml is not None
    if has_adm:
        print(f"  AXML chunk found ({len(axml)} bytes)")
    else:
        print("  No AXML chunk — positions will be distributed in a circle")

    # Step 3: Extract stems
    print("Extracting audio stems...")
    object_count = extract_stems(input_path, output_dir, info['channels'])
    print(f"  Extracted bed + {object_count} objects")

    # Step 4: Parse positions
    fps = 30
    total_frames = int(info['duration'] * fps)
    positions = []

    if has_adm:
        print("Parsing ADM position data...")
        positions = parse_adm_positions(axml, info['duration'], fps)
        print(f"  Found positions for {len(positions)} objects")

    # Step 5: Generate manifest
    colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7",
              "#DDA0DD", "#98D8C8", "#F7DC6F", "#BB8FCE", "#85C1E9",
              "#F8C471", "#82E0AA", "#F1948A", "#AED6F1", "#D7BDE2",
              "#A3E4D7", "#FAD7A0", "#EDBB99", "#D5F5E3", "#FADBD8"]

    objects = []
    for i in range(object_count):
        obj = {
            "name": positions[i]['name'] if i < len(positions) else f"Object {i+1}",
            "file": f"obj-{i+1:02d}.m4a",
            "volume": 0.85,
            "color": colors[i % len(colors)],
            "static": False,
        }

        if i < len(positions):
            obj["x"] = positions[i]['x']
            obj["y"] = positions[i]['y']
            obj["z"] = positions[i]['z']
        else:
            # Distribute in circle
            angle = (i / object_count) * 2 * math.pi
            r = 3.0
            obj["x"] = [round(r * math.sin(angle), 4)] * total_frames
            obj["y"] = [0.0] * total_frames
            obj["z"] = [round(-r * math.cos(angle), 4)] * total_frames

        objects.append(obj)

    manifest = {
        "version": 1,
        "name": name,
        "duration": round(info['duration'], 3),
        "positionFPS": fps,
        "bed": {"file": "bed.m4a", "volume": 0.7},
        "objects": objects
    }

    manifest_path = os.path.join(output_dir, 'manifest.json')
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f"\nDone! Output: {output_dir}")
    print(f"  bed.m4a + {object_count} objects + manifest.json")
    if has_adm:
        print(f"  Full ADM position data included ({total_frames} frames at {fps}fps)")


if __name__ == '__main__':
    main()

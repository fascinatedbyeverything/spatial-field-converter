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
    """Encode the whole BWF master as ONE multichannel bed.m4a.

    Ambisonic field recordings have no real objects — they're a 4-channel
    sound field decoded into a 7.1.2 bed. Splitting the bed channels into
    fake mono "obj-NN.m4a" files (with all-zero position metadata) is the
    architectural bug that bloated R2 storage and tripled ffmpeg encode
    work. Bed-only is the right output for this source class.

    AAC supports up to 7.1 (8 channels) natively. For 10-channel 7.1.2
    inputs we drop the two top-front height channels (Ltf, Rtf) to stay
    in 7.1 AAC — that's the channel layout AirPods Pro/Max + system
    Spatial Audio engage HRTF binauralization on. True heights need
    AC-4 IMS, deferred.

    Returns 0 (no objects written) — kept as int for caller compatibility.
    """
    out_path = os.path.join(output_dir, 'bed.m4a')

    if channel_count <= 8:
        # ≤7.1 — pass through; ffmpeg infers the channel layout from the input.
        cmd = [
            'ffmpeg', '-nostdin', '-y', '-i', wav_path,
            '-c:a', 'aac', '-b:a', '384k', '-ar', '48000',
            out_path,
        ]
        print(f"  Encoding {channel_count}-ch bed.m4a (single ffmpeg pass)...")
    else:
        # 7.1.2 (10ch) or higher — fold to 7.1 (8ch), dropping heights.
        # Pan filter maps channels 0..7 explicitly; ffmpeg then tags the
        # output as 7.1 (back) which is what Apple's AAC decoder + Spatial
        # Audio expect.
        pan = ('pan=7.1|'
               'FL=c0|FR=c1|FC=c2|LFE=c3|'
               'BL=c4|BR=c5|SL=c6|SR=c7')
        cmd = [
            'ffmpeg', '-nostdin', '-y', '-i', wav_path,
            '-filter_complex', f'[0:a]{pan}[bed]',
            '-map', '[bed]',
            '-c:a', 'aac', '-b:a', '384k', '-ar', '48000',
            out_path,
        ]
        print(f"  Encoding 7.1 bed.m4a from {channel_count}-ch BWF "
              f"(dropping heights for AAC compat)...")

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        tail = (result.stderr or '').splitlines()[-20:]
        raise RuntimeError(
            f"ffmpeg bed encode failed (exit {result.returncode}):\n"
            + '\n'.join(tail)
        )
    print(f"  Wrote bed.m4a (no obj-NN files — ambisonic source has no objects)")

    return 0


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

    # Step 5: Generate manifest. Bed-only — ambisonic sources have no objects.
    # Note that object_count is now always 0 from extract_stems(); manifest
    # publishes an empty objects array so downstream consumers (FF / Library
    # / Composer) don't waste CPU spatialising fake objects.
    manifest = {
        "version": 1,
        "name": name,
        "duration": round(info['duration'], 3),
        "positionFPS": fps,
        "bed": {"file": "bed.m4a", "volume": 0.7},
        "objects": []
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

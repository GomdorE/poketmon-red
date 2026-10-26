"""Analyse a WAV rendered by `--audio-test` (pure Python, no numpy).

Usage: python tools/audio_check.py out.wav [frame_samples=549]

Prints runs of consecutive engine frames with a stable pitch (zero-crossing estimate
of the left channel) and their RMS, so note lengths and frequencies can be compared
with the original data (freq = 131072 / (2048 - register)).
"""
import struct
import sys
import wave


def main() -> None:
    path = sys.argv[1]
    fs = int(sys.argv[2]) if len(sys.argv) > 2 else 549
    with wave.open(path, "rb") as w:
        n = w.getnframes()
        raw = w.readframes(n)
        ch = w.getnchannels()
        rate = w.getframerate()
    samples = struct.unpack("<%dh" % (n * ch), raw)
    left = samples[0::ch]
    frames = len(left) // fs
    rows = []
    for f in range(frames):
        seg = left[f * fs:(f + 1) * fs]
        mean = sum(seg) / fs
        rms = (sum((s - mean) ** 2 for s in seg) / fs) ** 0.5
        crossings = 0
        prev = seg[0] - mean
        for s in seg[1:]:
            v = s - mean
            if (v >= 0) != (prev >= 0):
                crossings += 1
            prev = v
        freq = crossings / 2.0 * rate / fs
        rows.append((f, round(freq), rms))
    # merge runs
    runs = []
    for f, freq, rms in rows:
        silent = rms < 50
        key = 0 if silent else freq
        if runs and abs(runs[-1][2] - key) <= max(40, key * 0.03) and (runs[-1][2] == 0) == silent:
            runs[-1][1] += 1
            runs[-1][3] = max(runs[-1][3], rms)
        else:
            runs.append([f, 1, key, rms])
    print(f"{path}: {frames} frames, {rate} Hz")
    for start, length, freq, rms in runs:
        label = "silence" if freq == 0 else f"{freq:5d} Hz"
        print(f"  frame {start:4d} +{length:3d}  {label}  rms {rms:7.0f}")


if __name__ == "__main__":
    main()

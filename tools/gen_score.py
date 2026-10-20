"""Synthesizes Lantern's score: three seamless loops, rendered once and committed as OGG.

    python tools/gen_score.py

  music/calm.ogg   inside, all well: slow warm chords in D dorian, a sub drone, sparse glass bells
  music/tense.ogg  an alarm or a failure open: a low pulse under a dissonant cluster and wind
  music/void.ogg   outside: high beating partials, a deep hum, almost nothing

Everything is additive synthesis and filters in numpy; reverb is a circular convolution with
decaying noise, so the end of each loop rings into its start and the loops have no seam. Needs
ffmpeg on PATH for the OGG encoding. The game crossfades between them (scripts/music.gd).
"""

import shutil
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "music"
RATE = 32000
rng = np.random.default_rng(14)


def q(f: float) -> float:
    """Snap a frequency to whole cycles per 48 s, so every oscillator lines up at the loop point."""
    return round(f * 48.0) / 48.0


def hz(note: str) -> float:
    """'D3' -> frequency."""
    names = {"C": -9, "C#": -8, "Db": -8, "D": -7, "D#": -6, "Eb": -6, "E": -5, "F": -4, "F#": -3, "Gb": -3,
             "G": -2, "G#": -1, "Ab": -1, "A": 0, "A#": 1, "Bb": 1, "B": 2}
    return 440.0 * 2 ** ((names[note[:-1]] + 12 * (int(note[-1]) - 4)) / 12)


def saw(f: float, t: np.ndarray, harmonics: int = 14, phase: float = 0.0) -> np.ndarray:
    out = np.zeros_like(t)
    f = q(f)
    for k in range(1, harmonics + 1):
        if f * k > RATE / 2.2:
            break
        out += np.sin(2 * np.pi * f * k * t + phase * k) / k
    return out


def lowpass(x: np.ndarray, cutoff: np.ndarray | float) -> np.ndarray:
    """One-pole lowpass with a (possibly moving) cutoff; run twice for 12 dB/oct. Circular warm-up."""
    a = np.exp(-2 * np.pi * np.broadcast_to(cutoff, x.shape) / RATE)
    y = np.empty_like(x)
    for _ in range(2):
        prev = 0.0
        for start in (len(x) - RATE, 0):   # warm up on the tail so the loop has no click
            seg = slice(start, len(x)) if start else slice(0, len(x))
            xs, as_ = x[seg], a[seg]
            ys = np.empty_like(xs)
            for i in range(len(xs)):
                prev = as_[i] * prev + (1 - as_[i]) * xs[i]
                ys[i] = prev
            if start == 0:
                y[:] = ys
        x = y.copy()
    return y


def lowpass_fast(x: np.ndarray, cutoff: float) -> np.ndarray:
    """Fixed-cutoff lowpass by FFT (circular, so it loops)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    spec *= 1 / (1 + (f / cutoff) ** 4)
    return np.fft.irfft(spec, len(x))


def reverb(x: np.ndarray, seconds: float, mix: float, seed: int) -> np.ndarray:
    """Circular convolution with decaying, darkening noise: the tail wraps to the start."""
    n = len(x)
    r = np.random.default_rng(seed)
    t = np.arange(int(seconds * RATE)) / RATE
    ir = r.standard_normal(len(t)) * np.exp(-t * 6.9 / seconds)
    ir = lowpass_fast(np.pad(ir, (0, n - len(ir))), 5000.0)
    ir /= np.sqrt(np.sum(ir ** 2))
    wet = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ir), n)
    return x * (1 - mix) + wet * mix * 3.0


def envelope(t: np.ndarray, start: float, length: float, attack: float, loop: float) -> np.ndarray:
    """A raised-cosine swell from start for length seconds, wrapping around the loop."""
    u = ((t - start) % loop)
    rise = np.clip(u / attack, 0, 1)
    fall = np.clip((length - u) / attack, 0, 1)
    return (0.5 - 0.5 * np.cos(np.pi * np.minimum(rise, fall))) * (u < length)


def bell(t: np.ndarray, f: float, at: float, loop: float, decay: float) -> np.ndarray:
    u = (t - at) % loop
    env = np.exp(-u / decay) * np.clip(u / 0.004, 0, 1)
    partials = [(1.0, 1.0), (2.76, 0.4), (5.4, 0.18), (8.93, 0.08)]
    return env * sum(a * np.sin(2 * np.pi * f * m * u) * np.exp(-u * m * 0.15) for m, a in partials)


def stereo(left: np.ndarray, right: np.ndarray, peak_db: float) -> np.ndarray:
    st = np.stack([left, right], axis=1)
    st -= st.mean(axis=0)
    st *= 10 ** (peak_db / 20) / np.max(np.abs(st))
    return st


def calm(loop: float = 96.0) -> np.ndarray:
    t = np.arange(int(loop * RATE)) / RATE
    chords = [["D3", "A3", "C4", "F4", "E4"], ["Bb2", "F3", "A3", "D4", "C5"],
              ["F2", "C3", "A3", "E4", "G4"], ["C3", "G3", "D4", "E4", "B4"]]
    span = loop / len(chords)
    chans = []
    for side in (0, 1):
        pad = np.zeros_like(t)
        for i, chord in enumerate(chords):
            env = envelope(t, i * span - 4.0, span + 8.0, 7.0, loop)
            for j, note in enumerate(chord):
                f = hz(note)
                detune = 1 + (0.0035 if side else -0.0035) * (1 + j % 2)
                pad += env * (saw(f, t, 10, j * 1.3) + saw(f * detune, t, 10, j * 2.1 + side)) * 0.5 / (1 + j * 0.15)
        cutoff = 650 + 450 * (0.5 + 0.5 * np.sin(2 * np.pi * t / loop * 2 + side))
        pad = lowpass(pad, cutoff)
        drone = 0.9 * np.sin(2 * np.pi * q(hz("D1")) * t) + 0.35 * np.sin(2 * np.pi * q(hz("D2")) * t + 0.4)
        drone *= 0.6 + 0.4 * np.sin(2 * np.pi * t / loop * 3) ** 2
        chans.append(pad * 0.5 + drone * 0.35)
    bells = [np.zeros_like(t), np.zeros_like(t)]
    scale = ["D5", "F5", "G5", "A5", "C6", "D6", "A4"]
    for k in range(14):
        at = float(rng.uniform(0, loop))
        b = bell(t, hz(scale[rng.integers(len(scale))]), at, loop, float(rng.uniform(2.5, 5.0))) * float(rng.uniform(0.08, 0.18))
        pan = float(rng.uniform(0.2, 0.8))
        bells[0] += b * (1 - pan)
        bells[1] += b * pan
    left = reverb(chans[0] + bells[0], 4.5, 0.45, 1)
    right = reverb(chans[1] + bells[1], 4.5, 0.45, 2)
    return stereo(left, right, -4.0)


def tense(loop: float = 48.0) -> np.ndarray:
    t = np.arange(int(loop * RATE)) / RATE
    chans = []
    for side in (0, 1):
        beat = 1.2
        u = t % beat
        pulse = np.sin(2 * np.pi * 46 * u * (1 - 0.3 * u)) * np.exp(-u * 7) * 1.4
        u2 = (t - 0.28) % beat
        pulse += np.sin(2 * np.pi * 40 * u2) * np.exp(-u2 * 9) * 0.7
        cluster = np.zeros_like(t)
        for j, note in enumerate(["D3", "Eb3", "Ab3", "D4", "Eb4"]):
            f = hz(note) * (1 + (0.004 if side else -0.004))
            cluster += saw(f, t, 8, j + side) * (0.6 + 0.4 * np.sin(2 * np.pi * t / loop * (j + 1) + side))
        cluster = lowpass(cluster, 380 + 300 * (0.5 + 0.5 * np.sin(2 * np.pi * t / loop * 2)))
        wind = lowpass_fast(rng.standard_normal(len(t)), 900.0)
        wind *= 0.4 + 0.6 * (0.5 + 0.5 * np.sin(2 * np.pi * t / loop * 3 + side * 1.7))
        chans.append(pulse * 0.6 + cluster * 0.22 + wind * 0.25)
    left = reverb(chans[0], 2.5, 0.3, 3)
    right = reverb(chans[1], 2.5, 0.3, 4)
    return stereo(left, right, -4.0)


def void(loop: float = 96.0) -> np.ndarray:
    t = np.arange(int(loop * RATE)) / RATE
    chans = []
    for side in (0, 1):
        sh = np.zeros_like(t)
        for j, f in enumerate([1174.7, 1176.9, 1567.9, 1760.0, 2349.3]):
            amp = 0.5 + 0.5 * np.sin(2 * np.pi * t / loop * (j + 1) + side * 0.9 + j)
            sh += np.sin(2 * np.pi * q(f + side * 0.7) * t + j) * amp ** 3 / (1 + j * 0.4)
        hum = np.sin(2 * np.pi * q(hz("D1") * 0.5) * t) * 0.8 + np.sin(2 * np.pi * q(hz("A1") * 0.5) * t) * 0.3
        hum *= 0.5 + 0.5 * np.sin(2 * np.pi * t / loop) ** 2
        chans.append(sh * 0.12 + hum * 0.4)
    bells = [np.zeros_like(t), np.zeros_like(t)]
    for k in range(5):
        at = float(rng.uniform(0, loop))
        b = bell(t, hz(["D4", "A4", "E5"][k % 3]), at, loop, 7.0) * 0.12
        bells[k % 2] += b
        bells[1 - k % 2] += b * 0.4
    left = reverb(chans[0] + bells[0], 7.0, 0.6, 5)
    right = reverb(chans[1] + bells[1], 7.0, 0.6, 6)
    return stereo(left, right, -6.0)


def save(name: str, audio: np.ndarray) -> None:
    OUT.mkdir(exist_ok=True)
    wav_path = OUT / f"{name}.wav"
    pcm = (np.clip(audio, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(wav_path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "4",
                    str(OUT / f"{name}.ogg")], check=True)
    wav_path.unlink()
    print(f"{name:6} {len(audio) / RATE:5.1f} s -> {OUT / (name + '.ogg')} ({(OUT / (name + '.ogg')).stat().st_size // 1024} KB)")


def main() -> int:
    if shutil.which("ffmpeg") is None:
        print("ffmpeg is needed on PATH")
        return 1
    for name, make in (("calm", calm), ("tense", tense), ("void", void)):
        save(name, make())
    return 0


if __name__ == "__main__":
    sys.exit(main())

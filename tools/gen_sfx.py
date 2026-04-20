#!/usr/bin/env python3
"""
Procedural SFX generator — pure Python stdlib + ffmpeg for .ogg encoding.
Generates all new game sounds into assets/audio/.
"""

import wave, struct, math, random, os, subprocess, tempfile

SAMPLE_RATE = 44100

# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

def clamp(v, lo=-1.0, hi=1.0):
    return max(lo, min(hi, v))

def sine(t, freq):
    return math.sin(2 * math.pi * freq * t)

def noise():
    return random.uniform(-1.0, 1.0)

def adsr(t, dur, attack, decay, sustain_level, release):
    """Return envelope amplitude 0..1 at time t for a note of total length dur."""
    if t < attack:
        return t / attack if attack > 0 else 1.0
    t -= attack
    if t < decay:
        return 1.0 - (1.0 - sustain_level) * (t / decay) if decay > 0 else sustain_level
    t -= decay
    sustain_dur = dur - attack - decay - release
    if t < sustain_dur:
        return sustain_level
    t -= sustain_dur
    if t < release:
        return sustain_level * (1.0 - t / release) if release > 0 else 0.0
    return 0.0

def save_wav(path, samples):
    """Write list of floats [-1,1] as 16-bit mono WAV."""
    with wave.open(path, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        for s in samples:
            wf.writeframes(struct.pack('<h', int(clamp(s) * 32767)))

def to_ogg(wav_path, ogg_path):
    subprocess.run(
        ['ffmpeg', '-y', '-i', wav_path, '-ar', '44100', '-ac', '2',
         '-strict', 'experimental', '-c:a', 'vorbis', ogg_path],
        check=True, capture_output=True
    )

def gen(name, samples, out_dir):
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        tmp = f.name
    save_wav(tmp, samples)
    ogg = os.path.join(out_dir, name + '.ogg')
    to_ogg(tmp, ogg)
    os.unlink(tmp)
    print(f'  wrote {ogg}')

# ---------------------------------------------------------------------------
# Sound recipes
# ---------------------------------------------------------------------------

def make_explosion(dur=0.8):
    """Low boom + decaying noise rumble."""
    n = int(SAMPLE_RATE * dur)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-5.0 * t)
        boom = sine(t, 60.0) * 0.6 + sine(t, 90.0) * 0.3
        crunch = noise() * 0.5
        # low-pass-ish: average with previous sample smoothing handled by envelope shape
        s = (boom + crunch) * env
        samples.append(s * 0.85)
    return samples

def make_rocket_fire(dur=0.35):
    """Descending low-freq whoosh."""
    n = int(SAMPLE_RATE * dur)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = adsr(t, dur, 0.01, 0.05, 0.6, 0.15)
        freq = 220.0 * math.exp(-2.5 * t)   # sweep down from 220 Hz
        s = (sine(t, freq) * 0.5 + noise() * 0.35) * env
        samples.append(s * 0.9)
    return samples

def make_shotgun(dur=0.25):
    """Percussive noise burst — wide spread."""
    n = int(SAMPLE_RATE * dur)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-18.0 * t)
        body = noise() * 0.7 + sine(t, 120.0) * 0.15 + sine(t, 80.0) * 0.15
        s = body * env
        samples.append(s * 0.95)
    return samples

def make_sniper(dur=0.3):
    """High-pitched thin ping, quick ascend then tail-off."""
    n = int(SAMPLE_RATE * dur)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = adsr(t, dur, 0.002, 0.05, 0.3, 0.20)
        freq = 800.0 + 1200.0 * t / dur  # sweep up
        s = (sine(t, freq) * 0.6 + sine(t, freq * 1.5) * 0.25 + noise() * 0.1) * env
        samples.append(s * 0.8)
    return samples

def make_levelup(dur=0.65):
    """Ascending pentatonic arpeggio: C5 E5 G5 C6."""
    freqs = [523.25, 659.25, 784.0, 1046.5]
    n_total = int(SAMPLE_RATE * dur)
    note_dur = dur / len(freqs)
    samples = []
    for fi, freq in enumerate(freqs):
        n_note = int(SAMPLE_RATE * note_dur)
        for i in range(n_note):
            t = i / SAMPLE_RATE
            env = adsr(t, note_dur, 0.005, 0.05, 0.7, note_dur * 0.3)
            s = (sine(t, freq) * 0.5 + sine(t, freq * 2) * 0.25 + sine(t, freq * 0.5) * 0.2) * env
            samples.append(s * 0.8)
    # Pad/trim to exact length
    while len(samples) < n_total:
        samples.append(0.0)
    return samples[:n_total]

def make_xp_pickup(dur=0.18):
    """Short ascending bleep."""
    n = int(SAMPLE_RATE * dur)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = adsr(t, dur, 0.005, 0.02, 0.6, 0.10)
        freq = 600.0 + 400.0 * (t / dur)
        s = (sine(t, freq) * 0.6 + sine(t, freq * 2) * 0.2) * env
        samples.append(s * 0.75)
    return samples

def make_coin_pickup(dur=0.16):
    """Higher-pitched quick ping."""
    n = int(SAMPLE_RATE * dur)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = adsr(t, dur, 0.003, 0.02, 0.5, 0.10)
        freq = 1000.0 + 600.0 * (t / dur)
        s = (sine(t, freq) * 0.55 + sine(t, freq * 1.5) * 0.25) * env
        samples.append(s * 0.75)
    return samples

def make_player_death(dur=0.9):
    """Deep descending groan + noise."""
    n = int(SAMPLE_RATE * dur)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-3.5 * t)
        freq = 200.0 * math.exp(-2.0 * t)
        s = (sine(t, freq) * 0.5 + sine(t, freq * 0.5) * 0.3 + noise() * 0.25) * env
        samples.append(s * 0.9)
    return samples

def make_heal(dur=0.4):
    """Soft rising shimmer."""
    n = int(SAMPLE_RATE * dur)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = adsr(t, dur, 0.05, 0.1, 0.6, 0.15)
        freq = 440.0 + 220.0 * (t / dur)
        s = (sine(t, freq) * 0.4 + sine(t, freq * 1.5) * 0.3 + sine(t, freq * 2) * 0.15) * env
        samples.append(s * 0.65)
    return samples

def make_wave_start(dur=0.45):
    """Two rising alert tones."""
    n = int(SAMPLE_RATE * dur)
    half = n // 2
    samples = []
    for fi, (freq, start, end_i) in enumerate([(440.0, 0, half), (660.0, half, n)]):
        for i in range(start, end_i):
            t = (i - start) / SAMPLE_RATE
            local_dur = (end_i - start) / SAMPLE_RATE
            env = adsr(t, local_dur, 0.01, 0.05, 0.7, 0.1)
            s = (sine(t, freq) * 0.55 + sine(t, freq * 2) * 0.2) * env
            samples.append(s * 0.8)
    return samples

def make_wave_clear(dur=0.7):
    """Triumphant ascending fanfare: C5 G5 E6."""
    freqs = [523.25, 784.0, 1318.51]
    note_dur = dur / len(freqs)
    samples = []
    for freq in freqs:
        n_note = int(SAMPLE_RATE * note_dur)
        for i in range(n_note):
            t = i / SAMPLE_RATE
            env = adsr(t, note_dur, 0.005, 0.04, 0.75, note_dur * 0.35)
            s = (sine(t, freq) * 0.5 + sine(t, freq * 2) * 0.3 + sine(t, freq * 3) * 0.1) * env
            samples.append(s * 0.85)
    return samples

def make_pause(dur=0.15):
    """Clean single click/blip."""
    n = int(SAMPLE_RATE * dur)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = adsr(t, dur, 0.003, 0.03, 0.4, 0.08)
        s = (sine(t, 880.0) * 0.6 + sine(t, 440.0) * 0.2) * env
        samples.append(s * 0.7)
    return samples

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(script_dir, '..', 'assets', 'audio')
    os.makedirs(out_dir, exist_ok=True)

    sounds = [
        ('sfx_explosion',    make_explosion()),
        ('sfx_rocket_fire',  make_rocket_fire()),
        ('sfx_shotgun',      make_shotgun()),
        ('sfx_sniper',       make_sniper()),
        ('sfx_levelup',      make_levelup()),
        ('sfx_xp_pickup',    make_xp_pickup()),
        ('sfx_coin_pickup',  make_coin_pickup()),
        ('sfx_player_death', make_player_death()),
        ('sfx_heal',         make_heal()),
        ('sfx_wave_start',   make_wave_start()),
        ('sfx_wave_clear',   make_wave_clear()),
        ('sfx_pause',        make_pause()),
    ]

    print(f'Generating {len(sounds)} sounds -> {os.path.abspath(out_dir)}')
    for name, samples in sounds:
        gen(name, samples, out_dir)
    print('Done.')

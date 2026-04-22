#!/usr/bin/env python3
"""
Procedural music generator - pure Python stdlib + ffmpeg.
Generates loopable background music for menu and in-game use.

Usage: python3 tools/gen_music.py
Writes to assets/audio/music_menu.ogg and assets/audio/music_game.ogg
"""

import wave, struct, math, random, os, subprocess, tempfile

SR  = 22050
TAU = 2.0 * math.pi

# ---------------------------------------------------------------------------
# Note frequencies  (A minor pentatonic + scale)
# ---------------------------------------------------------------------------
NOTES = {
    'E1': 41.20,  'G1': 49.00,  'A1': 55.00,
    'E2': 82.41,  'G2': 98.00,  'A2': 110.00,
    'C3': 130.81, 'D3': 146.83, 'E3': 164.81, 'G3': 196.00, 'A3': 220.00,
    'C4': 261.63, 'D4': 293.66, 'E4': 329.63, 'G4': 392.00, 'A4': 440.00,
    'C5': 523.25, 'D5': 587.33, 'E5': 659.25, 'G5': 784.00, 'A5': 880.00,
    'B3': 246.94,
}

# ---------------------------------------------------------------------------
# Envelope helper (scalar, fast for inline use)
# ---------------------------------------------------------------------------

def _env(i, n, SR, attack, decay, sustain, release):
    t = i / SR
    dur = n / SR
    if t < attack:
        return t / attack if attack > 0 else 1.0
    t -= attack
    if t < decay:
        return 1.0 - (1.0 - sustain) * (t / decay) if decay > 0 else sustain
    t -= decay
    s_dur = dur - attack - decay - release
    if t < s_dur:
        return sustain
    t -= s_dur
    if t < release:
        return sustain * (1.0 - t / release) if release > 0 else 0.0
    return 0.0

# ---------------------------------------------------------------------------
# Synth voices  (return list of float, amplitude ~-1..1)
# ---------------------------------------------------------------------------

def synth_pad(freq, dur, attack=0.3, decay=0.4, sustain=0.7, release=0.5,
              lfo_rate=0.4, lfo_depth=0.04):
    n = int(SR * dur)
    f1, f2, f3 = freq, freq * 1.005, freq * 0.995
    lfo_k = TAU * lfo_rate / SR
    return [
        (math.sin(TAU * f1 * i / SR) * 0.5
         + math.sin(TAU * f2 * i / SR) * 0.3
         + math.sin(TAU * f3 * i / SR) * 0.2)
        * _env(i, n, SR, attack, decay, sustain, release)
        * (1.0 + lfo_depth * math.sin(lfo_k * i))
        for i in range(n)
    ]

def synth_organ(freq, dur, attack=0.01, decay=0.05, sustain=0.7, release=0.15):
    n = int(SR * dur)
    k = TAU * freq / SR
    return [
        (math.sin(k * i) * 0.55
         + math.sin(k * 2 * i) * 0.28
         + math.sin(k * 3 * i) * 0.12
         + math.sin(k * 4 * i) * 0.05)
        * _env(i, n, SR, attack, decay, sustain, release)
        for i in range(n)
    ]

def synth_bass(freq, dur, attack=0.005, decay=0.08, sustain=0.65, release=0.1):
    n = int(SR * dur)
    k = TAU * freq / SR
    return [
        (math.sin(k * i) * 0.60
         + math.sin(k * 0.5 * i) * 0.25
         + math.sin(k * 2.0 * i) * 0.15)
        * _env(i, n, SR, attack, decay, sustain, release)
        for i in range(n)
    ]

def synth_lead(freq, dur, attack=0.01, decay=0.06, sustain=0.65, release=0.12,
               vibrato=0.003):
    n = int(SR * dur)
    vib_k = TAU * 5.5 / SR
    k_base = TAU * freq / SR
    samples = []
    phase = 0.0
    for i in range(n):
        vib = 1.0 + vibrato * math.sin(vib_k * i)
        phase += k_base * vib
        env = _env(i, n, SR, attack, decay, sustain, release)
        s = (math.sin(phase) * 0.50
             + math.sin(phase * 2) * 0.30
             + math.sin(phase * 3) * 0.12
             + math.sin(phase * 0.5) * 0.08)
        samples.append(s * env)
    return samples

def synth_kick():
    dur = 0.28
    n = int(SR * dur)
    out = []
    prev = 0.0
    for i in range(n):
        t = i / SR
        env  = math.exp(-14.0 * t)
        tenv = math.exp(-60.0 * t)
        freq = 80.0 * math.exp(-20.0 * t)
        raw = math.sin(TAU * freq * t) * 0.85 + random.uniform(-1, 1) * 0.2 * tenv
        s = raw * env
        # one-pole lowpass
        y = prev + 0.4 * (s - prev)
        out.append(y)
        prev = y
    return out

def synth_snare():
    dur = 0.18
    n = int(SR * dur)
    return [
        (random.uniform(-1, 1) * 0.7
         + math.sin(TAU * 220.0 * i / SR) * 0.3 * math.exp(-35.0 * i / SR))
        * math.exp(-22.0 * i / SR)
        for i in range(n)
    ]

def synth_hihat(vol=0.18, dur=0.045):
    n = int(SR * dur)
    out = []
    prev = 0.0
    for i in range(n):
        raw = random.uniform(-1, 1) * math.exp(-50.0 * i / SR) * vol
        y = prev + 0.6 * (raw - prev)
        out.append(y)
        prev = y
    return out

# ---------------------------------------------------------------------------
# Buffer helpers
# ---------------------------------------------------------------------------

def make_buf(dur_sec):
    return [0.0] * int(SR * dur_sec)

def mix_at(buf, samples, start_sec, vol=1.0):
    start = int(start_sec * SR)
    end   = min(start + len(samples), len(buf))
    n     = end - start
    for i in range(n):
        buf[start + i] += samples[i] * vol

def normalize_buf(buf, peak=0.82):
    mx = max(abs(s) for s in buf)
    if mx > 1e-9:
        k = peak / mx
        for i in range(len(buf)):
            buf[i] *= k
    return buf

def fade_edges(buf, fade_sec=0.07):
    n = int(fade_sec * SR)
    for i in range(n):
        t = i / n
        buf[i] *= t
        buf[-(i + 1)] *= t
    return buf

# ---------------------------------------------------------------------------
# WAV / OGG I/O
# ---------------------------------------------------------------------------

def save_wav(path, buf):
    with wave.open(path, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        data = struct.pack(f'<{len(buf)}h',
                           *[int(max(-32767, min(32767, s * 32767)) ) for s in buf])
        wf.writeframes(data)

def to_ogg(wav_path, ogg_path):
    subprocess.run(
        ['ffmpeg', '-y', '-i', wav_path, '-ar', '44100', '-ac', '2',
         '-strict', 'experimental', '-c:a', 'vorbis', ogg_path],
        check=True, capture_output=True
    )

def gen(name, buf, out_dir):
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        tmp = f.name
    save_wav(tmp, buf)
    ogg = os.path.join(out_dir, name + '.ogg')
    to_ogg(tmp, ogg)
    os.unlink(tmp)
    print(f'  wrote {ogg}')

# ---------------------------------------------------------------------------
# MENU MUSIC  -- ambient space, 72 BPM, 18 bars (~60 s)
# ---------------------------------------------------------------------------

def make_menu_music():
    BPM   = 72
    beat  = 60.0 / BPM
    bar   = beat * 4
    n_bars = 18

    total_dur = bar * n_bars
    buf = make_buf(total_dur)

    sub_seq = ['A1','A1','E1','E1','G1','G1','A1','A1',
               'A1','A1','E1','E1','G1','G1','A1','A1',
               'A1','A1']
    for b in range(n_bars):
        mix_at(buf, synth_bass(NOTES[sub_seq[b]], bar * 0.96,
                               attack=0.12, decay=0.2, sustain=0.7, release=0.4),
               b * bar, vol=0.52)

    voicings = [
        ['A2','E3','A3','C4'],
        ['E2','G3','B3','E3'],
        ['G2','D3','G3','B3'],
        ['A2','E3','A3','C4'],
        ['A2','E3','A3','C4'],
    ]
    for ci, chord in enumerate(voicings):
        sb = ci * 4
        if sb >= n_bars:
            break
        rem  = min(4, n_bars - sb)
        cdur = bar * rem * 0.93
        for note in chord:
            mix_at(buf, synth_pad(NOTES[note], cdur,
                                  attack=0.55, decay=0.5, sustain=0.72, release=0.8),
                   sb * bar, vol=0.28)

    arp_seq = ['A3','C4','E4','G4','A4','G4','E4','C4']
    hb = beat / 2.0
    n_steps = int(total_dur / hb)
    for step in range(n_steps):
        t0 = step * hb
        if t0 + hb > total_dur:
            break
        mix_at(buf, synth_organ(NOTES[arp_seq[step % 8]], hb * 0.65,
                                attack=0.006, decay=0.04, sustain=0.55, release=0.08),
               t0, vol=0.22)

    melody = ['A4','C5','E5','C5','A4','G4','E4','A4','C5','A4']
    for i, note in enumerate(melody):
        sb = i * 2
        if sb >= n_bars:
            break
        mix_at(buf, synth_lead(NOTES[note], beat * 1.7,
                               attack=0.025, decay=0.1, sustain=0.6, release=0.35,
                               vibrato=0.004),
               sb * bar + beat, vol=0.32)

    normalize_buf(buf)
    fade_edges(buf)
    return buf

# ---------------------------------------------------------------------------
# GAME MUSIC  -- driving electronic, 138 BPM, 32 bars (~55 s)
# ---------------------------------------------------------------------------

def make_game_music():
    BPM      = 138
    beat     = 60.0 / BPM
    bar      = beat * 4
    eighth   = beat / 2.0
    sixteenth = beat / 4.0
    n_bars   = 32

    total_dur = bar * n_bars
    buf = make_buf(total_dur)

    kick_s  = synth_kick()
    snare_s = synth_snare()

    for b in range(n_bars):
        bt = b * bar
        mix_at(buf, kick_s,  bt)
        mix_at(buf, snare_s, bt + beat)
        mix_at(buf, kick_s,  bt + beat * 2)
        mix_at(buf, snare_s, bt + beat * 3)
        for s16 in range(16):
            hv = 0.10 if (s16 % 4 == 0) else 0.17
            mix_at(buf, synth_hihat(vol=hv), bt + s16 * sixteenth)

    bass_pat = [('A2',1.0),('A2',0.7),('G2',1.0),('A2',0.8),
                ('A2',1.0),('E2',1.0),('G2',0.8),('A2',1.0),
                ('A2',1.0),('A2',0.7),('G2',1.0),('C3',0.9),
                ('A2',1.0),('E2',1.0),('A2',0.8),('G2',0.9)]
    total_8ths = int(total_dur / eighth)
    for step in range(total_8ths):
        t0 = step * eighth
        if t0 + eighth > total_dur:
            break
        note, vel = bass_pat[step % len(bass_pat)]
        mix_at(buf, synth_bass(NOTES[note], eighth * 0.82,
                               attack=0.005, decay=0.06, sustain=0.6, release=0.08),
               t0, vol=0.55 * vel)

    arp_pat = ['A4','C5','E5','A5','G5','E5','C5','A4',
               'A4','E5','C5','A4','G4','A4','E4','G4']
    arp_start = 2 * bar
    total_16ths = int((total_dur - arp_start) / sixteenth)
    for step in range(total_16ths):
        t0 = arp_start + step * sixteenth
        if t0 + sixteenth > total_dur:
            break
        mix_at(buf, synth_organ(NOTES[arp_pat[step % len(arp_pat)]], sixteenth * 0.70,
                                attack=0.004, decay=0.03, sustain=0.45, release=0.06),
               t0, vol=0.20)

    phrase = [
        ('A4', 1.0), ('C5', 0.5), ('D5', 0.5),
        ('E5', 1.0), ('A4', 1.0),
        ('G4', 0.5), ('E4', 0.5), ('A4', 2.0),
        ('C5', 1.0), ('E5', 0.5), ('G5', 0.5),
        ('A5', 1.0), ('G5', 1.0),
        ('E5', 0.5), ('C5', 0.5), ('A4', 2.0),
    ]
    for pb in [4, 12, 20, 28]:
        if pb >= n_bars:
            break
        cursor = pb * bar
        for note, dur_beats in phrase:
            if cursor + beat > total_dur:
                break
            mix_at(buf, synth_lead(NOTES[note], dur_beats * beat * 0.88,
                                   attack=0.01, decay=0.05, sustain=0.65, release=0.12,
                                   vibrato=0.002),
                   cursor, vol=0.30)
            cursor += dur_beats * beat

    normalize_buf(buf)
    fade_edges(buf)
    return buf

# ---------------------------------------------------------------------------
# BETWEEN-WAVES MUSIC  -- warm/triumphant lounge, 90 BPM, 20 bars (~53 s)
# ---------------------------------------------------------------------------

def make_betweenwaves_music():
    BPM    = 90
    beat   = 60.0 / BPM
    bar    = beat * 4
    eighth = beat / 2.0
    n_bars = 20

    total_dur = bar * n_bars
    buf = make_buf(total_dur)

    # Walking bass line -- C major / A minor alternating
    bass_pat = [
        ('A2', 1.0), ('C3', 0.8), ('E2', 0.9), ('G2', 0.8),
        ('A2', 1.0), ('C3', 0.8), ('G2', 0.9), ('E2', 0.8),
        ('C3', 1.0), ('E2', 0.8), ('G2', 0.9), ('A2', 0.8),
        ('A2', 1.0), ('E2', 0.8), ('C3', 0.9), ('G2', 0.8),
    ]
    total_8ths = int(total_dur / eighth)
    for step in range(total_8ths):
        t0 = step * eighth
        if t0 + eighth > total_dur:
            break
        note, vel = bass_pat[step % len(bass_pat)]
        mix_at(buf, synth_bass(NOTES[note], eighth * 0.78,
                               attack=0.008, decay=0.07, sustain=0.60, release=0.10),
               t0, vol=0.45 * vel)

    # Slow pad chords -- warm major/minor voicings held for 2 bars each
    chord_seq = [
        ['A2', 'C3', 'E3', 'A3'],   # Am
        ['G2', 'B3', 'D3', 'G3'],   # G
        ['C3', 'E3', 'G3', 'C4'],   # C
        ['E2', 'G3', 'B3', 'E3'],   # Em
        ['A2', 'C3', 'E3', 'A3'],   # Am
        ['G2', 'D3', 'G3', 'B3'],   # G
        ['C3', 'E3', 'G3', 'C4'],   # C
        ['A2', 'E3', 'A3', 'C4'],   # Am
        ['A2', 'C3', 'E3', 'A3'],   # Am
        ['G2', 'B3', 'D3', 'G3'],   # G
    ]
    for ci, chord in enumerate(chord_seq):
        sb = ci * 2
        if sb >= n_bars:
            break
        cdur = bar * 2 * 0.92
        for note in chord:
            if note not in NOTES:
                continue
            mix_at(buf, synth_pad(NOTES[note], cdur,
                                  attack=0.4, decay=0.4, sustain=0.72, release=0.7),
                   sb * bar, vol=0.24)

    # Light arpeggio (organ, eighth notes) starting bar 1
    arp_seq = ['A3', 'E4', 'C4', 'E4', 'A3', 'G4', 'E4', 'C4',
               'C4', 'E4', 'G4', 'E4', 'C4', 'A3', 'E4', 'G4']
    arp_start = bar
    total_arp_8ths = int((total_dur - arp_start) / eighth)
    for step in range(total_arp_8ths):
        t0 = arp_start + step * eighth
        if t0 + eighth > total_dur:
            break
        mix_at(buf, synth_organ(NOTES[arp_seq[step % len(arp_seq)]], eighth * 0.62,
                                attack=0.005, decay=0.04, sustain=0.48, release=0.08),
               t0, vol=0.18)

    # Gentle lead melody entering at bar 4, repeating every 8 bars
    melody = [
        ('A4', 1.5), ('C5', 0.5), ('E5', 1.0), ('C5', 1.0),
        ('A4', 1.0), ('G4', 0.5), ('E4', 0.5), ('A4', 2.0),
        ('C5', 1.0), ('E5', 0.5), ('G5', 0.5), ('E5', 1.0), ('C5', 1.0),
        ('A4', 0.5), ('G4', 0.5), ('A4', 2.0),
    ]
    for pb in [4, 12]:
        if pb >= n_bars:
            break
        cursor = pb * bar
        for note, dur_beats in melody:
            if cursor + beat > total_dur:
                break
            mix_at(buf, synth_lead(NOTES[note], dur_beats * beat * 0.85,
                                   attack=0.025, decay=0.08, sustain=0.62, release=0.30,
                                   vibrato=0.005),
                   cursor, vol=0.28)
            cursor += dur_beats * beat

    normalize_buf(buf)
    fade_edges(buf)
    return buf

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    random.seed(42)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(script_dir, '..', 'assets', 'audio')
    os.makedirs(out_dir, exist_ok=True)

    tracks = [
        ('music_menu', make_menu_music),
        ('music_game', make_game_music),
        ('music_betweenwaves', make_betweenwaves_music),
    ]

    print(f'Generating {len(tracks)} music tracks -> {os.path.abspath(out_dir)}')
    for name, fn in tracks:
        print(f'  building {name}...')
        buf = fn()
        gen(name, buf, out_dir)
    print('Done.')

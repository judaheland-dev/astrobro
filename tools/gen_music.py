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
    'E2': 82.41,  'G2': 98.00,  'A2': 110.00,  'B2': 123.47,
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

def synth_saw(freq, dur, attack=0.005, decay=0.08, sustain=0.7, release=0.12,
              detune=0.008):
    """Aggressive detuned sawtooth — core of techy/industrial leads."""
    n = int(SR * dur)
    k1 = TAU * freq / SR
    k2 = TAU * (freq * (1.0 + detune)) / SR
    k3 = TAU * (freq * (1.0 - detune * 0.7)) / SR
    out = []
    p1 = p2 = p3 = 0.0
    for i in range(n):
        p1 = (p1 + k1) % TAU
        p2 = (p2 + k2) % TAU
        p3 = (p3 + k3) % TAU
        # sawtooth via phase accumulator  (1 - phase/pi  maps 0..2pi -> 1..-1)
        s = ((1.0 - p1 / math.pi) * 0.5
           + (1.0 - p2 / math.pi) * 0.3
           + (1.0 - p3 / math.pi) * 0.2)
        out.append(s * _env(i, n, SR, attack, decay, sustain, release))
    return out

def synth_fm(freq, dur, mod_ratio=3.5, mod_idx=4.5,
             attack=0.004, decay=0.07, sustain=0.55, release=0.10):
    """FM synth with harsh, metallic timbre. mod_ratio >2 = tech/industrial feel."""
    n = int(SR * dur)
    k_car = TAU * freq / SR
    k_mod = TAU * freq * mod_ratio / SR
    out = []
    car_phase = mod_phase = 0.0
    for i in range(n):
        env = _env(i, n, SR, attack, decay, sustain, release)
        mod_phase += k_mod
        car_phase += k_car + mod_idx * math.sin(mod_phase)
        out.append(math.sin(car_phase) * env)
    return out

def synth_stab(freq, dur, attack=0.003, decay=0.12, sustain=0.0, release=0.04):
    """Short punchy synth stab — sawtooth + slight noise grit, no sustain."""
    n = int(SR * dur)
    k = TAU * freq / SR
    out = []
    phase = 0.0
    for i in range(n):
        phase = (phase + k) % TAU
        saw = 1.0 - phase / math.pi   # sawtooth
        sqr = 1.0 if phase < math.pi else -1.0  # square
        grit = random.uniform(-1, 1) * 0.06
        s = saw * 0.55 + sqr * 0.35 + grit
        out.append(s * _env(i, n, SR, attack, decay, sustain, release))
    return out

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

def to_ogg_soundfile(buf, ogg_path):
    import soundfile as sf
    import numpy as np
    data = np.array(buf, dtype='float32')
    # soundfile needs stereo for Godot compatibility
    stereo = np.stack([data, data], axis=1)
    sf.write(ogg_path, stereo, SR, format='OGG', subtype='VORBIS')

def gen(name, buf, out_dir):
    ogg = os.path.join(out_dir, name + '.ogg')
    # Try ffmpeg first, fall back to soundfile
    try:
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
            tmp = f.name
        save_wav(tmp, buf)
        to_ogg(tmp, ogg)
        os.unlink(tmp)
    except (FileNotFoundError, subprocess.CalledProcessError):
        to_ogg_soundfile(buf, ogg)
    print(f'  wrote {ogg}')

# ---------------------------------------------------------------------------
# MENU MUSIC  -- dark ambient space, 68 BPM, 24 bars (~84 s)
#               Builds: sub-bass drone -> pad chords -> bass -> kick ->
#               snare+hats -> FM hits -> pad melody
# ---------------------------------------------------------------------------

def make_menu_music():
    BPM    = 68
    beat   = 60.0 / BPM
    bar    = beat * 4
    eighth = beat / 2.0
    n_bars = 24

    total_dur = bar * n_bars
    buf = make_buf(total_dur)

    # --- Sub-bass pad drone: present throughout, slow swell ---
    mix_at(buf, synth_pad(NOTES['A1'], total_dur * 0.98,
                          attack=3.0, decay=2.0, sustain=0.60, release=4.0,
                          lfo_rate=0.06, lfo_depth=0.018),
           0.0, vol=0.30)

    # --- Dark pad chords: enter at bar 2, 4-bar hold, volume ramps up ---
    # Am7 / Gm / Em7 voicings -- hollow minor 7ths for ominous depth
    pad_chords = [
        ['A2', 'E3', 'G3', 'A3'],   # Am7
        ['G2', 'D3', 'G3'],          # Gm (no 3rd = hollow)
        ['A2', 'C3', 'E3', 'G3'],   # Am7
        ['E2', 'B2', 'D3', 'G3'],   # Em7 (tritone G adds tension)
        ['A2', 'E3', 'G3', 'A3'],   # Am7
        ['G2', 'D3', 'G3'],          # Gm
    ]
    for ci, chord in enumerate(pad_chords):
        sb = 2 + ci * 4
        if sb >= n_bars:
            break
        cdur = min(bar * 4 * 0.97, total_dur - sb * bar)
        vol_factor = min(1.0, 0.45 + ci * 0.11)
        for note in chord:
            if note not in NOTES:
                continue
            mix_at(buf, synth_pad(NOTES[note], cdur,
                                  attack=1.0, decay=0.6, sustain=0.68, release=1.3,
                                  lfo_rate=0.11, lfo_depth=0.016),
                   sb * bar, vol=0.29 * vol_factor)

    # --- Sparse bass: enters bar 6, slow held notes ---
    bass_seq = [
        ('A2', 2.0), ('E2', 2.0), ('G2', 2.0), ('A2', 2.0),
        ('C3', 2.0), ('G2', 2.0), ('A2', 2.0), ('E2', 2.0),
        ('A2', 2.0), ('G2', 2.0),
    ]
    cursor = 6 * bar
    for note, dur_beats in bass_seq:
        if cursor >= total_dur:
            break
        mix_at(buf, synth_bass(NOTES[note], dur_beats * beat * 0.88,
                               attack=0.14, decay=0.22, sustain=0.70, release=0.45),
               cursor, vol=0.48)
        cursor += dur_beats * beat

    # --- Kick: sparse pulse, enters bar 10 ---
    kick_s  = synth_kick()
    snare_s = synth_snare()
    for b in range(10, n_bars):
        bt = b * bar
        mix_at(buf, kick_s, bt, vol=0.70)
        if b >= 14:
            mix_at(buf, kick_s, bt + beat * 2, vol=0.55)

    # --- Snare (half-time on beat 3) + hi-hats: enter bar 14 ---
    for b in range(14, n_bars):
        bt = b * bar
        mix_at(buf, snare_s, bt + beat * 2, vol=0.60)
        if b >= 18:
            mix_at(buf, snare_s, bt + beat,     vol=0.45)
            mix_at(buf, snare_s, bt + beat * 3, vol=0.50)
            for s8 in range(8):
                hv = 0.07 if s8 % 2 == 0 else 0.04
                mix_at(buf, synth_hihat(vol=hv, dur=0.06),
                       bt + s8 * eighth)

    # --- Sparse FM hits: enter bar 14, dark metallic texture ---
    fm_hits = ['A3', 'G3', 'E3', 'A3', 'C4', 'G3', 'E3', 'A3']
    for b in range(14, n_bars):
        bt = b * bar
        for bi, beat_off in enumerate([0.0, 2.0, 2.5]):
            note = fm_hits[(b * 3 + bi) % len(fm_hits)]
            mix_at(buf, synth_fm(NOTES[note], beat * 0.44,
                                 mod_ratio=2.8, mod_idx=3.2,
                                 attack=0.012, decay=0.10,
                                 sustain=0.0, release=0.06),
                   bt + beat_off * beat, vol=0.14)

    # --- Pad melody: enters bar 18, slow and atmospheric (no bright lead) ---
    melody = [
        ('A4', 2.0), ('G4', 1.0), ('E4', 1.0),
        ('A4', 1.5), ('C5', 0.5), ('G4', 2.0),
        ('E4', 1.5), ('A4', 0.5), ('C5', 2.0),
        ('G4', 2.0), ('A4', 2.0),
    ]
    cursor = 18 * bar
    for note, dur_beats in melody:
        if cursor >= total_dur:
            break
        mix_at(buf, synth_pad(NOTES[note], dur_beats * beat * 0.90,
                              attack=0.18, decay=0.22, sustain=0.65, release=0.55,
                              lfo_rate=0.28, lfo_depth=0.022),
               cursor, vol=0.27)
        cursor += dur_beats * beat

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
# GAME HARD MUSIC  -- mysterious -> dark synth -> active industrial
#                     120 BPM, 32 bars (~64 s), 3 clear sections:
#                     S1 bars  0-7  : sparse, eerie, no drums
#                     S2 bars  8-19 : dark synth pulse, brooding saw melody
#                     S3 bars 20-31 : full aggressive drums, driving bass
# ---------------------------------------------------------------------------

def make_game_hard_music():
    BPM       = 120
    beat      = 60.0 / BPM
    bar       = beat * 4
    eighth    = beat / 2.0
    sixteenth = beat / 4.0
    n_bars    = 32

    total_dur = bar * n_bars
    buf = make_buf(total_dur)

    kick_s  = synth_kick()
    snare_s = synth_snare()

    # =====================================================================
    # SECTION 1 – MYSTERIOUS  (bars 0-7, ~16 s)
    # No drums. Sub-bass drone, slow dissonant pads, eerie FM bleeps.
    # =====================================================================

    # Sub-bass drone: present throughout, barely audible at first
    mix_at(buf, synth_pad(NOTES['A1'], total_dur * 0.99,
                          attack=3.5, decay=1.5, sustain=0.45, release=4.0,
                          lfo_rate=0.04, lfo_depth=0.010),
           0.0, vol=0.20)

    # Slow, dissonant pads: Am + B natural (major 7th = eerie), Em7
    s1_pad_chords = [
        ['A2', 'E3', 'B3'],   # Am + maj7 — unsettling open voicing
        ['E2', 'B2', 'G3'],   # Em7  — somber and hollow
    ]
    for ci, chord in enumerate(s1_pad_chords):
        t0 = ci * 4 * bar
        cdur = bar * 4 * 0.95
        for note in chord:
            if note not in NOTES:
                continue
            mix_at(buf, synth_pad(NOTES[note], cdur,
                                  attack=2.2, decay=0.9, sustain=0.52, release=2.8,
                                  lfo_rate=0.06, lfo_depth=0.013),
                   t0, vol=0.23)

    # Eerie FM bleeps: sparse, high-register, alien timbre (high mod_idx)
    eerie_seq = [
        (0.6,  'A4',  5.0, 8.0),
        (3.2,  'E5',  4.5, 9.5),
        (6.5,  'B3',  6.0, 10.0),
        (9.8,  'G4',  5.5, 8.5),
        (12.3, 'A4',  4.0,  7.0),
        (15.7, 'E4',  5.0,  9.0),
        (19.1, 'D4',  6.0,  8.0),
        (22.5, 'G4',  5.0,  7.5),
    ]
    for t_beats, note, mr, mi in eerie_seq:
        t0 = t_beats * beat
        if t0 >= 8 * bar:
            break
        mix_at(buf, synth_fm(NOTES[note], beat * 0.22,
                             mod_ratio=mr, mod_idx=mi,
                             attack=0.030, decay=0.20, sustain=0.0, release=0.14),
               t0, vol=0.09)

    # Sparse bass "heartbeat" — only 4 hits, like a distant pulse
    for tb in [4.0, 9.0, 13.0, 15.5]:
        t0 = tb * beat
        if t0 >= 8 * bar:
            break
        mix_at(buf, synth_bass(NOTES['A1'], beat * 0.65,
                               attack=0.07, decay=0.28, sustain=0.30, release=0.65),
               t0, vol=0.38)

    # =====================================================================
    # SECTION 2 – DARK SYNTH  (bars 8-19, ~24 s)
    # Pulse kick enters, dark heavy pads, brooding slow saw melody.
    # Snare + hi-hats join at bar 14.
    # =====================================================================

    # Kick: 4-on-floor from bar 8, builds in intensity toward bar 14
    for b in range(8, 14):
        bt = b * bar
        ramp = 0.65 + (b - 8) * 0.06   # 0.65 -> 0.95
        for bi in range(4):
            mix_at(buf, kick_s, bt + bi * beat, vol=ramp)

    # Full groove from bar 14: kick + snare + hi-hats
    for b in range(14, 20):
        bt = b * bar
        for bi in range(4):
            mix_at(buf, kick_s, bt + bi * beat, vol=1.0)
        mix_at(buf, snare_s, bt + beat,     vol=0.85)
        mix_at(buf, snare_s, bt + beat * 3, vol=0.85)
        for s8 in range(8):
            hv = 0.11 if s8 % 2 == 0 else 0.06
            mix_at(buf, synth_hihat(vol=hv, dur=0.055), bt + s8 * eighth)

    # Dark pads: heavier, dissonant, slow attack
    s2_chords = [
        ['A2', 'E3', 'G3'],          # Am7
        ['G2', 'D3', 'G3'],          # Gm bare 5th
        ['A2', 'E3', 'G3', 'B3'],   # Am7 + maj7 — tense
        ['E2', 'B2', 'G3'],          # Em7 tritone
        ['A2', 'G3'],                 # bare Am7 shell
        ['G2', 'D3'],                 # bare G5
    ]
    for ci in range(6):
        t0 = 8 * bar + ci * 2 * bar
        if t0 >= 20 * bar:
            break
        chord = s2_chords[ci % len(s2_chords)]
        cdur = bar * 2 * 0.95
        for note in chord:
            if note not in NOTES:
                continue
            mix_at(buf, synth_pad(NOTES[note], cdur,
                                  attack=0.8, decay=0.5, sustain=0.60, release=1.1,
                                  lfo_rate=0.12, lfo_depth=0.018),
                   t0, vol=0.22)

    # Dark synth bass: beat-note pattern, descending feel
    bass_s2 = [
        ('A2', 1.0), ('G2', 0.9), ('A2', 1.0), ('E2', 0.9),
        ('A2', 1.0), ('G2', 0.9), ('D3', 1.0), ('G2', 0.9),
        ('A2', 1.0), ('G2', 0.9), ('E2', 1.0), ('A2', 0.9),
        ('E2', 1.0), ('G2', 0.9), ('A2', 1.0), ('G2', 0.9),
    ]
    s2_beats = int((20 * bar - 8 * bar) / beat)
    for step in range(s2_beats):
        t0 = 8 * bar + step * beat
        if t0 >= 20 * bar:
            break
        note, vel = bass_s2[step % len(bass_s2)]
        mix_at(buf, synth_bass(NOTES[note], beat * 0.83,
                               attack=0.008, decay=0.10, sustain=0.68, release=0.12),
               t0, vol=0.52 * vel)

    # Brooding saw melody: slow, descending phrases — enters bar 11
    # Lower register than the "active" lead; feels heavy and threatening
    s2_melody = [
        ('E5', 2.0), ('D5', 1.0), ('C5', 1.0),
        ('A4', 2.0), ('G4', 2.0),
        ('E4', 1.5), ('G4', 0.5), ('A4', 2.0),
        ('C5', 1.5), ('A4', 0.5), ('G4', 2.0),
        ('E4', 2.0), ('A4', 2.0),
    ]
    cursor = 11 * bar
    for note, dur_beats in s2_melody:
        if cursor >= 20 * bar:
            break
        mix_at(buf, synth_saw(NOTES[note], dur_beats * beat * 0.90,
                              attack=0.018, decay=0.12, sustain=0.60, release=0.16,
                              detune=0.009),
               cursor, vol=0.27)
        cursor += dur_beats * beat

    # FM metallic texture: sparse off-beat hits, dark
    for b in range(8, 20):
        bt = b * bar
        for bo, ni in [(1.5, b % 4), (3.5, (b + 2) % 4)]:
            note = ['A3', 'E3', 'G3', 'B3'][ni]
            mix_at(buf, synth_fm(NOTES[note], beat * 0.28,
                                 mod_ratio=3.0, mod_idx=4.0,
                                 attack=0.010, decay=0.09, sustain=0.0, release=0.07),
                   bt + bo * beat, vol=0.13)

    # =====================================================================
    # SECTION 3 – ACTIVE / INDUSTRIAL  (bars 20-31)
    # Drums explode: double kicks, full 16th hi-hats, driving 8th bass,
    # aggressive saw leads, FM stabs, FM counter-melody.
    # =====================================================================

    # Aggressive drum pattern with double kicks
    for b in range(20, n_bars):
        bt = b * bar
        mix_at(buf, kick_s,  bt,                  vol=1.15)
        mix_at(buf, kick_s,  bt + beat * 1.5,     vol=0.88)
        mix_at(buf, snare_s, bt + beat,            vol=1.00)
        mix_at(buf, kick_s,  bt + beat * 2,        vol=1.05)
        mix_at(buf, kick_s,  bt + beat * 2.75,     vol=0.78)
        mix_at(buf, snare_s, bt + beat * 3,        vol=1.00)
        for s16 in range(16):
            hv = 0.22 if (s16 % 4 == 0) else (0.12 if s16 % 2 == 0 else 0.07)
            mix_at(buf, synth_hihat(vol=hv, dur=0.032), bt + s16 * sixteenth)

    # Driving 8th-note bass: deep sine + saw grit layer
    bass_s3 = [
        ('A1', 1.0), ('A1', 0.85), ('G1', 1.0), ('A1', 0.90),
        ('A1', 1.0), ('E2', 0.95), ('G1', 1.0), ('A1', 0.85),
        ('A1', 1.0), ('A1', 0.85), ('G1', 1.0), ('A1', 0.90),
        ('A1', 1.0), ('E2', 0.95), ('A1', 0.85), ('G1', 1.0),
    ]
    s3_8ths = int((total_dur - 20 * bar) / eighth)
    for step in range(s3_8ths):
        t0 = 20 * bar + step * eighth
        if t0 >= total_dur:
            break
        note, vel = bass_s3[step % len(bass_s3)]
        mix_at(buf, synth_bass(NOTES[note], eighth * 0.80,
                               attack=0.004, decay=0.05, sustain=0.70, release=0.06),
               t0, vol=0.58 * vel)
        mix_at(buf, synth_saw(NOTES[note] * 2, eighth * 0.78,
                              attack=0.003, decay=0.06, sustain=0.55, release=0.05,
                              detune=0.013),
               t0, vol=0.19 * vel)

    # Aggressive saw lead: shorter, harder phrases, more chromatic
    phrase_a = [
        ('A4', 0.5), ('C5', 0.25), ('E5', 0.25), ('G5', 0.5), ('E5', 0.5),
        ('D5', 0.5), ('C5', 0.25), ('A4', 0.25),
        ('G4', 0.5), ('A4', 0.5),
        ('E4', 0.5), ('A4', 1.5),
    ]
    phrase_b = [
        ('E5', 0.5), ('G5', 0.25), ('A5', 0.25), ('G5', 0.5), ('E5', 0.5),
        ('D5', 0.5), ('C5', 0.25), ('A4', 0.25),
        ('B3', 0.5), ('A4', 0.5),
        ('C5', 0.5), ('E5', 1.5),
    ]
    for pb, phrase in [(20, phrase_a), (24, phrase_b), (28, phrase_a)]:
        if pb >= n_bars:
            break
        cursor = pb * bar
        for note, dur_beats in phrase:
            if cursor >= total_dur:
                break
            if note not in NOTES:
                cursor += dur_beats * beat
                continue
            mix_at(buf, synth_saw(NOTES[note], dur_beats * beat * 0.85,
                                  attack=0.005, decay=0.06, sustain=0.72, release=0.08,
                                  detune=0.007),
                   cursor, vol=0.36)
            cursor += dur_beats * beat

    # FM stabs on off-beats
    stab_chords = [
        ['A3', 'E4'], ['G3', 'D4'], ['A3', 'C4'], ['E3', 'B3'],
    ]
    stab_rhythm = [0.5, 1.5, 2.25, 3.0, 3.5]
    for b in range(20, n_bars):
        chord = stab_chords[b % len(stab_chords)]
        for beat_off in stab_rhythm:
            t0 = b * bar + beat_off * beat
            if t0 >= total_dur:
                break
            for note in chord:
                mix_at(buf, synth_stab(NOTES[note], sixteenth * 1.8,
                                       attack=0.003, decay=0.10,
                                       sustain=0.0, release=0.03),
                       t0, vol=0.22)

    # FM counter-melody: harsh metallic layer over section 3
    counter = [
        ('E4', 1.0), ('G4', 0.5), ('A4', 0.5),
        ('G4', 1.0), ('E4', 1.0),
        ('C4', 0.5), ('D4', 0.5), ('E4', 2.0),
    ]
    for pb in [22, 26, 30]:
        if pb >= n_bars:
            break
        cursor = pb * bar
        for note, dur_beats in counter:
            if cursor >= total_dur:
                break
            mix_at(buf, synth_fm(NOTES[note], dur_beats * beat * 0.82,
                                 mod_ratio=3.5, mod_idx=4.5,
                                 attack=0.005, decay=0.08,
                                 sustain=0.50, release=0.08),
                   cursor, vol=0.26)
            cursor += dur_beats * beat

    # Dark pads continue through section 3 (heavier voicings)
    s3_pad_chords = [
        ['A2', 'C3', 'G3', 'A3'],
        ['E2', 'B2', 'D3', 'G3'],
        ['A2', 'C3', 'G3'],
        ['G2', 'D3', 'G3'],
    ]
    for ci in range(int((n_bars - 20) / 4) + 1):
        t0 = 20 * bar + ci * 4 * bar
        if t0 >= total_dur:
            break
        chord = s3_pad_chords[ci % len(s3_pad_chords)]
        cdur = min(bar * 4 * 0.97, total_dur - t0)
        for note in chord:
            mix_at(buf, synth_pad(NOTES[note], cdur,
                                  attack=0.5, decay=0.4, sustain=0.60, release=0.9,
                                  lfo_rate=0.20, lfo_depth=0.022),
                   t0, vol=0.18)

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
        ('music_game_hard', make_game_hard_music),
        ('music_betweenwaves', make_betweenwaves_music),
    ]

    print(f'Generating {len(tracks)} music tracks -> {os.path.abspath(out_dir)}')
    for name, fn in tracks:
        print(f'  building {name}...')
        buf = fn()
        gen(name, buf, out_dir)
    print('Done.')

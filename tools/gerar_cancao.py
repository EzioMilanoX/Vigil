"""Gera a música da noite extra "A canção" (SEN-06 L.U.L.L.A.B.Y.).

    python tools/gerar_cancao.py assets/musica

Uma caixinha de música velha tocando uma cantiga lenta, original (melodia
escrita aqui, sem material de terceiros), em lá menor, 3/4, 72 por minuto:
16 compassos = 48 batidas = 40 s, em loop. Grava três arquivos:

- cancao.wav       a caixinha "limpa" (só um pouco gasta);
- cancao_torta.wav as mesmas notas, nos mesmos tempos, desafinadas, com
                   batimento, um zumbido grave e chiado de disco: o jogo
                   mistura as duas conforme o Manequim chega perto;
- cancao.json      as batidas (tempos em segundos) e a duração do loop.

As batidas saem da partitura, exatas. Para trocar a música por outra, use
tools/gerar_batidas.py, que acha as batidas de qualquer áudio.

Precisa de numpy.
"""

import json
import sys
import wave

import numpy as np

RATE = 22050
BPM = 72
BEAT = 60 / BPM
BARS = 16
BEATS = BARS * 3
LENGTH = BEATS * BEAT

# A melodia: (nota MIDI, batida de início, duração em batidas).
_A, _B, _C, _D, _E, _F, _Gs = 69, 71, 72, 74, 76, 77, 68
MELODIA = []
_COMPASSOS = [
    [(_E, 2), (_C, 1)],
    [(_D, 1), (_E, 1), (_A, 1)],
    [(_B, 2), (_Gs, 1)],
    [(_A, 3)],
    [(_E, 2), (_C, 1)],
    [(_D, 1), (_F, 1), (_E, 1)],
    [(_D, 1), (_C, 1), (_B, 1)],
    [(_E, 3)],
    [(_F, 2), (_E, 1)],
    [(_D, 1), (_C, 1), (_D, 1)],
    [(_E, 2), (_A, 1)],
    [(_B, 3)],
    [(_C, 1), (_B, 1), (_A, 1)],
    [(_Gs, 2), (_B, 1)],
    [(_A, 1), (64, 1), (_C, 1)],
    [(_A, 3)],
]
for _n, _compasso in enumerate(_COMPASSOS):
    _b = _n * 3
    for _nota, _dur in _compasso:
        MELODIA.append((_nota + 12, _b, _dur))
        _b += _dur

# Um acorde por compasso: (fundamental, terça, quinta), em MIDI.
_AM, _DM, _EM = (45, 60, 64), (50, 65, 69), (40, 56, 59)
ACORDES = [
    _AM,
    _AM,
    _EM,
    _AM,
    _AM,
    _DM,
    _EM,
    _EM,
    _DM,
    _DM,
    _AM,
    _EM,
    _AM,
    _EM,
    _AM,
    _AM,
]


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def lamina(f, dur, rng, desafino=0.0, wow=0.0):
    """Uma lâmina de caixinha de música: parciais inarmônicas que somem
    depressa nos agudos, e o estalo do pino no começo."""
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    f = f * 2 ** (desafino / 12)
    # Vibrato de mecanismo gasto (wow): a frequência oscila devagar.
    fase0 = rng.uniform(0, 2 * np.pi)
    mod = 1 + wow * np.sin(2 * np.pi * 0.6 * t + fase0)
    fase = 2 * np.pi * np.cumsum(f * mod) / RATE
    s = (
        np.exp(-t * 2.4) * np.sin(fase)
        + 0.30 * np.exp(-t * 5.0) * np.sin(2.0 * fase)
        + 0.14 * np.exp(-t * 11.0) * np.sin(5.4 * fase)
        + 0.06 * np.exp(-t * 19.0) * np.sin(8.9 * fase)
    )
    estalo = rng.uniform(-1, 1, n) * np.exp(-t * 900) * 0.6
    ataque = np.minimum(1, t * 2000)
    return ataque * s + estalo


def tocar(notas, rng, torta=False):
    """Mistura as notas [(midi, inicio_s, volume)] numa faixa de LENGTH s.
    O que passa do fim volta no começo (o loop não dá tranco)."""
    total = int(round(LENGTH * RATE))
    out = np.zeros(total)
    for midi, inicio, vol in notas:
        if torta:
            # Cada nota cai um pouco (e não sempre igual), e uma segunda
            # lâmina, mais aguda, bate contra ela.
            d = -0.45 + rng.uniform(-0.3, 0.2)
            s = lamina(hz(midi), 2.6, rng, desafino=d, wow=0.012)
            s += 0.55 * lamina(hz(midi), 2.6, rng, desafino=d + 0.55, wow=0.02)
        else:
            s = lamina(hz(midi), 2.6, rng, desafino=rng.uniform(-0.04, 0.04), wow=0.002)
        i0 = int(round(inicio * RATE))
        idx = (np.arange(len(s)) + i0) % total
        np.add.at(out, idx, vol * s)
    return out


def partitura():
    notas = []
    for midi, b, _dur in MELODIA:
        notas.append((midi, b * BEAT, 1.0))
    for c, (raiz, terca, quinta) in enumerate(ACORDES):
        b = c * 3
        notas.append((raiz, b * BEAT, 0.55))
        # Batidas 2 e 3: a terça e a quinta, baixinho (toda batida tem ataque).
        notas.append((terca, (b + 1) * BEAT, 0.28))
        notas.append((quinta, (b + 1) * BEAT, 0.22))
        notas.append((terca, (b + 2) * BEAT, 0.24))
        notas.append((quinta, (b + 2) * BEAT, 0.2))
    return notas


def limpa():
    rng = np.random.default_rng(3)
    s = tocar(partitura(), rng)
    # Um chiado de fundo bem baixo: a caixinha é velha.
    s += 0.004 * rng.uniform(-1, 1, len(s))
    return s


def torta():
    rng = np.random.default_rng(5)
    s = tocar(partitura(), rng, torta=True)
    n = len(s)
    t = np.arange(n) / RATE
    # Um zumbido grave (lá e si bemol juntos, quase no mesmo tom) que respira.
    drone = np.sin(2 * np.pi * 55 * t) + 0.8 * np.sin(2 * np.pi * 58.27 * t)
    drone *= 0.10 * (0.6 + 0.4 * np.sin(2 * np.pi * t / LENGTH * 4))
    # Chiado de disco: estalos esparsos e ruído.
    estalos = (rng.random(n) < 0.0009) * rng.uniform(-1, 1, n) * 0.5
    s = s + drone + estalos + 0.012 * rng.uniform(-1, 1, n)
    # Uma leve saturação, para soar "estragada".
    return np.tanh(1.6 * s / np.max(np.abs(s))) / np.tanh(1.6)


def salvar(caminho, s, pico=0.85):
    s = s / max(1e-9, np.max(np.abs(s))) * pico
    dados = (s * 32767).astype("<i2").tobytes()
    with wave.open(caminho, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(dados)


if __name__ == "__main__":
    pasta = sys.argv[1] if len(sys.argv) > 1 else "assets/musica"
    salvar(f"{pasta}/cancao.wav", limpa())
    salvar(f"{pasta}/cancao_torta.wav", torta())
    batidas = [round(i * BEAT, 4) for i in range(BEATS)]
    with open(f"{pasta}/cancao.json", "w", encoding="utf-8") as f:
        json.dump(
            {
                "fonte": "tools/gerar_cancao.py (partitura)",
                "bpm": BPM,
                "length": round(LENGTH, 4),
                "beats": batidas,
            },
            f,
            indent=1,
        )
        f.write("\n")
    print(f"ok: {BEATS} batidas, {LENGTH:.1f} s")

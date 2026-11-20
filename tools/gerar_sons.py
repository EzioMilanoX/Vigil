"""Gera os sons do Vigil (mono, 44.1 kHz, sem arquivos de terceiros).

    python tools/gerar_sons.py assets/sons
"""
import math
import random
import struct
import sys
import wave

RATE = 44100
random.seed(7)


def salvar(pasta, nome, amostras):
    pico = max(1e-9, max(abs(s) for s in amostras))
    with wave.open(f"{pasta}/{nome}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(32000 * 0.9 * s / pico)) for s in amostras))


def passo():
    """Um passo pesado em piso de madeira."""
    n = int(RATE * 0.35)
    s, lp = [], 0.0
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 18)
        lp += 0.08 * (random.uniform(-1, 1) - lp)
        s.append(env * (0.7 * math.sin(2 * math.pi * 62 * t) + 2.5 * lp))
    return s


def rangido():
    """Articulação de manequim rangendo: ele chegou."""
    n = int(RATE * 0.9)
    s, fase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = 210 + 90 * math.sin(2 * math.pi * 1.3 * t) + 25 * random.uniform(-1, 1)
        fase += 2 * math.pi * f / RATE
        pulso = 1.0 if math.sin(2 * math.pi * 23 * t + 3 * math.sin(7 * t)) > 0.3 else 0.25
        env = min(1, t * 8) * min(1, (0.9 - t) * 5)
        s.append(env * pulso * (math.sin(fase) + 0.4 * math.sin(2.01 * fase)))
    return s


def coracao():
    n = int(RATE * 0.8)
    s = []
    for i in range(n):
        t = i / RATE
        v = 0.0
        for t0, a in ((0.0, 1.0), (0.22, 0.7)):
            if t >= t0:
                d = t - t0
                v += a * math.exp(-d * 25) * math.sin(2 * math.pi * 48 * d)
        s.append(v)
    return s


def chiado():
    """Chiado de rádio, em loop: ruído com zumbido e falhas."""
    n = int(RATE * 2.0)
    s = []
    for i in range(n):
        t = i / RATE
        falha = 0.35 if int(t * 37) % 7 == 0 else 1.0
        s.append(falha * (random.uniform(-1, 1) * 0.8 + 0.2 * math.sin(2 * math.pi * 60 * t)))
    return s


def choque():
    """O choque: um zumbido elétrico que estala e some."""
    n = int(RATE * 0.5)
    s = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 6)
        quadrada = 1.0 if math.sin(2 * math.pi * 118 * t) > 0 else -1.0
        estalo = random.uniform(-1, 1) if random.random() < 0.3 else 0
        s.append(env * (0.6 * quadrada + 0.6 * estalo))
    return s


def grito():
    """O grito do susto: serra que sobe, com ruído e distorção."""
    n = int(RATE * 1.3)
    s, fase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = 300 + 900 * min(1, t * 2) + 60 * math.sin(2 * math.pi * 13 * t)
        fase += f / RATE
        serra = 2 * (fase % 1) - 1
        env = min(1, t * 20) * (1 if t < 1.0 else max(0, (1.3 - t) / 0.3))
        v = env * (0.7 * serra + 0.5 * random.uniform(-1, 1))
        s.append(max(-0.8, min(0.8, v * 1.6)))
    return s


def batida():
    """Três batidas abafadas na parede (susto falso)."""
    n = int(RATE * 1.1)
    s = [0.0] * n
    for t0 in (0.0, 0.32, 0.58):
        lp = 0.0
        for i in range(int(RATE * 0.25)):
            j = int(t0 * RATE) + i
            if j >= n:
                break
            t = i / RATE
            lp += 0.05 * (random.uniform(-1, 1) - lp)
            s[j] += math.exp(-t * 30) * (math.sin(2 * math.pi * 75 * t) + 3 * lp)
    return s


def zumbido():
    """O zumbido da Mariposa, em loop: asas batendo rápido."""
    n = int(RATE * 1.0)
    s = []
    for i in range(n):
        t = i / RATE
        asa = 0.55 + 0.45 * math.sin(2 * math.pi * 31 * t)
        f = 165 + 8 * math.sin(2 * math.pi * 3 * t)
        serra = 2 * ((f * t) % 1) - 1
        s.append(asa * (0.6 * serra + 0.25 * random.uniform(-1, 1)))
    return s


if __name__ == "__main__":
    pasta = sys.argv[1] if len(sys.argv) > 1 else "assets/sons"
    for nome, gerar in [
        ("passo", passo),
        ("rangido", rangido),
        ("coracao", coracao),
        ("chiado", chiado),
        ("choque", choque),
        ("grito", grito),
        ("batida", batida),
        ("zumbido", zumbido),
    ]:
        salvar(pasta, nome, gerar())
    print("ok")

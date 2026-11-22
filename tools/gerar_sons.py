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


def _serra(f, t):
    return 2 * ((f * t) % 1) - 1


def respiro():
    """Uma respiração lenta e rouca bem perto (emboscada): puxa e solta."""
    n = int(RATE * 1.5)
    s, lp, bp = [], 0.0, 0.0
    for i in range(n):
        t = i / RATE
        if t < 0.65:
            env = math.sin(math.pi * t / 1.3) ** 2
            corte = 0.08
        else:
            u = (t - 0.65) / 0.85
            env = max(0.0, 1 - u) ** 1.5 * 1.2
            corte = 0.05
        ruido = random.uniform(-1, 1)
        lp += corte * (ruido - lp)
        bp += 0.3 * (lp - bp)
        rouco = 0.25 * math.sin(2 * math.pi * 62 * t) * (0.5 + 0.5 * math.sin(2 * math.pi * 23 * t))
        s.append(env * (2.5 * (lp - bp) + rouco * (t > 0.65)))
    return s


def apagao():
    """A lanterna morrendo: um estalo elétrico e o zumbido que cai e some."""
    n = int(RATE * 0.9)
    s = []
    for i in range(n):
        t = i / RATE
        estalo = random.uniform(-1, 1) * math.exp(-t * 60)
        f = 120 * (1 - 0.6 * min(1, t / 0.7))
        zumbido = 0.5 * _serra(f, t) * max(0, 1 - t / 0.75)
        falha = 1 if random.random() > 0.15 * t * 10 else 0
        s.append(estalo + zumbido * falha)
    return s


def rosto():
    """O rosto que pisca no feixe: um corte agudo e dissonante, curtíssimo."""
    n = int(RATE * 0.55)
    s = []
    for i in range(n):
        t = i / RATE
        env = min(1, t * 400) * math.exp(-t * 7)
        v = (_serra(1400, t) + _serra(1487, t) + 0.6 * _serra(1980, t)) / 2.6
        baque = 1.2 * math.sin(2 * math.pi * 55 * t) * math.exp(-t * 18)
        s.append(env * (v + 0.35 * random.uniform(-1, 1)) + baque)
    return s


def susto():
    """O susto de quando ele pega: estouro, acorde que se esfrega subindo,
    grave que soca o peito e um guincho metálico por cima, tudo saturado."""
    n = int(RATE * 1.8)
    s = []
    fases = [0.0] * 4
    base = [196, 207.6, 293.7, 415.3]
    for i in range(n):
        t = i / RATE
        subida = 1 + 0.5 * min(1, t / 0.9)
        acorde = 0.0
        for k, f in enumerate(base):
            fases[k] += f * subida * (1 + 0.012 * math.sin(2 * math.pi * (6 + k) * t)) / RATE
            acorde += 2 * (fases[k] % 1) - 1
        acorde /= 4
        guincho = math.sin(2 * math.pi * (1700 + 260 * math.sin(2 * math.pi * 9 * t)) * t)
        soco = math.sin(2 * math.pi * 45 * t) * math.exp(-t * 5)
        estouro = random.uniform(-1, 1) * math.exp(-t * 35)
        env = min(1, t * 300) * (1 if t < 1.35 else max(0, (1.8 - t) / 0.45))
        v = env * (0.9 * acorde + 0.45 * guincho + 1.1 * soco + 0.4 * random.uniform(-1, 1)) + estouro
        s.append(max(-0.7, min(0.7, v * 2.2)))
    return s


RATE_3D = 22050
DIRECOES = range(0, 360, 45)


def _reamostrar(s, de, para):
    passo = de / para
    return [s[int(i * passo)] for i in range(int(len(s) / passo))]


def _passa_baixa(s, corte):
    """Filtro de um polo: corte em Hz, na taxa do 3D."""
    a = 1 - math.exp(-2 * math.pi * corte / RATE_3D)
    out, y = [], 0.0
    for v in s:
        y += a * (v - y)
        out.append(y)
    return out


def binaural(mono, graus):
    """Põe um som mono numa direção em volta da cabeça (0 = frente, 90 = direita).

    Aproximação de HRTF sem tabela: atraso entre os ouvidos (até 0,66 ms),
    diferença de volume, a sombra da cabeça abafando o ouvido de longe e,
    atrás, o som todo mais abafado (a orelha filtra o que vem de trás).
    """
    th = math.radians(graus)
    s = _reamostrar(mono, RATE, RATE_3D)
    if math.cos(th) < 0:
        s = _passa_baixa(s, 1800 + 1400 * (1 + math.cos(th)))
    lado = math.sin(th)  # + direita
    atraso = int(abs(lado) * 0.00066 * RATE_3D)
    perto, longe = s, [0.0] * atraso + _passa_baixa(s, 900 + 4000 * (1 - abs(lado)))
    longe = [v * (1 - 0.5 * abs(lado)) for v in longe[: len(s)]]
    esq, dir_ = (longe, perto) if lado > 0 else (perto, longe)
    return esq, dir_


def salvar_estereo(caminho, esq, dir_):
    pico = max(1e-9, max(max(abs(v) for v in esq), max(abs(v) for v in dir_)))
    with wave.open(caminho, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE_3D)
        w.writeframes(
            b"".join(
                struct.pack("<hh", int(30000 * a / pico), int(30000 * b / pico))
                for a, b in zip(esq, dir_)
            )
        )


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
        ("respiro", respiro),
        ("apagao", apagao),
        ("rosto", rosto),
        ("susto", susto),
    ]:
        salvar(pasta, nome, gerar())
    # As versões em 3D (fone): uma por direção, de 45 em 45 graus.
    import os

    os.makedirs(f"{pasta}/3d", exist_ok=True)
    random.seed(11)
    for nome, gerar in [
        ("passo", passo),
        ("rangido", rangido),
        ("grito", grito),
        ("batida", batida),
        ("zumbido", zumbido),
        ("respiro", respiro),
    ]:
        mono = gerar()
        for g in DIRECOES:
            esq, dir_ = binaural(mono, g)
            salvar_estereo(f"{pasta}/3d/{nome}_{g:03d}.wav", esq, dir_)
    print("ok")

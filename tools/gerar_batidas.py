"""Acha as batidas de uma música e grava o JSON que a noite "A canção" lê.

    python tools/gerar_batidas.py musica.mp3 assets/musica/cancao.json
    python tools/gerar_batidas.py musica.wav saida.json --motor numpy
    python tools/gerar_batidas.py musica.wav saida.json --conferir assets/musica/cancao.json

Saída: {"length": duração em s, "bpm": estimado, "beats": [tempos em s]}.
O jogo toca a música em loop e o Manequim dá um passo em cada batida.

Motores:
- librosa (se estiver instalado): librosa.beat.beat_track. Lê wav, mp3,
  ogg, flac...
- numpy (sempre funciona): fluxo espectral (onde a energia sobe de repente),
  o andamento pela autocorrelação e as batidas por programação dinâmica
  (o método de Ellis, 2007: cada batida cai num ataque forte e o intervalo
  entre elas fica perto do andamento). Lê WAV; outros formatos passam pelo
  ffmpeg, se estiver no PATH.

--conferir compara com outro JSON de batidas (quantas ficaram a até 50 ms).
Músicas sem percussão clara dão batidas ruins: abra o JSON, olhe o bpm e,
se precisar, force a faixa de andamento com --min-bpm/--max-bpm.
"""

import argparse
import json
import shutil
import subprocess
import sys
import wave

import numpy as np

RATE = 22050
HOP = 256
# O pico do fluxo de um quadro fica ~3/4 de janela depois do início dele
# (medido com a partitura de gerar_cancao.py). O áudio entra com esse
# tanto de silêncio na frente: assim o quadro i marca o ataque em i * HOP.
ATRASO = 1536


def ler_audio(caminho):
    """Mono, float em [-1, 1], a RATE Hz."""
    try:
        with wave.open(caminho, "rb") as w:
            canais, largura, taxa = w.getnchannels(), w.getsampwidth(), w.getframerate()
            bruto = w.readframes(w.getnframes())
        if largura != 2:
            raise wave.Error("só WAV de 16 bits")
        s = np.frombuffer(bruto, "<i2").astype(np.float64) / 32768
        s = s.reshape(-1, canais).mean(axis=1)
        if taxa != RATE:
            x = np.arange(0, len(s), taxa / RATE)
            s = np.interp(x, np.arange(len(s)), s)
        return s
    except (wave.Error, EOFError):
        pass
    if not shutil.which("ffmpeg"):
        sys.exit("Só leio WAV de 16 bits sem o ffmpeg (ou instale o librosa).")
    bruto = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-i",
            caminho,
            "-ac",
            "1",
            "-ar",
            str(RATE),
            "-f",
            "s16le",
            "-",
        ],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        check=True,
    ).stdout
    return np.frombuffer(bruto, "<i2").astype(np.float64) / 32768


def com_librosa(caminho, min_bpm, max_bpm):
    import librosa

    y, sr = librosa.load(caminho, sr=RATE, mono=True)
    inicio = (min_bpm * max_bpm) ** 0.5
    tempo, batidas = librosa.beat.beat_track(y=y, sr=sr, units="time", start_bpm=inicio)
    bpm = float(np.atleast_1d(tempo)[0])
    if bpm < min_bpm or bpm > max_bpm:
        # Pegou a metade ou o dobro: refaz preso à faixa pedida.
        alvo = min(max(bpm, min_bpm), max_bpm)
        tempo, batidas = librosa.beat.beat_track(
            y=y, sr=sr, units="time", start_bpm=alvo, tightness=400
        )
        bpm = float(np.atleast_1d(tempo)[0])
    return y.astype(np.float64), bpm, [float(b) for b in batidas]


def fluxo(s, n_fft=2048, hop=HOP):
    """Força de ataque por quadro (fluxo espectral em escala log)."""
    s = np.concatenate([np.zeros(ATRASO), s])
    janela = np.hanning(n_fft)
    quadros = 1 + max(0, len(s) - n_fft) // hop
    mags = np.empty((quadros, n_fft // 2 + 1))
    for i in range(quadros):
        mags[i] = np.abs(np.fft.rfft(janela * s[i * hop : i * hop + n_fft]))
    log = np.log1p(100 * mags)
    d = np.maximum(0, np.diff(log, axis=0)).sum(axis=1)
    d = np.concatenate([[0], d])
    # Tira a tendência lenta (o volume da música subindo e descendo).
    k = int(RATE / hop * 0.5) | 1
    base = np.convolve(d, np.ones(k) / k, mode="same")
    d = np.maximum(0, d - base)
    return d / (d.std() + 1e-9), RATE / hop


def andamento(onset, fps, min_bpm, max_bpm):
    """O período (em quadros) com mais autocorrelação, preferindo ~90 bpm."""
    o = onset - onset.mean()
    ac = np.correlate(o, o, mode="full")[len(o) - 1 :]
    melhor, periodo = -np.inf, None
    for bpm in np.arange(min_bpm, max_bpm, 0.25):
        p = 60 * fps / bpm
        i = int(round(p))
        if i >= len(ac):
            continue
        # O período e os seus múltiplos (compassos) somam evidência.
        v = (
            ac[i]
            + 0.5 * ac[min(len(ac) - 1, 2 * i)]
            + 0.25 * ac[min(len(ac) - 1, 3 * i)]
        )
        v *= np.exp(-0.5 * (np.log2(bpm / 90) / 0.9) ** 2)
        if v > melhor:
            melhor, periodo = v, p
    return periodo


def com_numpy(caminho, min_bpm, max_bpm):
    s = ler_audio(caminho)
    onset, fps = fluxo(s)
    p = andamento(onset, fps, min_bpm, max_bpm)
    # Programação dinâmica: pontuação = ataque aqui + melhor batida anterior,
    # punindo intervalos longe do período.
    n = len(onset)
    pont = onset.astype(np.float64).copy()
    antes = np.full(n, -1)
    lo, hi = int(round(p / 2)), int(round(2 * p))
    desvios = np.arange(lo, hi + 1)
    custo = -100 * np.log(desvios / p) ** 2
    for t in range(hi, n):
        cand = pont[t - desvios] + custo
        j = int(np.argmax(cand))
        pont[t] = onset[t] + cand[j]
        antes[t] = t - desvios[j]
    # Começa do fim, na melhor batida do último período, e volta.
    fim = n - hi + int(np.argmax(pont[n - hi :]))
    batidas = []
    t = fim
    while t >= 0:
        batidas.append(t)
        t = antes[t]
    batidas.reverse()
    return s, 60 * fps / p, [b / fps for b in batidas]


def afinar(s, bpm, batidas):
    """Igual para os dois motores: completa as batidas que faltam no começo e
    no fim (no ritmo do andamento), puxa cada uma para o pico de ataque mais
    perto (±40 ms) e tira as que ficaram coladas."""
    onset, fps = fluxo(s)
    p = 60 / bpm
    dur = len(s) / RATE
    batidas = sorted(batidas)
    while batidas and batidas[0] - p >= -0.02:
        batidas.insert(0, batidas[0] - p)
    while batidas and batidas[-1] + p < dur - 0.02:
        batidas.append(batidas[-1] + p)
    r = int(0.04 * fps)
    finas = []
    for t in batidas:
        q = int(round(max(0.0, t) * fps))
        a, z = max(0, q - r), min(len(onset), q + r + 1)
        if a >= z:
            continue
        finas.append((a + int(np.argmax(onset[a:z]))) / fps)
    out = []
    for t in finas:
        if not out or t - out[-1] >= 0.6 * p:
            out.append(t)
    # A música toca em loop: uma batida colada no fim é a primeira de novo.
    if len(out) > 1 and out[0] + dur - out[-1] < 0.6 * p:
        out.pop()
    return out


def conferir(batidas, referencia, tol=0.05):
    ref = np.array(referencia)
    perto = sum(1 for b in batidas if np.min(np.abs(ref - b)) <= tol)
    erros = [float(np.min(np.abs(ref - b))) for b in batidas]
    print(
        f"conferência: {perto}/{len(batidas)} batidas a até {int(tol * 1000)} ms "
        f"(referência tem {len(ref)}); erro médio {1000 * np.mean(erros):.1f} ms"
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("audio")
    ap.add_argument("saida")
    ap.add_argument("--motor", choices=["auto", "librosa", "numpy"], default="auto")
    ap.add_argument("--min-bpm", type=float, default=50)
    ap.add_argument("--max-bpm", type=float, default=180)
    ap.add_argument("--conferir", help="outro JSON de batidas para comparar")
    a = ap.parse_args()

    motor = a.motor
    if motor == "auto":
        try:
            import librosa  # noqa: F401

            motor = "librosa"
        except ImportError:
            motor = "numpy"
    achar = com_librosa if motor == "librosa" else com_numpy
    s, bpm, batidas = achar(a.audio, a.min_bpm, a.max_bpm)
    duracao = len(s) / RATE
    batidas = afinar(s, bpm, batidas)
    batidas = sorted(round(b, 4) for b in batidas if 0 <= b < duracao)
    if len(batidas) < 2:
        sys.exit("Não achei batidas: a música tem ritmo?")
    with open(a.saida, "w", encoding="utf-8") as f:
        json.dump(
            {
                "fonte": f"tools/gerar_batidas.py ({motor})",
                "bpm": round(bpm, 2),
                "length": round(duracao, 4),
                "beats": batidas,
            },
            f,
            indent=1,
        )
        f.write("\n")
    print(
        f"{motor}: {len(batidas)} batidas, ~{bpm:.1f} bpm, {duracao:.1f} s -> {a.saida}"
    )
    if a.conferir:
        with open(a.conferir, encoding="utf-8") as f:
            conferir(batidas, json.load(f)["beats"])


if __name__ == "__main__":
    main()

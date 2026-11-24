# Mudanças

## 0.5.0 (2026-11-24)

- **Diretor do medo.** Ele aprende como você joga ao longo da noite (e lembra se você tentar de novo):
  - repara para onde você mais olha e passa a chegar mais pelo lado do quarto que você esquece (preferido, nunca garantido);
  - a tática que te pegou ou quase pegou volta mais vezes; a que você espanta fácil, menos. Quem vive de lanterna acesa vê mais apagão; quem economiza luz, mais estátua; quem demora a achar o chiado, mais sumiço;
  - a tensão sobe e desce: depois de um susto forte (o choque, a respiração, o apagão, o rosto), um respiro curto sem sustos falsos; quando nada acontece há um tempo, eles voltam mais. Depois de um espanto suado, ele demora um pouco mais a voltar;
  - é justo: nunca a mesma tática duas vezes seguidas, a primeira é sempre rondar, toda tática da noite continua possível e nada muda na velocidade dele nem na janela do choque;
  - dá para desligar em Configurações (Medo → Diretor do medo); desligado, é tudo sorteio, como antes.
- **Recentralizar:** a bússola discreta no canto de cima faz da frente de agora a frente do quarto, para quando o giroscópio derivar. Ele, a Mariposa e o chiado continuam onde estavam em relação a você.
- **Noite extra: A canção** (protótipo do conceito SEN-06 L.U.L.L.A.B.Y.), liberada depois de vencer a noite 4, no fim de "Noites e recordes":
  - uma caixinha de música velha toca uma cantiga lenta (original, sintetizada); o Manequim só dá um passo na batida e, entre as batidas, fica parado;
  - quando ele corre, o choque só pega dentro de ±80 ms de uma batida e mirando nele; fora do tempo é erro (aparece "fora do tempo" na tela e a contagem no fim da noite). Na batida em que ele chega em você, ainda dá para acertar dentro da janela;
  - para o ritmo não virar previsão, sumir, o chiado, a finta da corrida e passos falsos acontecem fora do tempo;
  - quanto mais perto ele está, mais rápida e mais desafinada a música fica;
  - em Configurações → Acessibilidade: um pulso discreto na borda da tela no tempo da música (desligado por padrão) e o atraso do som, para fone Bluetooth;
  - para trocar a música: `tools/gerar_batidas.py` acha as batidas de qualquer áudio (librosa ou, sem ele, um detector em numpy) e grava o JSON que o jogo lê.

## 0.4.0 (2026-11-22)

- **Ele não vem sempre do mesmo jeito.** Cada aparição sorteia uma tática, nunca a mesma duas vezes seguidas:
  - **Estátua** (desde a noite 1): com a luz em cima, congela e muda de pose quando você não está vendo; no escuro, anda depressa. Segurar a luz gasta a pilha.
  - **Emboscada** (noite 2): some sem barulho e reaparece atrás de você; só uma respiração avisa antes de ele correr.
  - **Apagão** (noite 3): perto, a lanterna morre; ele corre invisível em volta e só os passos e o chiado o acham. O choque traz a luz de volta.
- **Sustos de verdade:**
  - quando ele pega, a luz morre e tudo fica em silêncio por meio segundo; então o rosto avança da escuridão e ocupa a tela, com a imagem rasgando, as cores se separando e um clarão;
  - o rosto é desenhado de perto: porcelana rachada iluminada de baixo, um pedaço faltando, órbitas fundas com pupilas acesas e a boca rasgada;
  - um grito novo em camadas (estouro, acorde que se esfrega subindo, grave que soca e um guincho por cima) e vibração em três tempos;
  - com a luz acesa, o rosto às vezes pisca dentro do feixe, com um corte agudo (susto falso);
  - o quarto treme com a respiração e com o apagão.

## 0.3.1 (2026-11-21)

- **Desempenho:** o chiado não cria mais milhares de pontos a cada quadro (usa um conjunto sorteado uma vez, deslocado a cada quadro). Medido no S20 FE: pintura de 1,9 ms em média (p95 2,5 ms) e nenhum quadro lento em 300, com câmera e lanterna. Para medir em outro celular: `flutter build apk --release --dart-define=VIGIL_PERF=true` mostra o tempo de cada quadro na tela.

## 0.3.0 (2026-11-20)

- **Som 3D (com fone):** passos, rangidos, o grito, as batidas e o zumbido vêm gravados em 8 direções, com a diferença de tempo e de volume entre os ouvidos e o som de trás mais abafado. Dá para ouvir se ele está na frente ou atrás, não só de que lado. Sem fone, desligue em Configurações.
- **Conquistas:** oito, de "Primeira vigília" a "Uma semana em claro" (choque perfeito, noite sem errar, noite quase sem lanterna, 30 espantos...). Aparecem no fim da noite em que você ganha.
- **Diário:** a história de cada noite vencida e o que se acha na manhã seguinte (etiquetas, alfinetes, um recibo de 1987...).

## 0.2.0 (2026-11-20)

- **Menu de verdade:** o manequim parado no escuro ao fundo, com a luz falhando; continuar da noite liberada, noites e recordes, treino e configurações.
- **Treino jogável:** quatro passos guiados (achar, iluminar, seguir o chiado, o choque na hora certa), com "AGORA!" quando é a hora.
- **História:** um trecho antes de cada noite (o Ateliê Valente, as etiquetas, os casulos), escrito aos poucos.
- **Noites e recordes:** vitórias, mortes e o amanhecer mais rápido de cada noite; o que cada noite traz de novo.
- **Configurações:** volume, vibração, câmera, sensibilidade e inversão do giro, e jogar sentado (só arrastando).
- **Mais difícil e mais tenso:** ele chega mais rápido sem ninguém olhando e a janela do choque é mais curta. Da noite 2, fintas: ele corre e para no meio. Da noite 3, corre invisível. A pilha falha mais justo quando ele corre.
- **A Mariposa (noite 4+):** só avança enquanto a lanterna está acesa e vai embora no escuro; o zumbido diz o lado. Briga com o manequim, que precisa da luz.
- **Sustos falsos:** batidas na parede e um vulto que cruza a tela.
- **Pausa:** botão na tela e pausa sozinho quando o celular toca ou você sai do app.

## 0.1.0 (2026-11-20)

Primeira versão para testar.

- **O manequim** anda em volta de você, chega perto aos poucos e às vezes some. Quando some, só o chiado na tela e no som denuncia onde ele está, e a lanterna em cima o revela.
- **Choque no tempo certo:** quando ele corre, o choque só pega se ele já estiver perto e você estiver mirando nele. Errar gasta o choque, que leva um tempo para recarregar.
- **Câmera e lanterna de verdade:** o fundo é o seu quarto pela câmera, escurecido, e a lanterna do celular acende junto com a do jogo. Sem câmera, aparece um quarto desenhado.
- **Gire o corpo:** o giroscópio, projetado na vertical, funciona com o celular em pé ou inclinado. No Windows, arraste.
- **Sons com direção:** passos, rangido, chiado, choque, coração e grito, com pan esquerda/direita; o que vem de trás soa mais grave.
- **Noites:** cada noite vencida libera a próxima, com mais vezes para espantá-lo, ele mais rápido e a pilha mais curta.
- **A lembrança mente:** às vezes a tela chia de um lado onde ele não está.

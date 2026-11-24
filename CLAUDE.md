# CLAUDE.md — Vigil

Terror de celular (Android; Windows só para testar). Idioma: PT-BR. Repositório público: [EzioMilanoX/Vigil](https://github.com/EzioMilanoX/Vigil).

**Promovido do blueprint `SEN-05` V.I.G.I.L.** (`PersonalBlueprints/00 Visualizador/data.js`). Na 0.1.0 virou um terror no estilo "realidade aumentada" (pedido do Enzo: "mais parecido com FNAF AR"). Usa só as **mecânicas** do gênero: criatura em volta de você, invisível revelada pela luz, choque no tempo certo. **Não copiar** nome, personagens, arte nem visual de jogo existente: a criatura é o Manequim, original. Não usa a OuroborosEngine (Python não roda no Android).

## Comandos

- `flutter run` · `flutter test` · `flutter analyze`
- Capturas para o README: `flutter test telas/telas_test.dart --update-goldens`
- Ícone: `flutter test telas/icone_test.dart --update-goldens` e depois `dart run flutter_launcher_icons`
- Sons: `python tools/gerar_sons.py assets/sons` (sintetizados, sem arquivos de terceiros)
- `telas/` fica fora da suíte normal e do analyze (usa as fontes do SDK do Flutter em `C:/flutter`).

## Estrutura

- `lib/game/vigil_game.dart` — as regras em Dart puro, determinísticas por `seed`. Manequim: `Mode.roaming` (rodeia e chega perto, às vezes `cloaked`), `charging` (corre; o choque só pega com `distance <= shockWindow` e mirando), `gone` (espantado, volta de outro lado). `staticLevel` = chiado quando você olha para ele invisível (ou para o chiado falso, "a lembrança mente"). `Rules.forNight(n)` endurece a noite.
- `lib/ui/mannequin.dart` — o desenho do Manequim (claro na luz, silhueta e olhos no escuro, defeito de imagem).
- `lib/ui/room_painter.dart` — escuro com o buraco do feixe, o Manequim (aceso só dentro do feixe), chiado, quarto desenhado quando não há câmera, e o susto.
- `lib/ui/game_screen.dart` — câmera (`camera`, a lanterna real acompanha), giroscópio projetado na vertical (`sensors_plus`), botões segurar-lanterna e choque, sons (`lib/ui/sounds.dart`).
- `lib/ui/title_screen.dart` — o menu (TitleScreen), NightsScreen, StoryScreen (texto em `lib/game/story.dart`) e SettingsScreen.
- `lib/data/save.dart` — noite liberada, recordes por noite, treino feito e configurações, num JSON em `shared_preferences`.
- `lib/game/tutorial.dart` — o treino: `TutorialCoach` monta cada situação com o jogo em `scripted` (ele não anda nem mata sozinho).
- Som 3D: `tools/gerar_sons.py` grava `assets/sons/3d/<som>_<graus>.wav` (8 direções, binaural aproximado: atraso e volume entre ouvidos, sombra da cabeça, trás abafado); `Sounds.direction(angle)` escolhe a mais próxima. `Cue.angle` é o ângulo relativo ao olhar.
- Conquistas: `lib/game/achievements.dart` (`earnedBy(NightResult)`); o jogo conta `lanternTime`, `misses`, `perfectHits`; `Save.finish` guarda recorde e conquistas. Diário: `JournalScreen` com `storyFor` e `foundAfter` (`lib/game/story.dart`).
- Noites: 2 = fintas (`feintChance`), 3 = corrida invisível (`cloakedCharge`), 4+ = a Mariposa (`moth`: avança com a luz acesa, recua no escuro). `Rules.novelty(n)` é o texto do que a noite traz.
- Táticas (`Tactic`): cada `_arrive` sorteia uma de `Rules.tactics`, nunca a mesma seguida, e a primeira da noite é `roam`. `statue` (congela com `lit && inBeam`, `pose` muda quando a luz sai), `ambush` (`lurking`: invisível, sem chiado nem `arrive`; depois `CueKind.breath` atrás, `ambushWarnSeconds`, e corrida mais lenta por `ambushChargeFactor`), `blackout` (em `blackoutAt` liga `blackout`, que apaga `lit`; passos a cada 0,55 s; choque com mira 30% mais larga). Noite 1: roam+statue; 2: +ambush; 3: +blackout.
- Diretor do medo: `lib/game/director.dart` (`FearDirector`, Dart puro e sem `Random` próprio: o `roll` vem do `_rng` do jogo, então segue determinístico pelo seed). Observa olhar por setor do quarto (`look`), lanterna, tempo até achar o chiado e o resultado de cada aparição (`Outcome`); escolhe a tática (`nextTactic`, pesos 0,5–3, sem repetir, primeira = roam), o lado (`side`, até 85% para o esquecido) e dosa `faceFlash`/sustos falsos com respiro (`calm`) depois de susto forte. `VigilGame(director:)`; sem ele, sorteio como antes. A `GameScreen` mantém o mesmo diretor no "De novo". Liga/desliga em `Settings.fearDirector`. Recentralizar: `VigilGame.recenter()` gira o mundo todo (e a memória do diretor) para `heading = 0`; botão `recentralizar` no HUD.
- Sustos: `faceFlash` (o rosto pisca no feixe, `faceFlashPerSecond`, só com a luz acesa); ao perder, `_doom` (escuro e `Sounds.hush()` por 0,55 s) e então `ScarePainter` (`scareSeconds`) com `drawScareFace` de `mannequin.dart`. Sons novos em `gerar_sons.py`: `respiro` (com 3D), `apagao`, `rosto`, `susto`.
- A canção (noite extra `songNight = 0`, SEN-06; liberada depois da noite 4): `lib/game/lullaby.dart` (`BeatMap` lê `assets/musica/cancao.json`, `SongClock` com janela ±80 ms e `sync` pela posição do áudio) e `VigilGame(song:)` + `Rules.lullaby()` (avança só em `_onBeat`; finta, chiado e `CueKind.offbeat` fora do tempo; `songTempo`/`songDetune` misturam `cancao.wav` e `cancao_torta.wav` no `SongPlayer`). Música: `python tools/gerar_cancao.py assets/musica`; trocar: `python tools/gerar_batidas.py musica.mp3 assets/musica/cancao.json` (librosa ou numpy; `--conferir` compara), e substituir os dois WAV.
- Emulador para testar sem o celular: ver "Emulador" abaixo.

## Emulador

`powershell -File ../_templates/emulador.ps1 ligar`, depois `flutter build apk --release` (todas as ABIs), `instalar`, `abrir com.eziomilanox.vigil`, `print`, `arrastar` (gira o quarto), `segurar 170 2044 1500` (lanterna, tela 1080x2280). A câmera do emulador é uma cena virtual. Toques pelo adb chegam com ~1–2 s de atraso: o tempo do choque não dá para testar assim (está nos testes de `vigil_game_test.dart`).

## Release

APK feito na máquina (`flutter build apk --release`, assinado com a chave de debug desta máquina) e anexado à release do GitHub. O CI gera um APK numa tag `v*`, mas com outra chave de debug: não misturar os dois no mesmo celular sem desinstalar.

## Riscos conhecidos

- O giroscópio deriva; o recentralizar (bússola no HUD) redefine a frente, mas não há referência absoluta: com a câmera, ele ainda escorrega devagar pelo quarto real.
- Girar o corpo cansa: noites curtas (3 a 6 espantos).
- Sem fone, perde metade das pistas.

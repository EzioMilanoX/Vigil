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
- Emulador para testar sem o celular: ver "Emulador" abaixo.

## Emulador

`powershell -File ../_templates/emulador.ps1 ligar`, depois `flutter build apk --release` (todas as ABIs), `instalar`, `abrir com.eziomilanox.vigil`, `print`, `arrastar` (gira o quarto), `segurar 170 2044 1500` (lanterna, tela 1080x2280). A câmera do emulador é uma cena virtual. Toques pelo adb chegam com ~1–2 s de atraso: o tempo do choque não dá para testar assim (está nos testes de `vigil_game_test.dart`).

## Release

APK feito na máquina (`flutter build apk --release`, assinado com a chave de debug desta máquina) e anexado à release do GitHub. O CI gera um APK numa tag `v*`, mas com outra chave de debug: não misturar os dois no mesmo celular sem desinstalar.

## Riscos conhecidos

- O giroscópio deriva; não há recentralizar (a posição dele é relativa, então o efeito é pequeno).
- Girar o corpo cansa: noites curtas (3 a 6 espantos).
- Sem fone, perde metade das pistas.

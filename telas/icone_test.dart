// Desenha o ícone do app com o próprio Manequim do jogo:
//   flutter test telas/icone_test.dart --update-goldens
//   dart run flutter_launcher_icons
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/ui/mannequin.dart';

const fundo = Color(0xFF0B0A09);

class _Icone extends CustomPainter {
  const _Icone({required this.background});
  final bool background;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final s = size.width;
    if (background) {
      canvas.drawRect(Offset.zero & size, Paint()..color = fundo);
    }
    // O feixe da lanterna batendo no rosto.
    canvas.drawCircle(
      c,
      s * 0.36,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x66FFE6B0), Color(0x22FFE6B0), Colors.transparent],
          stops: [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: s * 0.36)),
    );
    // Só a cabeça e os ombros, no centro (zona segura do ícone adaptativo).
    final h = s * 2.6;
    drawMannequin(
      canvas,
      Offset(c.dx, c.dy - s * 0.02 + h * 0.92),
      h,
      MannequinStyle.lit,
    );
  }

  @override
  bool shouldRepaint(_Icone old) => false;
}

void main() {
  Future<void> draw(WidgetTester tester, bool background, String file) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        child: CustomPaint(
          size: const Size(1024, 1024),
          painter: _Icone(background: background),
        ),
      ),
    );
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(file));
  }

  testWidgets('ícone', (t) => draw(t, true, '../assets/icon/icon.png'));
  testWidgets(
    'frente do ícone adaptativo',
    (t) => draw(t, false, '../assets/icon/foreground.png'),
  );
}

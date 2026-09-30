import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:corte/render.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Rect mapped(Matrix4 m, Size img) => MatrixUtils.transformRect(m, Offset.zero & img);

/// Imagen w×h donde cada píxel tiene un color distinto.
Future<(ui.Image, Uint8List)> patterned(int w, int h) {
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      px.setAll((y * w + x) * 4, [x * 6 % 256, y * 12 % 256, (x * y) % 256, 255]);
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future.then((img) => (img, px));
}

Future<(int, int, Uint8List)> decodePng(Uint8List png) async {
  final (img, _) = await decodeFull(png);
  final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return (img.width, img.height, raw!.buffer.asUint8List());
}

void main() {
  test('fitMatrix cover llena, contain entra centrada', () {
    const img = Size(400, 200), frame = Size(100, 100);
    expect(mapped(fitMatrix(img, frame, cover: true), img), const Rect.fromLTWH(-50, 0, 200, 100));
    expect(mapped(fitMatrix(img, frame, cover: false), img), const Rect.fromLTWH(0, 25, 100, 50));
  });

  test('slideSize: nativo si la foto alcanza, ampliado si no; nunca reduce', () {
    const img = Size(4000, 2000), frame = Size(100, 100);
    final cover = fitMatrix(img, frame, cover: true); // 2000 px de foto en el marco
    expect(slideSize(cover, frame, 1080, 1080, 1), (w: 2000, h: 2000, native: true));
    expect(slideSize(cover, frame, 1080, 1350, 1).w, 2000);
    final zoom = cover.clone()..scaleByDouble(10, 10, 1, 1); // 200 px de foto: se amplía
    expect(slideSize(zoom, frame, 1080, 1080, 1), (w: 1080, h: 1080, native: false));
  });

  testWidgets('export nativo = píxeles originales exactos, repartidos en slides', (tester) async {
    await tester.runAsync(() async {
      const frame = Size(100, 50); // 2 slides cuadrados; en el marco entran 40×20 px de foto
      // (ancho de foto, pan extra en px de pantalla, offset esperado en px de foto)
      for (final (iw, pan, off) in [(40, 0.0, 0), (60, -0.3, 10)]) {
        const ih = 20;
        final (img, src) = await patterned(iw, ih);
        final m = fitMatrix(Size(iw.toDouble(), 20), frame, cover: true)..storage[12] += pan;
        for (final bg in [null, Colors.white]) {
          final pngs = await renderSlides(
            img: img,
            blurSrc: img,
            m: m,
            frame: frame,
            fmtW: 10,
            fmtH: 10,
            count: 2,
            bg: bg,
          );
          expect(pngs.length, 2);
          for (var i = 0; i < 2; i++) {
            final (w, h, px) = await decodePng(pngs[i]);
            expect((w, h), (20, 20));
            for (var y = 0; y < h; y++) {
              for (var x = 0; x < w; x++) {
                final o = (y * w + x) * 4, so = (y * iw + x + off + i * 20) * 4;
                expect(px.sublist(o, o + 4), src.sublist(so, so + 4), reason: 'iw $iw slide $i px ($x,$y)');
              }
            }
          }
        }
      }
    });
  });

  testWidgets('rotar 90/180/270 = píxeles originales exactos (sin re-muestreo)', (tester) async {
    await tester.runAsync(() async {
      const frame = Size(100, 50); // la foto girada (40×20) llena justo 2 slides de 20×20
      // (giros, ancho y alto de la foto sin girar, píxel de origen para el píxel girado (x, y))
      final cases = <(int, int, int, (int, int) Function(int, int))>[
        (1, 20, 40, (x, y) => (y, 40 - 1 - x)),
        (2, 40, 20, (x, y) => (40 - 1 - x, 20 - 1 - y)),
        (3, 20, 40, (x, y) => (20 - 1 - y, x)),
      ];
      for (final (turns, ow, oh, from) in cases) {
        final (img, src) = await patterned(ow, oh);
        final pngs = await renderSlides(
          img: img,
          blurSrc: img,
          m: fitMatrix(const Size(40, 20), frame, cover: true),
          frame: frame,
          fmtW: 10,
          fmtH: 10,
          count: 2,
          turns: turns,
        );
        for (var i = 0; i < 2; i++) {
          final (w, h, px) = await decodePng(pngs[i]);
          expect((w, h), (20, 20));
          for (var y = 0; y < h; y++) {
            for (var x = 0; x < w; x++) {
              final (sx, sy) = from(x + i * 20, y);
              final o = (y * w + x) * 4, so = (sy * ow + sx) * 4;
              expect(px.sublist(o, o + 4), src.sublist(so, so + 4), reason: 'giro $turns slide $i px ($x,$y)');
            }
          }
        }
      }
      // La copia de pantalla girada también es exacta.
      final (img, src) = await patterned(3, 2);
      final rot = await rotate90(img);
      expect((rot.width, rot.height), (2, 3));
      final px = (await rot.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 2; x++) {
          final o = (y * 2 + x) * 4, so = ((2 - 1 - x) * 3 + y) * 4;
          expect(px.sublist(o, o + 4), src.sublist(so, so + 4));
        }
      }
    });
  });
}

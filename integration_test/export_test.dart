// Corre en el dispositivo (GPU real): flutter test integration_test -d <id>
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:corte/render.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// RGBA donde cada píxel codifica su (x, y).
Uint8List pattern(int w, int h) {
  final px = Uint8List(w * h * 4);
  var o = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      px[o++] = x & 255;
      px[o++] = y & 255;
      px[o++] = ((x >> 8) << 4 | (y >> 8)) & 255;
      px[o++] = 255;
    }
  }
  return px;
}

Future<ui.Image> fromPixels(Uint8List px, int w, int h) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// Verifica que cada slide sea una copia exacta (desplazada en px enteros) del original.
Future<void> expectExact(List<Uint8List> pngs, Uint8List src, int iw, Matrix4 m, Size frame, int fmtW, int fmtH) async {
  final (:w, :h, :native) = slideSize(m, frame, fmtW, fmtH, pngs.length);
  expect(native, isTrue);
  final k = w * pngs.length / frame.width;
  final offX = (-m.storage[12] * k).round(), offY = (-m.storage[13] * k).round();
  final s32 = src.buffer.asUint32List();
  for (var i = 0; i < pngs.length; i++) {
    final (img, _) = await decodeFull(pngs[i]);
    expect((img.width, img.height), (w, h));
    final o32 = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint32List();
    img.dispose();
    var bad = 0;
    for (var y = 0; y < h; y++) {
      final row = (y + offY) * iw + offX + i * w;
      for (var x = 0; x < w; x++) {
        if (o32[y * w + x] != s32[row + x]) bad++;
      }
    }
    expect(bad, 0, reason: 'slide $i: $bad píxeles distintos al original');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('12 MP PNG → carrusel 3 × IG vertical, píxeles exactos', (tester) async {
    await tester.runAsync(() async {
      const iw = 4000, ih = 3000;
      final src = pattern(iw, ih);
      final png = (await (await fromPixels(src, iw, ih)).toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final (full, reduced) = await decodeFull(png);
      expect(reduced, isFalse);
      expect((full.width, full.height), (iw, ih));
      final preview = await downscale(full, 2048);
      const frame = Size(360, 150); // 3 × 1080/1350
      // El ancho entra justo; pan vertical con fracción de píxel.
      final m = fitMatrix(const Size(4000, 3000), frame, cover: true)..storage[13] -= 11.81;
      for (final bg in [null, Colors.white]) {
        final sw = Stopwatch()..start();
        final pngs = await renderSlides(
            img: full, blurSrc: preview, m: m, frame: frame, fmtW: 1080, fmtH: 1350, count: 3, bg: bg);
        debugPrint('12MP carrusel (${bg == null ? 'blur' : 'color'}): ${sw.elapsedMilliseconds} ms, '
            '${pngs.map((p) => '${(p.length / 1e6).toStringAsFixed(1)} MB').join(', ')}');
        await expectExact(pngs, src, iw, m, frame, 1080, 1350);
      }
    });
  });

  testWidgets('50 MP (8160×6120) → IG cuadrado nativo, píxeles exactos', (tester) async {
    await tester.runAsync(() async {
      const iw = 8160, ih = 6120;
      final src = pattern(iw, ih);
      final full = await fromPixels(src, iw, ih);
      expect((full.width, full.height), (iw, ih));
      final preview = await downscale(full, 2048);
      const frame = Size(300, 300);
      final m = fitMatrix(const Size(8160, 6120), frame, cover: true)..storage[12] += 17.4;
      final sw = Stopwatch()..start();
      final pngs = await renderSlides(img: full, blurSrc: preview, m: m, frame: frame, fmtW: 1080, fmtH: 1080, count: 1);
      debugPrint('50MP IG cuadrado: ${sw.elapsedMilliseconds} ms, ${(pngs[0].length / 1e6).toStringAsFixed(1)} MB');
      await expectExact(pngs, src, iw, m, frame, 1080, 1080);
    });
  });

  testWidgets('JPEG alta calidad: misma resolución que PNG, fiel y más liviano', (tester) async {
    await tester.runAsync(() async {
      // Foto "realista": degradé + ruido leve de luminancia, como el de una cámara.
      // (Ruido de color independiente por píxel es el peor caso de cualquier JPEG y no representa fotos reales.)
      const iw = 4000, ih = 3000;
      final rnd = Random(7);
      final src = Uint8List(iw * ih * 4);
      for (var i = 0, p = 0; i < iw * ih; i++) {
        final x = i % iw, y = i ~/ iw, n = rnd.nextInt(13) - 6;
        src[p++] = (x * 200 ~/ iw + 30 + n).clamp(0, 255).toInt();
        src[p++] = (y * 180 ~/ ih + 40 + n).clamp(0, 255).toInt();
        src[p++] = (120 + 50 * sin(x / 90) + n).round().clamp(0, 255).toInt();
        src[p++] = 255;
      }
      final full = await fromPixels(src, iw, ih);
      const frame = Size(300, 375);
      final m = fitMatrix(const Size(4000, 3000), frame, cover: true);
      Future<(Uint8List, int)> run(bool jpeg) async {
        final sw = Stopwatch()..start();
        final out = await renderSlides(img: full, blurSrc: full, m: m, frame: frame, fmtW: 1080, fmtH: 1350, count: 1, jpeg: jpeg);
        return (out.single, sw.elapsedMilliseconds);
      }
      final (png, tPng) = await run(false);
      final (jpg, tJpg) = await run(true);
      expect(jpg.sublist(0, 2), [0xFF, 0xD8], reason: 'no es JPEG');
      final (a, _) = await decodeFull(png);
      final (b, _) = await decodeFull(jpg);
      expect((b.width, b.height), (a.width, a.height));
      expect((a.width, a.height), (2400, 3000)); // nativo, igual que PNG
      final pa = (await a.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      final pb = (await b.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      var sum = 0, se = 0.0;
      for (var i = 0; i < pa.length; i++) {
        if (i % 4 == 3) continue;
        final d = (pa[i] - pb[i]).abs();
        sum += d;
        se += d * d;
      }
      final n = pa.length * 3 / 4, mad = sum / n, psnr = 10 * log(255 * 255 / (se / n)) / ln10;
      debugPrint('PNG ${(png.length / 1e6).toStringAsFixed(1)} MB en $tPng ms | '
          'JPEG ${(jpg.length / 1e6).toStringAsFixed(1)} MB en $tJpg ms | '
          'dif media ${mad.toStringAsFixed(2)}, PSNR ${psnr.toStringAsFixed(1)} dB');
      expect(jpg.length, lessThan(png.length));
      expect(psnr, greaterThan(40), reason: 'calidad visual demasiado baja');
    });
  });

  testWidgets('zoom fuerte → se amplía al mínimo de la red (nunca menos)', (tester) async {
    await tester.runAsync(() async {
      final full = await fromPixels(pattern(1200, 900), 1200, 900);
      const frame = Size(200, 200);
      final m = fitMatrix(const Size(1200, 900), frame, cover: true)..scaleByDouble(4, 4, 1, 1);
      final pngs = await renderSlides(img: full, blurSrc: full, m: m, frame: frame, fmtW: 1080, fmtH: 1080, count: 1);
      final (img, _) = await decodeFull(pngs[0]);
      expect((img.width, img.height), (1080, 1080));
    });
  });
}

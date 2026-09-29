import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Tamaño mínimo recomendado por red. La salida nunca baja de esto, pero sí lo supera
/// cuando la foto tiene más resolución (ver [slideSize]).
const formats = [
  ('IG cuadrado', 1080, 1080),
  ('IG vertical', 1080, 1350),
  ('IG horizontal', 1080, 566),
  ('Story / Reels / TikTok', 1080, 1920),
  ('Facebook', 1200, 630),
  ('X', 1600, 900),
  ('LinkedIn', 1200, 627),
  ('YouTube miniatura', 1280, 720),
];

/// Blur del fondo relativo a la altura del lienzo, igual en preview y export.
double blurSigma(double height) => height * 0.04;

/// Matriz que centra la imagen en el marco: cover = lo llena (recorta), contain = entra entera.
Matrix4 fitMatrix(Size img, Size frame, {required bool cover}) {
  final sx = frame.width / img.width, sy = frame.height / img.height;
  final s = cover ? max(sx, sy) : min(sx, sy);
  final tx = (frame.width - img.width * s) / 2, ty = (frame.height - img.height * s) / 2;
  return Matrix4(s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
}

/// Decodifica a resolución completa, sin re-muestrear. `reduced` = el motor la achicó
/// porque supera el máximo de textura del GPU del dispositivo.
Future<(ui.Image, bool)> decodeFull(Uint8List bytes) async {
  final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buf);
  final codec = await desc.instantiateCodec();
  final img = (await codec.getNextFrame()).image;
  final reduced = max(img.width, img.height) < max(desc.width, desc.height);
  codec.dispose();
  desc.dispose();
  buf.dispose();
  return (img, reduced);
}

/// Copia liviana para editar en pantalla (el export usa siempre el original).
Future<ui.Image> downscale(ui.Image img, int maxSide) async {
  final r = maxSide / max(img.width, img.height);
  if (r >= 1) return img.clone();
  final w = (img.width * r).round(), h = (img.height * r).round();
  final rec = ui.PictureRecorder();
  Canvas(rec).drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final pic = rec.endRecording();
  final out = await pic.toImage(w, h);
  pic.dispose();
  return out;
}

const _jpegChannel = MethodChannel('corte/jpeg');

/// JPEG con el codificador del sistema (Android Bitmap / iOS ImageIO): offline, sin dependencias.
/// Misma resolución que el PNG; solo cambia la compresión.
Future<Uint8List> encodeJpeg(ui.Image img, {int quality = 95}) async {
  final px = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final jpg = await _jpegChannel.invokeMethod<Uint8List>('encode', {'w': img.width, 'h': img.height, 'px': px, 'q': quality});
  return jpg!;
}

/// Tamaño de cada slide exportado. `m` está en coordenadas de píxeles de la foto original.
/// Nativo: 1 px de la foto = 1 px de salida. Si eso queda por debajo del tamaño de la red,
/// se amplía hasta ese tamaño. Nunca se reduce la resolución original.
({int w, int h, bool native}) slideSize(Matrix4 m, Size frame, int fmtW, int fmtH, int count) {
  final nativeW = frame.width / count / m.storage[0];
  final native = nativeW >= fmtW;
  final w = native ? nativeW.round() : fmtW;
  return (w: w, h: (w * fmtH / fmtW).round(), native: native);
}

/// Renderiza los slides reproduciendo la matriz `m` del preview de tamaño `frame`.
/// `img` = foto original a resolución completa; `blurSrc` = copia liviana para el fondo.
/// `bg == null` => fondo de la foto desenfocada. PNG = sin pérdida; `jpeg` = calidad 95, más liviano.
Future<List<Uint8List>> renderSlides({
  required ui.Image img,
  required ui.Image blurSrc,
  required Matrix4 m,
  required Size frame,
  required int fmtW,
  required int fmtH,
  required int count,
  Color? bg,
  bool jpeg = false,
}) async {
  final (:w, :h, :native) = slideSize(m, frame, fmtW, fmtH, count);
  final total = Rect.fromLTWH(0, 0, (w * count).toDouble(), h.toDouble());
  final k = total.width / frame.width;
  // Nativo: escala exacta 1 y offset entero => se copian los píxeles originales sin re-muestreo.
  final scale = native ? 1.0 : k * m.storage[0];
  var dx = m.storage[12] * k, dy = m.storage[13] * k;
  if (native) {
    dx = dx.roundToDouble();
    dy = dy.roundToDouble();
  }
  final blurSize = Size(blurSrc.width.toDouble(), blurSrc.height.toDouble());
  final out = <Uint8List>[];
  for (var i = 0; i < count; i++) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..translate(-i * w.toDouble(), 0);
    if (bg != null) {
      c.drawRect(total, Paint()..color = bg);
    } else {
      final fit = applyBoxFit(BoxFit.cover, blurSize, total.size);
      final s = blurSigma(total.height);
      c.drawImageRect(
        blurSrc,
        Alignment.center.inscribe(fit.source, Offset.zero & blurSize),
        total,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: s, sigmaY: s, tileMode: TileMode.clamp),
      );
    }
    c
      ..translate(dx, dy)
      ..scale(scale)
      ..drawImage(img, Offset.zero, Paint()..filterQuality = native ? FilterQuality.none : FilterQuality.high);
    final pic = rec.endRecording();
    final image = await pic.toImage(w, h);
    try {
      out.add(jpeg
          ? await encodeJpeg(image)
          : (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
    } finally {
      pic.dispose();
      image.dispose();
    }
  }
  return out;
}

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const cream = Color(0xFFF6EFE4);
const sand = Color(0xFFE6D5BE);
const terracotta = Color(0xFFC0673E);
const rose = Color(0xFFD9A69B);
const mustard = Color(0xFFD9A441);
const sage = Color(0xFF8C9A6E);
const espresso = Color(0xFF3B2A22);
const night = Color(0xFF2A211C);

// Tonos "tinta" para texto y rellenos: pasan WCAG AA (≥ 4.5:1 con texto crema / sobre crema).
// Los pastel de arriba quedan para lo decorativo (arcoíris, sol, swatches).
const clay = Color(0xFFA0502B); // crema sobre arcilla 5.0:1
const moss = Color(0xFF5E6B44); // crema sobre musgo 5.0:1
const ochre = Color(0xFF9C701A); // íconos sobre crema 3.9:1

const serif = 'DMSerif';

ThemeData bohoTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: terracotta, brightness: b).copyWith(
    primary: clay,
    onPrimary: cream,
    // Íconos de estado: en claro, tonos profundos; en oscuro, los pastel ya contrastan (≥ 5:1).
    secondary: dark ? sage : moss,
    tertiary: dark ? mustard : ochre,
    secondaryContainer: dark ? const Color(0xFF4A3A31) : const Color(0xFFF0DCD2),
    onSecondaryContainer: dark ? cream : espresso,
    surface: dark ? night : cream,
    onSurface: dark ? cream : espresso,
    // 75 % de opacidad: texto secundario ≥ 5.6:1 en ambos modos.
    onSurfaceVariant: (dark ? cream : espresso).withValues(alpha: .75),
    surfaceContainer: dark ? const Color(0xFF362A23) : const Color(0xFFEFE4D4),
    // Bordes de chips/segmentos ≥ 3:1 contra el fondo.
    outline: dark ? const Color(0xFF8A7564) : const Color(0xFF927859),
  );
  const pill = StadiumBorder();
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      // Íconos de la barra de estado oscuros sobre crema, claros sobre noche.
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 30, color: scheme.onSurface),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      showCheckmark: false,
      side: BorderSide(color: scheme.outline),
      backgroundColor: scheme.surface,
      selectedColor: clay,
      labelStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurface),
      secondaryLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: cream),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, letterSpacing: .3),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: moss,
        selectedForegroundColor: cream,
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      // Invertido respecto del fondo para que el aviso resalte en ambos modos.
      backgroundColor: dark ? cream : espresso,
      contentTextStyle: TextStyle(fontFamily: 'Poppins', color: dark ? espresso : cream, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

/// Arcoíris boho: bandas concéntricas, de afuera hacia adentro.
void paintRainbow(Canvas c, Offset base, double radius, {double opacity = 1}) {
  const bands = [terracotta, rose, mustard, sage];
  final w = radius / (bands.length + 1.5);
  for (var i = 0; i < bands.length; i++) {
    final r = radius - w * (i + .5);
    c.drawArc(
      Rect.fromCircle(center: base, radius: r),
      pi,
      pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .82
        ..color = bands[i].withValues(alpha: opacity),
    );
  }
}

/// Sol con rayos cortos.
void paintSun(Canvas c, Offset center, double r, {double opacity = 1}) {
  final p = Paint()..color = mustard.withValues(alpha: opacity);
  c.drawCircle(center, r, p);
  p
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * .12
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 12; i++) {
    final a = i * pi / 6, d = Offset(cos(a), sin(a));
    c.drawLine(center + d * r * 1.35, center + d * r * 1.7, p);
  }
}

/// Fondo decorativo estático (se pinta una vez; va dentro de un RepaintBoundary).
class Backdrop extends CustomPainter {
  const Backdrop(this.dark);
  final bool dark;

  @override
  void paint(Canvas c, Size s) {
    final o = dark ? .10 : .16;
    paintSun(c, Offset(s.width * .92, s.height * .06), s.width * .12, opacity: o);
    paintRainbow(c, Offset(0, s.height), s.width * .55, opacity: o);
    final dot = Paint()..color = terracotta.withValues(alpha: o);
    for (final (x, y) in const [(.12, .18), (.8, .35), (.65, .82), (.3, .55), (.9, .7)]) {
      c.drawCircle(Offset(s.width * x, s.height * y), 3, dot);
    }
  }

  @override
  bool shouldRepaint(Backdrop old) => old.dark != dark;
}

class Rainbow extends CustomPainter {
  const Rainbow();
  @override
  void paint(Canvas c, Size s) {
    paintSun(c, Offset(s.width / 2, s.height * .9), s.height * .1);
    paintRainbow(c, Offset(s.width / 2, s.height), s.height);
  }

  @override
  bool shouldRepaint(Rainbow old) => false;
}

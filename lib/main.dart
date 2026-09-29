import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

import 'boho.dart';
import 'render.dart';

void main() => runApp(MaterialApp(
      title: 'Corte',
      debugShowCheckedModeBanner: false,
      theme: bohoTheme(Brightness.light),
      darkTheme: bohoTheme(Brightness.dark),
      home: const Editor(),
    ));

const swatches = [cream, Colors.white, sand, rose, terracotta, mustard, sage, espresso];

class Editor extends StatefulWidget {
  const Editor({super.key});
  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> with SingleTickerProviderStateMixin {
  Uint8List? _bytes; // archivo original, intacto
  ui.Image? _img; // copia liviana solo para pantalla
  Size _full = Size.zero; // resolución original en px
  int _fmt = 1;
  bool _carousel = false;
  int _slides = 3;
  bool _blur = true;
  bool _jpeg = false; // PNG sin pérdida por defecto
  Color _color = cream;
  bool _saving = false;
  Size? _frame;
  var _ctrl = TransformationController();
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  Matrix4Tween? _tween;

  int get _count => _carousel ? _slides : 1;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final t = _tween;
      if (t != null) _ctrl.value = t.transform(Curves.easeOutCubic.transform(_anim.value));
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _ctrl.dispose();
    _img?.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final msg = ScaffoldMessenger.of(context);
    try {
      // Sin maxWidth/imageQuality: el picker devuelve el archivo original, sin re-comprimir ni achicar.
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final (full, reduced) = await decodeFull(bytes);
      final preview = await downscale(full, 2048);
      final size = Size(full.width.toDouble(), full.height.toDouble());
      full.dispose();
      if (reduced) {
        msg.showSnackBar(SnackBar(
            content: Text('La foto supera el máximo de este dispositivo; se usará a ${size.width.toInt()} × ${size.height.toInt()} px')));
      }
      setState(() {
        _img?.dispose();
        _img = preview;
        _bytes = bytes;
        _full = size;
        _frame = null; // fuerza encuadre inicial
      });
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('No se pudo abrir la foto: $e')));
    }
  }

  void _fit(bool cover) {
    HapticFeedback.selectionClick();
    _tween = Matrix4Tween(begin: _ctrl.value.clone(), end: fitMatrix(_full, _frame!, cover: cover));
    _anim.forward(from: 0);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final msg = ScaffoldMessenger.of(context);
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) throw 'Sin permiso para la galería';
      final (_, w, h) = formats[_fmt];
      // Se vuelve a decodificar el original: el export nunca usa la copia de pantalla.
      final (full, _) = await decodeFull(_bytes!);
      try {
        final files = await renderSlides(
          img: full,
          blurSrc: _img!,
          m: _ctrl.value,
          frame: _frame!,
          fmtW: w,
          fmtH: h,
          count: _count,
          bg: _blur ? null : _color,
          jpeg: _jpeg,
        );
        final ts = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < files.length; i++) {
          await Gal.putImageBytes(files[i], name: 'corte_${ts}_${i + 1}');
        }
        HapticFeedback.mediumImpact();
        final kind = _jpeg ? 'JPEG' : 'PNG';
        msg.showSnackBar(SnackBar(
            content: Text(files.length == 1 ? '✿  Imagen guardada ($kind)' : '✿  ${files.length} imágenes guardadas ($kind)')));
      } finally {
        full.dispose();
      }
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Cambio de formato/slides => nuevo tamaño de marco => reencuadre cover.
  void _relayout(VoidCallback f) {
    HapticFeedback.selectionClick();
    setState(() {
      f();
      _frame = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Corte'),
        actions: [
          if (img != null) IconButton(tooltip: 'Cambiar foto', onPressed: _pick, icon: const Icon(Icons.photo_library_outlined)),
          if (img != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cream))
                    : const Icon(Icons.download_rounded),
                label: const Text('Guardar'),
              ),
            ),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        RepaintBoundary(child: CustomPaint(painter: Backdrop(dark))),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOutCubic,
          child: img == null
              ? _home()
              : SafeArea(
                  key: const ValueKey('editor'),
                  child: Column(children: [_formatBar(), _carouselBar(), Expanded(child: _canvas(img)), _bottomBar()]),
                ),
        ),
      ]),
    );
  }

  Widget _home() {
    final t = Theme.of(context);
    return Center(
      key: const ValueKey('home'),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const RepaintBoundary(child: CustomPaint(size: Size(220, 110), painter: Rainbow())),
            const SizedBox(height: 28),
            Text('Cortá, ampliá\ny armá carruseles',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: serif, fontSize: 34, height: 1.1, color: t.colorScheme.onSurface)),
            const SizedBox(height: 12),
            Text('Tus fotos, a medida de cada red.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Elegir foto'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _formatBar() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          for (var i = 0; i < formats.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: _ratioIcon(formats[i].$2, formats[i].$3, _fmt == i),
                label: Text(formats[i].$1),
                tooltip: '${formats[i].$2} × ${formats[i].$3}',
                selected: _fmt == i,
                onSelected: (_) => _relayout(() => _fmt = i),
              ),
            ),
        ]),
      );

  // Mini rectángulo con la proporción del formato.
  Widget _ratioIcon(int w, int h, bool selected) {
    final m = w > h ? w : h;
    return Center(
      child: Container(
        width: 16 * w / m,
        height: 16 * h / m,
        decoration: BoxDecoration(
          border: Border.all(color: selected ? cream : terracotta, width: 1.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _carouselBar() {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Icon(Icons.view_carousel_outlined, size: 20, color: t.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        const Text('Carrusel', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        Transform.scale(
          scale: .85,
          child: Switch(value: _carousel, onChanged: (v) => _relayout(() => _carousel = v)),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: _carousel
              ? Row(children: [
                  IconButton.outlined(
                    visualDensity: VisualDensity.compact,
                    onPressed: _slides > 2 ? () => _relayout(() => _slides--) : null,
                    icon: const Icon(Icons.remove, size: 18),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text('$_slides', textAlign: TextAlign.center, style: const TextStyle(fontFamily: serif, fontSize: 22)),
                  ),
                  IconButton.outlined(
                    visualDensity: VisualDensity.compact,
                    onPressed: _slides < 10 ? () => _relayout(() => _slides++) : null,
                    icon: const Icon(Icons.add, size: 18),
                  ),
                ])
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Widget _canvas(ui.Image img) {
    final (_, w, h) = formats[_fmt];
    final ratio = w * _count / h;
    // El marco se calcula acá (no con un LayoutBuilder interno) para que el controller nuevo
    // exista antes de construir todo lo que lo escucha (marco + etiqueta de resolución).
    return LayoutBuilder(builder: (context, box) {
      const pad = EdgeInsets.fromLTRB(20, 12, 20, 8), mat = 6.0, labelH = 30.0;
      final aw = box.maxWidth - pad.horizontal - mat * 2, ah = box.maxHeight - pad.vertical - mat * 2 - labelH;
      // Proporción exacta (sin redondear) para que la salida nativa coincida con la foto al píxel.
      final fw = aw / ah > ratio ? ah * ratio : aw;
      final frame = Size(fw, fw / ratio);
      if (frame != _frame) {
        // Controller nuevo con el encuadre inicial: evita notificar durante el layout.
        final old = _ctrl;
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
        _anim.stop();
        _ctrl = TransformationController(fitMatrix(_full, frame, cover: true));
        _frame = frame;
      }
      // Zoom mínimo = "Ajustar": achicar más solo agregaría fondo (y un lienzo gigante al exportar).
      final minScale = fitMatrix(_full, frame, cover: false).storage[0];
      final sigma = blurSigma(frame.height);
      return Padding(
        padding: pad,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Paspartú tipo foto impresa; el área útil (lo que se exporta) es el marco de adentro.
          Container(
            padding: const EdgeInsets.all(mat),
            decoration: BoxDecoration(
              color: cream,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: espresso.withValues(alpha: .22), blurRadius: 24, offset: const Offset(0, 12))],
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: SizedBox.fromSize(
                size: frame,
                child: ClipRect(
                  child: Stack(children: [
                    // Fondo aislado: pan/zoom no vuelve a pintar el blur.
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _blur
                              ? ImageFiltered(
                                  key: const ValueKey('blur'),
                                  imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
                                  child: RawImage(image: img, fit: BoxFit.cover, width: frame.width, height: frame.height),
                                )
                              : ColoredBox(key: ValueKey(_color), color: _color, child: const SizedBox.expand()),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: InteractiveViewer(
                          transformationController: _ctrl,
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          minScale: minScale,
                          maxScale: minScale * 100,
                          onInteractionStart: (_) => _anim.stop(),
                          // Se dibuja la copia liviana ocupando el tamaño original:
                          // la matriz queda en píxeles de la foto original.
                          child: RawImage(
                            image: img,
                            width: _full.width,
                            height: _full.height,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                    if (_count > 1) IgnorePointer(child: _slideGuides(frame)),
                  ]),
                ),
              ),
            ),
          ),
          SizedBox(height: labelH, child: Center(child: _resolutionLabel(frame, w, h))),
        ]),
      );
    });
  }

  // Resolución real de salida, en vivo mientras se hace zoom.
  Widget _resolutionLabel(Size frame, int fmtW, int fmtH) => ValueListenableBuilder<Matrix4>(
        valueListenable: _ctrl,
        builder: (context, m, _) {
          final (:w, :h, :native) = slideSize(m, frame, fmtW, fmtH, _count);
          final scheme = Theme.of(context).colorScheme;
          final slides = _count > 1 ? '$_count × ' : '';
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(native ? Icons.verified_outlined : Icons.open_in_full_rounded, size: 16, color: native ? scheme.secondary : scheme.tertiary),
            const SizedBox(width: 6),
            Text(
              '$slides$w × $h px · ${native ? 'resolución original' : 'ampliada al mínimo de la red'}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ]);
        },
      );

  Widget _slideGuides(Size frame) => Stack(children: [
        for (var i = 0; i < _count; i++) ...[
          if (i > 0)
            Positioned(
              left: frame.width * i / _count - .75,
              top: 0,
              bottom: 0,
              width: 1.5,
              child: ColoredBox(color: cream.withValues(alpha: .85)),
            ),
          Positioned(
            left: frame.width * i / _count + 6,
            top: 6,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: espresso.withValues(alpha: .8), shape: BoxShape.circle),
              child: Text('${i + 1}', style: const TextStyle(fontFamily: serif, color: cream, fontSize: 13)),
            ),
          ),
        ],
      ]);

  Widget _bottomBar() {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => _fit(true),
              icon: const Icon(Icons.crop_rounded),
              label: const Text('Rellenar'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => _fit(false),
              icon: const Icon(Icons.fit_screen_rounded),
              label: const Text('Ajustar'),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _label('Fondo'),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Blur'), icon: Icon(Icons.blur_on)),
              ButtonSegment(value: false, label: Text('Color'), icon: Icon(Icons.palette_outlined)),
            ],
            selected: {_blur},
            onSelectionChanged: (s) {
              HapticFeedback.selectionClick();
              setState(() => _blur = s.first);
            },
          ),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: _blur
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [for (final c in swatches) _swatch(c)]),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _label('Archivo'),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('PNG')),
              ButtonSegment(value: true, label: Text('JPEG')),
            ],
            selected: {_jpeg},
            onSelectionChanged: (s) {
              HapticFeedback.selectionClick();
              setState(() => _jpeg = s.first);
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _jpeg ? 'Alta calidad (95), mucho más liviano' : 'Sin pérdida, pesa más',
              style: TextStyle(fontSize: 12, height: 1.25, color: t.colorScheme.onSurfaceVariant),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _label(String text) => SizedBox(
        width: 82,
        child: Text(text, style: TextStyle(fontFamily: serif, fontSize: 20, color: Theme.of(context).colorScheme.onSurface)),
      );

  Widget _swatch(Color c) {
    final sel = _color == c;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _color = c);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        width: sel ? 38 : 32,
        height: sel ? 38 : 32,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: sel ? clay : Theme.of(context).colorScheme.outline, width: sel ? 3 : 1),
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/template_def.dart';
import 'editor_controller.dart';

/// لوحة التصميم: تعرض القالب بمقاسه الأصلي مصغّراً للشاشة، وتحوّل اللمس
/// إلى إحداثيات القالب.
class EditorCanvas extends StatefulWidget {
  const EditorCanvas({super.key, required this.controller, required this.boundaryKey, this.onEditText});

  final EditorController controller;
  final GlobalKey boundaryKey;
  final void Function(TextLayer layer)? onEditText;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

enum _Target { none, layer, background }

class _EditorCanvasState extends State<EditorCanvas> {
  EditorController get c => widget.controller;

  _Target _target = _Target.none;
  Offset _startFocal = Offset.zero;
  Offset _startPos = Offset.zero;
  double _startFont = 0;
  double _startScale = 1;
  double _s = 1;

  Offset _toTemplate(Offset local) => local / _s;

  void _onScaleStart(ScaleStartDetails d) {
    final p = _toTemplate(d.localFocalPoint);
    final sel = c.selectedLayer;
    int? hit = sel != null && EditorController.rectOf(sel).inflate(c.unit * 0.02).contains(p)
        ? c.selected
        : c.layerAt(p);
    _startFocal = d.localFocalPoint;
    if (hit != null) {
      _target = _Target.layer;
      if (hit != c.selected) c.select(hit);
      final l = c.layers[hit];
      _startPos = Offset(l.x, l.y);
      _startFont = l.fontSize;
    } else if (c.backgroundPath != null) {
      _target = _Target.background;
      if (c.selected != -1) c.select(-1);
      _startPos = c.bgOffset;
      _startScale = c.bgScale;
    } else {
      _target = _Target.none;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final delta = (d.localFocalPoint - _startFocal) / _s;
    switch (_target) {
      case _Target.layer:
        final l = c.selectedLayer;
        if (l == null) return;
        var x = _startPos.dx + delta.dx;
        final centered = (c.size.width - l.width) / 2;
        c.showCenterGuide = (x - centered).abs() < c.unit * 0.012;
        if (c.showCenterGuide) x = centered;
        l
          ..x = x
          ..y = _startPos.dy + delta.dy;
        if (d.pointerCount > 1) l.fontSize = (_startFont * d.scale).clamp(c.unit * 0.008, c.unit * 0.3);
        c.update();
      case _Target.background:
        c.bgOffset = _startPos + delta;
        if (d.pointerCount > 1) c.bgScale = (_startScale * d.scale).clamp(0.2, 8.0);
        c.update();
      case _Target.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _target = _Target.none;
    if (c.showCenterGuide) {
      c.showCenterGuide = false;
      c.update();
    }
  }

  void _onTapUp(TapUpDetails d) {
    final hit = c.layerAt(_toTemplate(d.localPosition));
    c.select(hit ?? (c.backgroundPath != null ? -1 : null));
  }

  void _onDoubleTapDown(TapDownDetails d) {
    final hit = c.layerAt(_toTemplate(d.localPosition));
    if (hit != null) {
      c.select(hit);
      widget.onEditText?.call(c.layers[hit]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final t = c.template;
        if (t == null) return const SizedBox.shrink();
        final size = c.size;
        return LayoutBuilder(
          builder: (context, box) {
            _s = math.min(box.maxWidth / size.width, box.maxHeight / size.height);
            return Center(
              child: SizedBox(
                width: size.width * _s,
                height: size.height * _s,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  onTapUp: _onTapUp,
                  onDoubleTapDown: _onDoubleTapDown,
                  onDoubleTap: () {},
                  child: FittedBox(
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          RepaintBoundary(
                            key: widget.boundaryKey,
                            child: Composition(controller: c),
                          ),
                          ..._overlay(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// إطار التحديد وخط التوسيط (خارج منطقة التصدير).
  List<Widget> _overlay() {
    final stroke = 2.5 / _s;
    final color = Theme.of(context).colorScheme.primary;
    return [
      if (c.selectedLayer != null)
        Positioned.fromRect(
          rect: EditorController.rectOf(c.selectedLayer!),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.lightBlueAccent, width: stroke),
              ),
            ),
          ),
        ),
      if (c.selected == -1)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: stroke * 2),
              ),
            ),
          ),
        ),
      if (c.showCenterGuide)
        Positioned(
          left: c.size.width / 2 - stroke / 2,
          top: 0,
          bottom: 0,
          width: stroke,
          child: const IgnorePointer(child: ColoredBox(color: Colors.pinkAccent)),
        ),
    ];
  }
}

/// ما يُصدَّر فعلاً: الخلفية ثم القالب ثم النصوص.
class Composition extends StatelessWidget {
  const Composition({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = c.template!;
    return SizedBox(
      width: c.size.width,
      height: c.size.height,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: c.bgColor)),
            if (c.backgroundPath != null)
              Positioned.fill(
                child: Transform.translate(
                  offset: c.bgOffset,
                  child: Transform.scale(
                    scale: c.bgScale,
                    child: Image.file(
                      File(c.backgroundPath!),
                      fit: c.bgContain ? BoxFit.contain : BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: Image(image: t.image, fit: BoxFit.fill, filterQuality: FilterQuality.high),
            ),
            for (final l in c.layers)
              Positioned(
                left: l.x,
                top: l.y,
                width: l.width,
                child: LayerView(layer: l),
              ),
          ],
        ),
      ),
    );
  }
}

class LayerView extends StatelessWidget {
  const LayerView({super.key, required this.layer});

  final TextLayer layer;

  @override
  Widget build(BuildContext context) {
    final l = layer;
    final border = l.fontSize * 0.085;
    return Container(
      padding: EditorController.padding(l),
      decoration: switch (l.box) {
        BoxStyle.none => null,
        BoxStyle.outline => BoxDecoration(
          border: Border.all(color: l.boxColor, width: border),
        ),
        BoxStyle.filled => BoxDecoration(color: l.boxColor, borderRadius: BorderRadius.circular(l.fontSize * 0.15)),
      },
      child: Text(
        l.text,
        textAlign: l.align,
        textDirection: EditorController.directionOf(l.text),
        textScaler: TextScaler.noScaling,
        style: EditorController.style(l),
      ),
    );
  }
}

/// تصدير اللوحة بالمقاس الأصلي للقالب (بكسل لبكسل).
Future<Uint8List?> exportPng(GlobalKey key) async {
  final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}

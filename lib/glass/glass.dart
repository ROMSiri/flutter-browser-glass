import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'glass_theme.dart';
import 'spring.dart';

/// Матовое стекло: размытие фона + полупрозрачная заливка.
/// Размытие и заливка обрезаются одним и тем же скруглением,
/// поэтому блюр не выпирает за край.
///
/// Важно: не оборачивайте GlassBox в Opacity / ImageFiltered — внутри них
/// размытию нечего размывать. Для исчезновения используйте [fade].
class GlassBox extends StatelessWidget {
  final Widget? child;
  final BorderRadius borderRadius;
  final bool circle;
  final double blur;

  /// 1 — стекло полностью видно, 0 — стекла нет (и блюра тоже).
  final double fade;
  final EdgeInsetsGeometry? padding;
  final Color? tint;

  const GlassBox({
    super.key,
    this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.circle = false,
    this.blur = 12,
    this.fade = 1,
    this.padding,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    final f = fade.clamp(0.0, 1.0);
    final base = tint ?? c.tint;
    final fill = base.withOpacity(base.opacity * f);
    final stroke = c.stroke.withOpacity(c.stroke.opacity * f);

    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : borderRadius,
        border: Border.all(color: stroke, width: 1),
      ),
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );

    final sigma = blur * f;
    if (sigma > 0.05) {
      box = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: box,
      );
    }

    return circle
        ? ClipOval(child: box)
        : ClipRRect(borderRadius: borderRadius, child: box);
  }
}

/// Цвет, который плавно загорается синим, пока палец над элементом,
/// и плавно гаснет, когда палец уходит.
class HotColor extends StatelessWidget {
  final bool hot;
  final Color color;
  final Widget child;

  const HotColor({
    super.key,
    required this.hot,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: hot ? GlassColors.active : color),
      duration: Duration(milliseconds: hot ? 250 : 450),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return IconTheme.merge(
          data: IconThemeData(color: value),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: value),
            child: child!,
          ),
        );
      },
      child: child,
    );
  }
}

/// Круглая (или капсульная) стеклянная кнопка, которая сама по себе:
/// при зажатии чуть увеличивается, тянется с усилием и пружинкой
/// возвращается; под пальцем синеет; срабатывает, если отпустить на ней.
class StretchyGlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double width;
  final double height;
  final bool enabled;

  const StretchyGlassButton({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.width = 48,
    this.height = 48,
    this.enabled = true,
  });

  @override
  State<StretchyGlassButton> createState() => _StretchyGlassButtonState();
}

class _StretchyGlassButtonState extends State<StretchyGlassButton>
    with SingleTickerProviderStateMixin {
  late final StretchController _stretch;
  Offset _down = Offset.zero;
  bool _pressed = false;
  bool _hot = false;
  bool _longPressed = false;
  DateTime _downAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    final round = (widget.width - widget.height).abs() < 1;
    _stretch = StretchController(
      vsync: this,
      growTo: round ? 1.04 : 1.015,
    );
  }

  @override
  void dispose() {
    _stretch.dispose();
    super.dispose();
  }

  bool _inside(Offset local) =>
      local.dx >= -6 &&
      local.dy >= -6 &&
      local.dx <= widget.width + 6 &&
      local.dy <= widget.height + 6;

  void _checkLongPress() {
    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted || !_pressed || _longPressed) return;
      if (DateTime.now().difference(_downAt).inMilliseconds < 440) return;
      if (widget.onLongPress != null && _hot) {
        _longPressed = true;
        widget.onLongPress!();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    final round = (widget.width - widget.height).abs() < 1;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: widget.enabled
          ? (e) {
              _down = e.localPosition;
              _downAt = DateTime.now();
              _pressed = true;
              _longPressed = false;
              _stretch.press();
              setState(() => _hot = true);
              _checkLongPress();
            }
          : null,
      onPointerMove: widget.enabled
          ? (e) {
              if (!_pressed) return;
              _stretch.pull(e.localPosition.dx - _down.dx,
                  e.localPosition.dy - _down.dy);
              final inside = _inside(e.localPosition);
              if (inside != _hot) setState(() => _hot = inside);
            }
          : null,
      onPointerUp: widget.enabled
          ? (e) {
              if (!_pressed) return;
              _pressed = false;
              _stretch.release();
              final ok = _inside(e.localPosition) && !_longPressed;
              setState(() => _hot = false);
              if (ok) widget.onTap?.call();
            }
          : null,
      onPointerCancel: widget.enabled
          ? (e) {
              _pressed = false;
              _stretch.release();
              setState(() => _hot = false);
            }
          : null,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _stretch,
          builder: (context, child) {
            final d = _stretch.deform;
            final sx = round
                ? d.scaleX
                : d.grow * (1 + d.side * 1.1 / widget.width -
                    d.vert * 0.5 / widget.width);
            final sy = round
                ? d.scaleY
                : d.grow * (1 + d.vert * 0.45 / widget.height -
                    d.side * 0.12 / widget.height);
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translate(d.tx, d.ty)
                ..scale(sx, sy),
              child: child,
            );
          },
          child: GlassBox(
            circle: round,
            child: Center(
              child: Opacity(
                opacity: widget.enabled ? 1 : 0.35,
                child: HotColor(
                  hot: _hot,
                  color: c.text,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Значок вкладок: скруглённый квадрат с числом вкладок внутри.
class TabsCountIcon extends StatelessWidget {
  final int count;
  final double size;

  const TabsCountIcon({super.key, required this.count, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? GlassColors.of(context).text;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? ':D' : '$count',
        style: TextStyle(
          color: color,
          fontSize: size * 0.48,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

double lerpD(double a, double b, double t) => a + (b - a) * t;

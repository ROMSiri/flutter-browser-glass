import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';
import 'glass_theme.dart';
import 'spring.dart';

/// Пункт меню.
class GlassMenuEntry {
  final IconData? icon;
  final String label;
  final VoidCallback? onSelected;
  final bool? checked; // null — без галочки
  final bool enabled;
  final bool isDivider;

  const GlassMenuEntry({
    this.icon,
    required this.label,
    this.onSelected,
    this.checked,
    this.enabled = true,
  }) : isDivider = false;

  const GlassMenuEntry.divider()
      : icon = null,
        label = '',
        onSelected = null,
        checked = null,
        enabled = false,
        isDivider = true;
}

/// Быстрое действие в верхнем ряду меню (назад, вперёд, обновить…).
class GlassMenuQuickAction {
  final IconData icon;
  final VoidCallback? onSelected;
  final bool active; // подсвечено синим (например, страница в избранном)
  final bool closeOnSelect;
  final bool enabled;

  const GlassMenuQuickAction({
    required this.icon,
    this.onSelected,
    this.active = false,
    this.closeOnSelect = true,
    this.enabled = true,
  });
}

/// Стеклянная панель меню, которая вырастает из кнопки с пружинкой
/// и пружинкой уходит обратно.
///
/// Ставится в Stack на весь экран (Positioned.fill) ниже самой кнопки.
/// Пункт под пальцем загорается синим, отпустил на пункте — выбран.
/// Панель можно зажать и потянуть — она тянется туго и пружинкой возвращается.
class GlassPopupMenu extends StatefulWidget {
  final bool open;
  final Rect anchor; // где кнопка (в координатах этого Stack)
  final bool alignRight;
  final List<GlassMenuEntry> entries;
  final List<GlassMenuQuickAction> quickActions;
  final VoidCallback onClose;
  final double width;

  const GlassPopupMenu({
    super.key,
    required this.open,
    required this.anchor,
    required this.entries,
    required this.onClose,
    this.quickActions = const [],
    this.alignRight = false,
    this.width = 264,
  });

  @override
  State<GlassPopupMenu> createState() => _GlassPopupMenuState();
}

class _GlassPopupMenuState extends State<GlassPopupMenu>
    with TickerProviderStateMixin {
  static const double _pad = 8;
  static const double _quickH = 52;
  static const double _dividerH = 9;

  late final SpringAnimator _open;
  late final StretchController _stretch;

  int? _hotEntry;
  int? _hotQuick;
  bool _pressed = false;
  bool _selecting = false;
  Offset _down = Offset.zero;

  // геометрия последней отрисовки — для определения пункта под пальцем
  double _itemH = 44;
  double _panelH = 0;

  @override
  void initState() {
    super.initState();
    _open = SpringAnimator(
      vsync: this,
      params: (t) => t > 0.5 ? Springs.menuOpen : Springs.menuClose,
      clampBelowZero: true,
    );
    // панель тянется тяжело: предел меньше, резина туже
    _stretch = StretchController(
        vsync: this, radius: 8, tight: 0.15, growTo: 1.015, liftMax: 0);
    if (widget.open) _open.animateTo(1);
  }

  @override
  void didUpdateWidget(GlassPopupMenu old) {
    super.didUpdateWidget(old);
    if (old.open != widget.open) {
      if (widget.open) {
        _selecting = false;
        _hotEntry = null;
        _hotQuick = null;
      }
      _open.animateTo(widget.open ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _open.dispose();
    _stretch.dispose();
    super.dispose();
  }

  int get _visibleEntries => widget.entries.where((e) => !e.isDivider).length;

  int get _dividers => widget.entries.where((e) => e.isDivider).length;

  double get _fixedH =>
      _pad * 2 +
      (widget.quickActions.isNotEmpty ? _quickH + _dividerH : 0) +
      _dividers * _dividerH;

  /// Что под пальцем: быстрое действие или пункт.
  ({int? quick, int? entry}) _hitTest(Offset p) {
    var y = p.dy - _pad;
    final x = p.dx;
    if (p.dy < 0 || p.dy > _panelH || x < 0 || x > widget.width) {
      return (quick: null, entry: null);
    }
    if (widget.quickActions.isNotEmpty) {
      if (y < _quickH) {
        final cellW = (widget.width - _pad * 2) / widget.quickActions.length;
        final i = ((x - _pad) / cellW).floor();
        if (i < 0 || i >= widget.quickActions.length) {
          return (quick: null, entry: null);
        }
        return (quick: i, entry: null);
      }
      y -= _quickH + _dividerH;
    }
    for (var i = 0; i < widget.entries.length; i++) {
      final e = widget.entries[i];
      final h = e.isDivider ? _dividerH : _itemH;
      if (y >= 0 && y < h) {
        return (quick: null, entry: e.isDivider ? null : i);
      }
      y -= h;
    }
    return (quick: null, entry: null);
  }

  void _setHot(({int? quick, int? entry}) hit) {
    if (_selecting) return;
    if (hit.quick != _hotQuick || hit.entry != _hotEntry) {
      setState(() {
        _hotQuick = hit.quick;
        _hotEntry = hit.entry;
      });
    }
  }

  void _onDown(PointerDownEvent e) {
    if (!widget.open) return;
    _pressed = true;
    _down = e.localPosition;
    _stretch.press();
    _setHot(_hitTest(e.localPosition));
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pressed) return;
    _stretch.pull(e.localPosition.dx - _down.dx, e.localPosition.dy - _down.dy);
    _setHot(_hitTest(e.localPosition));
  }

  void _onUp(PointerUpEvent e) {
    if (!_pressed) return;
    _pressed = false;
    _stretch.release();
    final hit = _hitTest(e.localPosition);

    if (hit.entry != null) {
      final entry = widget.entries[hit.entry!];
      if (!entry.enabled) {
        setState(() => _hotEntry = null);
        return;
      }
      // синий остаётся, пока панель закрывается
      _selecting = true;
      HapticFeedback.selectionClick();
      Future.delayed(const Duration(milliseconds: 120), () {
        widget.onClose();
        entry.onSelected?.call();
      });
      return;
    }

    if (hit.quick != null) {
      final q = widget.quickActions[hit.quick!];
      if (!q.enabled) {
        setState(() => _hotQuick = null);
        return;
      }
      HapticFeedback.selectionClick();
      if (q.closeOnSelect) {
        _selecting = true;
        Future.delayed(const Duration(milliseconds: 120), () {
          widget.onClose();
          q.onSelected?.call();
        });
      } else {
        q.onSelected?.call();
        setState(() => _hotQuick = null);
      }
      return;
    }

    setState(() {
      _hotEntry = null;
      _hotQuick = null;
    });
  }

  void _onCancel(PointerCancelEvent e) {
    _pressed = false;
    _stretch.release();
    if (!_selecting) {
      setState(() {
        _hotEntry = null;
        _hotQuick = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return AnimatedBuilder(
        animation: Listenable.merge([_open, _stretch]),
        builder: (context, _) => _buildMenu(context, constraints.biggest),
      );
    });
  }

  Widget _buildMenu(BuildContext context, Size stack) {
    final p = _open.value;
    if (p <= 0.001 && !widget.open) return const SizedBox.shrink();

    final c = GlassColors.of(context);
    final topSafe = MediaQuery.of(context).padding.top;
    final w = widget.width;
    final anchor = widget.anchor;

    // высота пунктов подстраивается, если экран невысокий
    final maxH = math.max(200.0, anchor.top - 10 - topSafe - 12);
    final n = math.max(1, _visibleEntries);
    _itemH = ((maxH - _fixedH) / n).clamp(36.0, 44.0);
    _panelH = _fixedH + n * _itemH;

    var left = widget.alignRight ? anchor.right - w : anchor.left;
    left = left.clamp(8.0, math.max(8.0, stack.width - w - 8));
    final top = anchor.top - 10 - _panelH;

    // точка роста — центр кнопки
    final ox = anchor.center.dx - left;
    final oy = anchor.center.dy - top;
    final sc = 0.12 + 0.88 * p;

    // растяжение от центра самой панели — плавно, без рывков
    final d = _stretch.deform;
    final sx = d.grow * (1 + d.side * 0.002 - d.vert * 0.001);
    final sy = d.grow * (1 + d.vert * 0.002 - d.side * 0.0008);

    final m = Matrix4.identity()
      ..translate(d.tx * 1.4, d.ty * 1.33)
      ..translate(w / 2, _panelH / 2)
      ..scale(sx, sy)
      ..translate(-w / 2, -_panelH / 2)
      ..translate(ox, oy)
      ..scale(sc, sc)
      ..translate(-ox, -oy);

    final fade = (p * 2.2).clamp(0.0, 1.0);
    final ip = ((p - 0.25) / 0.6).clamp(0.0, 1.0);

    Widget content = Padding(
      padding: const EdgeInsets.all(_pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.quickActions.isNotEmpty) ...[
            SizedBox(
              height: _quickH,
              child: Row(
                children: [
                  for (var i = 0; i < widget.quickActions.length; i++)
                    Expanded(
                      child: Center(
                        child: HotColor(
                          hot: _hotQuick == i || widget.quickActions[i].active,
                          color:
                              widget.quickActions[i].enabled ? c.text : c.muted,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: c.hover,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(widget.quickActions[i].icon, size: 21),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _divider(c),
          ],
          for (var i = 0; i < widget.entries.length; i++)
            widget.entries[i].isDivider
                ? _divider(c)
                : _entry(widget.entries[i], i, c),
        ],
      ),
    );

    if (ip < 0.99) {
      final s = 4 * (1 - ip);
      content = Opacity(
        opacity: ip,
        child: s > 0.05
            ? ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s),
                child: content,
              )
            : content,
      );
    }

    return Stack(
      children: [
        // нажатие мимо панели — закрыть
        if (widget.open)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => widget.onClose(),
            ),
          ),
        Positioned(
          left: left,
          top: top,
          width: w,
          height: _panelH,
          child: IgnorePointer(
            ignoring: !widget.open,
            child: Transform(
              transform: m,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onDown,
                onPointerMove: _onMove,
                onPointerUp: _onUp,
                onPointerCancel: _onCancel,
                child: GlassBox(
                  borderRadius: const BorderRadius.all(Radius.circular(26)),
                  fade: fade,
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _divider(GlassColors c) => SizedBox(
        height: _dividerH,
        child: Center(
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: c.hover,
          ),
        ),
      );

  Widget _entry(GlassMenuEntry e, int i, GlassColors c) {
    return SizedBox(
      height: _itemH,
      child: HotColor(
        hot: _hotEntry == i,
        color: e.enabled ? c.text : c.muted,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (e.icon != null) ...[
                Icon(e.icon, size: 20),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  e.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              if (e.checked != null)
                Icon(
                  e.checked! ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

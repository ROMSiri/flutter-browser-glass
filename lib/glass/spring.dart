import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Жёсткость и затухание пружины.
class SpringParams {
  final double k; // жёсткость: больше — быстрее
  final double c; // затухание: меньше — больше отскок

  const SpringParams(this.k, this.c);
}

/// Пружины, которые используются во всём интерфейсе.
class Springs {
  /// пока палец держит — пружина жёсткая и идёт за пальцем
  static const hold = SpringParams(900, 55);

  /// после отпускания — мягкий возврат без раскачивания
  static const release = SpringParams(260, 24);

  /// сжатие / раскрытие нижней панели — небольшая пружинка
  static const morph = SpringParams(170, 20);

  /// открытие панели меню — заметная пружинка
  static const menuOpen = SpringParams(240, 17);

  /// закрытие панели меню — мягко, почти без отскока
  static const menuClose = SpringParams(320, 30);
}

/// Одно число, которое плавно идёт к цели по законам пружины.
class SpringValue {
  double value;
  double velocity = 0;
  double target;

  SpringValue(double initial)
      : value = initial,
        target = initial;

  bool get isMoving => velocity != 0 || value != target;

  /// Шаг пружины. Возвращает true, пока число ещё движется.
  bool step(double dt, SpringParams p, {double eps = 0.0005}) {
    // мелкие подшаги — стабильно на любых частотах экрана
    var remaining = dt;
    while (remaining > 0) {
      final h = math.min(remaining, 1 / 240);
      final a = -p.k * (value - target) - p.c * velocity;
      velocity += a * h;
      value += velocity * h;
      remaining -= h;
    }
    if (velocity.abs() < eps && (value - target).abs() < eps) {
      value = target;
      velocity = 0;
      return false;
    }
    return true;
  }

  void jumpTo(double v) {
    value = v;
    target = v;
    velocity = 0;
  }
}

/// Готовое растяжение части интерфейса.
class StretchDeform {
  final double vert; // насколько растянуто вверх/вниз
  final double side; // насколько растянуто вбок
  final double grow; // увеличение при зажатии
  final double tx; // сдвиг за пальцем
  final double ty;
  final double ix; // растяжение значков и текста (без вращения)
  final double iy;

  const StretchDeform({
    this.vert = 0,
    this.side = 0,
    this.grow = 1,
    this.tx = 0,
    this.ty = 0,
    this.ix = 1,
    this.iy = 1,
  });

  static const none = StretchDeform();

  /// Масштаб для круглых форм: вверх/вниз — выше и уже, вбок — шире.
  double get scaleX => grow * (1 + side * 0.0018 - vert * 0.0012);

  double get scaleY => grow * (1 + vert * 0.004 - side * 0.0008);
}

/// Растяжение с усилием и пружинкой: зажал — увеличилось,
/// тянешь — туго тянется (круглая граница), отпустил — пружинкой назад.
class StretchController extends ChangeNotifier {
  final double radius; // предел растяжения
  final double tight; // меньше — туже
  final double growTo; // увеличение при зажатии

  /// На сколько часть приподнимается, когда растяжение упёрлось в предел.
  final double liftMax;

  final _up = SpringValue(0);
  final _down = SpringValue(0);
  final _side = SpringValue(0);
  final _shift = SpringValue(0);
  final _grow = SpringValue(1);
  final _lift = SpringValue(0);

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _pressed = false;
  bool _disposed = false;

  StretchController({
    required TickerProvider vsync,
    this.radius = 14, // чуть дальше, чем было (11)
    this.tight = 0.28, // и чуть легче (было 0.22)
    this.growTo = 1.04,
    this.liftMax = 6,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  bool get pressed => _pressed;

  List<SpringValue> get _all => [_up, _down, _side, _shift, _grow, _lift];

  // мягкая резина: сопротивление растёт плавно, предел — без «стены»
  double _rubber(double d) =>
      radius * (1 - 1 / (d.abs() * tight / radius + 1));

  void press() {
    _pressed = true;
    _grow.target = growTo;
    _start();
  }

  /// dx, dy — насколько палец ушёл от места нажатия.
  void pull(double dx, double dy) {
    final dist = math.sqrt(dx * dx + dy * dy);
    final k = dist > 0 ? _rubber(dist) / dist : 0.0;
    final ex = dx * k, ey = dy * k;
    _up.target = math.max(-ey, 0.0);
    _down.target = math.max(ey, 0.0);
    _side.target = ex.abs();
    _shift.target = ex;

    // упёрлись в предел — часть плавно приподнимается вверх
    final reach = dist > 0 ? _rubber(dist) / radius : 0.0;
    // начинается примерно со 60px пути пальца, полностью — к ~200px
    final over = ((reach - 0.55) / 0.25).clamp(0.0, 1.0);
    _lift.target = liftMax * over * over * (3 - 2 * over);
    _start();
  }

  void release() {
    _pressed = false;
    _up.target = 0;
    _down.target = 0;
    _side.target = 0;
    _shift.target = 0;
    _grow.target = 1;
    _lift.target = 0;
    _start();
  }

  StretchDeform get deform {
    final up = _up.value, down = _down.value, side = _side.value;
    final vert = up + down;
    return StretchDeform(
      vert: vert,
      side: side,
      grow: _grow.value,
      tx: _shift.value * 0.25,
      ty: -up * 0.3 + down * 0.3 - _lift.value,
      ix: 1 - vert * 0.006 + side * 0.005,
      iy: 1 + vert * 0.006 - side * 0.003,
    );
  }

  void _start() {
    if (_disposed) return;
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : math.min((elapsed - _last).inMicroseconds / 1e6, 1 / 20);
    _last = elapsed;
    final p = _pressed ? Springs.hold : Springs.release;
    var moving = false;
    for (final s in _all) {
      if (s.step(dt, p, eps: 0.001)) moving = true;
    }
    notifyListeners();
    if (!moving && !_pressed) _ticker.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    super.dispose();
  }
}

/// Одна пружина со своим тикером (например, сжатие панели или открытие меню).
class SpringAnimator extends ChangeNotifier {
  final SpringValue spring;
  SpringParams Function(double target) params;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _disposed = false;

  /// Не опускаться ниже цели при движении вниз (например, меню не меньше кнопки).
  final bool clampBelowZero;

  SpringAnimator({
    required TickerProvider vsync,
    double initial = 0,
    required this.params,
    this.clampBelowZero = false,
  }) : spring = SpringValue(initial) {
    _ticker = vsync.createTicker(_tick);
  }

  double get value => spring.value;

  double get target => spring.target;

  void animateTo(double target) {
    if (_disposed) return;
    spring.target = target;
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void jumpTo(double v) {
    spring.jumpTo(v);
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : math.min((elapsed - _last).inMicroseconds / 1e6, 1 / 20);
    _last = elapsed;
    final moving = spring.step(dt, params(spring.target));
    if (clampBelowZero && spring.target == 0 && spring.value < 0) {
      spring.jumpTo(0);
    }
    notifyListeners();
    if (!moving || (clampBelowZero && spring.value == 0 && spring.target == 0)) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    super.dispose();
  }
}

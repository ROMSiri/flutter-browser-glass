import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Состояние нижней панели: сжата она или нет.
/// Листаешь страницу вниз — панель сжимается, вверх или у самого верха — раскрывается.
class GlassBarController extends ChangeNotifier {
  static final GlassBarController instance = GlassBarController._();

  GlassBarController._();

  bool _compact = false;
  double _lastY = 0;

  bool get compact => _compact;

  // спрятана ли панель целиком (пока вводят текст в поиск новой вкладки)
  bool _hidden = false;

  bool get hidden => _hidden;

  void setHidden(bool value) {
    if (value == _hidden) return;
    _hidden = value;
    notifyListeners();
  }

  // путь, пройденный в одну сторону: панель переключается только после
  // заметного листания, а не от каждого мелкого подёргивания страницы
  double _run = 0;

  // страница только что поменяла высоту — её прокрутка сдвигается сама,
  // это не листание пальцем
  DateTime _quietUntil = DateTime(0);

  void onScroll(int y) {
    final dy = y - _lastY;
    _lastY = y.toDouble();
    if (DateTime.now().isBefore(_quietUntil)) {
      _run = 0;
      return;
    }
    if (y < 10) {
      _run = 0;
      setCompact(false); // у самого верха — полная
      return;
    }
    if (dy == 0) return;
    if (_run != 0 && dy.sign != _run.sign) _run = 0; // сменили направление
    _run += dy;
    if (_run > 24) {
      setCompact(true); // листаем вниз — сжимается
    } else if (_run < -24) {
      setCompact(false); // листаем вверх — раскрывается
    }
  }

  void setCompact(bool value) {
    if (value == _compact) return;
    _compact = value;
    _quietUntil = DateTime.now().add(const Duration(milliseconds: 450));
    notifyListeners();
  }

  // полноэкранный режим: системные полоски спрятаны, страница на весь экран
  bool _fullscreen = false;

  bool get fullscreen => _fullscreen;

  void setFullscreen(bool value) {
    if (value == _fullscreen) return;
    _fullscreen = value;
    SystemChrome.setEnabledSystemUIMode(
            value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge)
        .catchError((_) {});
    if (value) _compact = true; // капсула сразу становится маленькой
    notifyListeners();
  }

  /// Место под капсулой: стеклянная полоса с капсулой (48), отступом
  /// снизу (12) и воздухом над ней (8). Пока панель сжата или включён
  /// полноэкранный режим, полосы нет и страница идёт до самого низа.
  static const double barSpace = 68;

  bool get showsStrip => !_compact && !_fullscreen;

  /// Где на экране стоит страница в покое.
  Rect pageRect(Size screen, EdgeInsets pad) {
    final top = _fullscreen ? 0.0 : pad.top;
    final bottom = showsStrip ? pad.bottom + barSpace : 0.0;
    return Rect.fromLTWH(0, top, screen.width, screen.height - top - bottom);
  }

  void reset() {
    _lastY = 0;
    _run = 0;
    setCompact(false);
  }
}

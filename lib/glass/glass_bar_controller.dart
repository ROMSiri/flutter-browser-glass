import 'package:flutter/foundation.dart';

/// Состояние нижней панели: сжата она или нет.
/// Листаешь страницу вниз — панель сжимается, вверх или у самого верха — раскрывается.
class GlassBarController extends ChangeNotifier {
  static final GlassBarController instance = GlassBarController._();

  GlassBarController._();

  bool _compact = false;
  double _lastY = 0;

  bool get compact => _compact;

  void onScroll(int y) {
    final dy = y - _lastY;
    if (y < 10) {
      setCompact(false); // у самого верха — полная
    } else if (dy > 6) {
      setCompact(true); // листаем вниз — сжимается
    } else if (dy < -6) {
      setCompact(false); // листаем вверх — раскрывается
    }
    // мелкие подёргивания страницы режим не переключают
    if (dy.abs() > 6 || y < 10) _lastY = y.toDouble();
  }

  void setCompact(bool value) {
    if (value == _compact) return;
    _compact = value;
    notifyListeners();
  }

  void reset() {
    _lastY = 0;
    setCompact(false);
  }
}

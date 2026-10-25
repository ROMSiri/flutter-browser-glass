import 'package:flutter/widgets.dart';

/// Общее состояние перехода «страница ↔ экран вкладок».
///
/// Экран вкладок ведёт анимацию и сообщает, где сейчас должна быть страница,
/// а браузер сжимает и двигает саму живую страницу в это место —
/// так в карточку превращается именно страница, а не её копия.
class TabsTransition extends ChangeNotifier {
  static final TabsTransition instance = TabsTransition._();

  TabsTransition._();

  /// 0 — страница на весь экран, 1 — страница стала карточкой в сетке.
  double t = 0;

  /// Куда на экране ложится страница (часть карточки под строкой с названием).
  Rect? card;

  /// Скругление углов страницы в пикселях экрана.
  double radius = 0;

  /// Видна ли живая страница. Когда карточка уже на месте и снимок готов,
  /// страница прячется, и остаётся обычная карточка со снимком.
  bool pageVisible = true;

  /// Готов ли свежий снимок текущей страницы для её карточки.
  Future<void>? screenshotReady;

  void update({
    required double t,
    required Rect? card,
    required double radius,
    required bool pageVisible,
  }) {
    this.t = t;
    this.card = card;
    this.radius = radius;
    this.pageVisible = pageVisible;
    notifyListeners();
  }

  /// Без уведомления: вызывается, когда экран вкладок уже убирается.
  void resetSilently() {
    t = 0;
    card = null;
    radius = 0;
    pageVisible = true;
  }
}

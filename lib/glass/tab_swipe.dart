import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../models/webview_model.dart';

/// Общее состояние свайпа по капсуле между вкладками.
///
/// Капсула ведёт жест, а браузер сдвигает живую страницу за пальцем
/// и рядом показывает соседнюю вкладку (её снимок) — как в Safari.
class TabSwipe extends ChangeNotifier {
  static final TabSwipe instance = TabSwipe._();

  TabSwipe._();

  /// Насколько страница сдвинута вбок, в пикселях (влево — меньше нуля).
  double offset = 0;

  /// Соседняя вкладка, которая въезжает: справа при [side] = 1, слева при -1.
  WebViewModel? neighbor;
  int side = 0;

  /// Снимок новой вкладки поверх живой страницы сразу после переключения,
  /// пока страница не успела отрисоваться, и насколько он ещё виден.
  Uint8List? cover;
  double coverOpacity = 0;

  bool get active => offset != 0 || neighbor != null;

  void update({required double offset, WebViewModel? neighbor, int side = 0}) {
    this.offset = offset;
    this.neighbor = neighbor;
    this.side = side;
    notifyListeners();
  }

  void setCover(Uint8List? cover, double opacity) {
    this.cover = opacity > 0.001 ? cover : null;
    coverOpacity = this.cover == null ? 0 : opacity;
    notifyListeners();
  }

  /// Без уведомления: вызывается, когда капсула уже убирается.
  void clearSilently() {
    offset = 0;
    neighbor = null;
    side = 0;
    cover = null;
    coverOpacity = 0;
  }

  void reset() {
    offset = 0;
    neighbor = null;
    side = 0;
    notifyListeners();
  }
}

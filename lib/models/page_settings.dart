import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_model.dart';

/// Переносит общие настройки страниц из настроек браузера в настройки WebView.
/// [dark] — включена ли сейчас тёмная тема приложения.
void applyPageSettings(InAppWebViewSettings target, BrowserSettings settings,
    {required bool dark}) {
  target.javaScriptEnabled = settings.javaScriptEnabled;
  target.supportZoom = settings.supportZoom;
  target.builtInZoomControls = settings.supportZoom;
  target.displayZoomControls = false;
  target.mediaPlaybackRequiresUserGesture = settings.mediaNeedsGesture;
  target.javaScriptCanOpenWindowsAutomatically = !settings.blockPopups;
  target.supportMultipleWindows = !settings.blockPopups;
  target.textZoom = settings.textZoom;
  final darken = settings.darkPages && dark;
  target.algorithmicDarkeningAllowed = darken;
  target.forceDark = darken ? ForceDark.ON : ForceDark.OFF;
}

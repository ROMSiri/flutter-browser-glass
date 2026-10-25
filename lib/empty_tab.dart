import 'package:flutter/material.dart';
import 'package:flutter_browser/util.dart';
import 'package:flutter_browser/webview_tab.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'glass/start_page.dart';
import 'models/browser_model.dart';
import 'models/webview_model.dart';
import 'models/window_model.dart';

/// Пустая вкладка: логотип поисковика, стеклянная строка поиска
/// и избранное плитками.
class EmptyTab extends StatefulWidget {
  const EmptyTab({super.key});

  @override
  State<EmptyTab> createState() => _EmptyTabState();
}

class _EmptyTabState extends State<EmptyTab> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // вкладок нет — та же страница с поиском, но клавиатура сама не открывается
    return StartPage(onOpen: _openUrl, autofocus: false);
  }

  void _openUrl(WebUri? url) {
    if (url == null) return;
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    windowModel.addTab(WebViewTab(
      key: GlobalKey(),
      webViewModel: WebViewModel(url: url),
    ));
  }

  void openNewTab(String value) {
    if (value.trim().isEmpty) return;
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final settings = browserModel.getSettings();

    var url = WebUri(value.trim());
    if (Util.isLocalizedContent(url) ||
        (url.isValidUri && url.toString().split(".").length > 1)) {
      url = url.scheme.isEmpty ? WebUri("https://$url") : url;
    } else {
      url = WebUri(settings.searchEngine.searchUrl + value.trim());
    }

    _openUrl(url);
  }
}

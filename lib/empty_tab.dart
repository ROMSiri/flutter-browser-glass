import 'package:flutter/material.dart';
import 'package:flutter_browser/custom_image.dart';
import 'package:flutter_browser/util.dart';
import 'package:flutter_browser/webview_tab.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'glass/glass.dart';
import 'glass/glass_theme.dart';
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
    final c = GlassColors.of(context);
    final browserModel = Provider.of<BrowserModel>(context, listen: true);
    final settings = browserModel.getSettings();
    final favorites = browserModel.favorites.take(8).toList();

    return Scaffold(
      backgroundColor: c.page,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 140),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: 64,
                  child: Image(image: AssetImage(settings.searchEngine.assetIcon)),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: GlassBox(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 18, right: 6),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, color: c.muted, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              onSubmitted: openNewTab,
                              textInputAction: TextInputAction.go,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              style: TextStyle(color: c.text, fontSize: 17),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: "Поиск или адрес сайта",
                                hintStyle:
                                    TextStyle(color: c.muted, fontSize: 17),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded,
                                color: GlassColors.active),
                            onPressed: () {
                              openNewTab(_controller.text);
                              FocusScope.of(context).unfocus();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (favorites.isNotEmpty) ...[
                  const SizedBox(height: 36),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Избранное",
                      style: TextStyle(
                          color: c.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: favorites.map((favorite) {
                      final url = favorite.url;
                      final faviconUrl = favorite.favicon != null
                          ? favorite.favicon!.url
                          : WebUri("${url?.origin ?? ""}/favicon.ico");
                      final name = (favorite.title?.isNotEmpty ?? false)
                          ? favorite.title!
                          : url?.host ?? "";
                      return GestureDetector(
                        onTap: () => _openUrl(favorite.url),
                        child: SizedBox(
                          width: 72,
                          child: Column(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: c.card,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: c.stroke),
                                ),
                                alignment: Alignment.center,
                                child: CustomImage(
                                    url: faviconUrl, maxWidth: 28, height: 28),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(color: c.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
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

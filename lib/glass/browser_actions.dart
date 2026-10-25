import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_browser/app_bar/url_info_popup.dart';
import 'package:flutter_browser/custom_image.dart';
import 'package:flutter_browser/custom_popup_dialog.dart';
import 'package:flutter_browser/main.dart';
import 'package:flutter_browser/models/browser_model.dart';
import 'package:flutter_browser/models/favorite_model.dart';
import 'package:flutter_browser/models/web_archive_model.dart';
import 'package:flutter_browser/models/webview_model.dart';
import 'package:flutter_browser/models/window_model.dart';
import 'package:flutter_browser/pages/settings/main.dart';
import 'package:flutter_browser/util.dart';
import 'package:flutter_browser/webview_tab.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'glass_bar_controller.dart';
import 'glass.dart';
import 'glass_page.dart';
import 'glass_sheet.dart';
import 'glass_theme.dart';

/// Все действия браузера (вкладки, избранное, история, тема…),
/// которыми пользуются нижняя панель, меню и экран вкладок.
mixin BrowserActions<T extends StatefulWidget> on State<T> {
  CustomPopupDialogPageRoute? _urlInfoRoute;

  // ---------- адрес и вкладки ----------

  WebUri homeUrl() {
    final settings =
        Provider.of<BrowserModel>(context, listen: false).getSettings();
    return settings.homePageEnabled && settings.customUrlHomePage.isNotEmpty
        ? WebUri(settings.customUrlHomePage)
        : WebUri(settings.searchEngine.url);
  }

  /// Из того, что ввели в адресную строку: адрес или поисковый запрос.
  WebUri urlFromInput(String value) {
    final settings =
        Provider.of<BrowserModel>(context, listen: false).getSettings();
    var url = WebUri(value.trim());
    if (Util.isLocalizedContent(url) ||
        (url.isValidUri && url.toString().split(".").length > 1)) {
      url = url.scheme.isEmpty ? WebUri("https://$url") : url;
    } else {
      url = WebUri(settings.searchEngine.searchUrl + value.trim());
    }
    return url;
  }

  void openInput(String value) {
    if (value.trim().isEmpty) return;
    final url = urlFromInput(value);
    final webViewModel = Provider.of<WebViewModel>(context, listen: false);
    if (webViewModel.webViewController != null) {
      webViewModel.webViewController!.loadUrl(urlRequest: URLRequest(url: url));
    } else {
      addNewTab(url: url);
      webViewModel.url = url;
    }
  }

  void addNewTab({WebUri? url}) {
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    browserModel.showTabScroller = false;
    GlassBarController.instance.reset();
    windowModel.addTab(WebViewTab(
      key: GlobalKey(),
      webViewModel: WebViewModel(url: url ?? homeUrl()),
    ));
  }

  void addNewIncognitoTab({WebUri? url}) {
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    browserModel.showTabScroller = false;
    GlassBarController.instance.reset();
    windowModel.addTab(WebViewTab(
      key: GlobalKey(),
      webViewModel: WebViewModel(url: url ?? homeUrl(), isIncognitoMode: true),
    ));
  }

  /// Закрыть все вкладки, кроме закреплённых.
  void closeAllTabs() {
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final pinned = windowModel.webViewTabs.any((t) => t.webViewModel.isPinned);
    if (pinned) {
      closeOtherTabs(null);
    } else {
      windowModel.closeAllTabs();
    }
    if (windowModel.webViewTabs.isEmpty) browserModel.showTabScroller = false;
    GlassBarController.instance.reset();
  }

  /// Закрыть все вкладки, кроме [keep] и закреплённых.
  void closeOtherTabs(WebViewModel? keep) {
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final tabs = windowModel.webViewTabs.toList();
    for (var i = tabs.length - 1; i >= 0; i--) {
      final model = tabs[i].webViewModel;
      if (model == keep || model.isPinned) continue;
      windowModel.closeTab(i);
    }
    if (keep?.tabIndex != null) windowModel.showTab(keep!.tabIndex!);
  }

  void togglePinTab(WebViewModel model) {
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    model.isPinned = !model.isPinned;
    windowModel.notifyWebViewTabUpdated();
    _toast(model.isPinned ? "Вкладка закреплена" : "Вкладка откреплена");
  }

  /// Копия вкладки — та же страница рядом, экран вкладок остаётся открытым.
  void duplicateTab(WebViewModel model) {
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final copy = WebViewModel(
        url: model.url,
        title: model.title,
        favicon: model.favicon,
        isIncognitoMode: model.isIncognitoMode);
    copy.screenshot = model.screenshot;
    windowModel.addTab(WebViewTab(key: GlobalKey(), webViewModel: copy));
  }

  void copyTabLink(WebViewModel model) {
    final url = model.url?.toString();
    if (url == null || url.isEmpty) return;
    Clipboard.setData(ClipboardData(text: url));
    _toast("Ссылка скопирована");
  }

  void shareTab(WebViewModel model) {
    final url = model.url;
    if (url != null) Share.share(url.toString(), subject: model.title);
  }

  /// Открыть экран вкладок (с актуальным снимком текущей страницы).
  Future<void> openTabViewer() async {
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    if (windowModel.webViewTabs.isEmpty) return;

    final webViewModel = windowModel.getCurrentTab()?.webViewModel;
    final webViewController = webViewModel?.webViewController;

    if (View.of(context).viewInsets.bottom > 0.0) {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      FocusManager.instance.primaryFocus?.unfocus();
      if (webViewController != null) {
        await webViewController.evaluateJavascript(
            source: "document.activeElement.blur();");
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (webViewModel != null && webViewController != null) {
      webViewModel.screenshot = await webViewController
          .takeScreenshot(
              screenshotConfiguration: ScreenshotConfiguration(
                  compressFormat: CompressFormat.JPEG, quality: 30))
          .timeout(
            const Duration(milliseconds: 1500),
            onTimeout: () => null,
          );
    }

    browserModel.showTabScroller = true;
  }

  // ---------- избранное ----------

  FavoriteModel? currentFavorite() {
    final webViewModel = Provider.of<WebViewModel>(context, listen: false);
    if (webViewModel.url == null || webViewModel.url.toString().isEmpty) {
      return null;
    }
    return FavoriteModel(
        url: webViewModel.url,
        title: webViewModel.title ?? "",
        favicon: webViewModel.favicon);
  }

  bool isCurrentFavorite() {
    final fav = currentFavorite();
    if (fav == null) return false;
    return Provider.of<BrowserModel>(context, listen: false)
        .containsFavorite(fav);
  }

  void toggleFavorite() {
    final fav = currentFavorite();
    if (fav == null) return;
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    if (browserModel.containsFavorite(fav)) {
      browserModel.removeFavorite(fav);
      _toast("Убрано из избранного");
    } else {
      browserModel.addFavorite(fav);
      _toast("Добавлено в избранное");
    }
    setState(() {});
  }

  void showFavorites() {
    pushGlassPage(
      context,
      (pageContext) => GlassPage(
        title: "Избранное",
        builder: (pageContext, padding) {
          final browserModel =
              Provider.of<BrowserModel>(pageContext, listen: true);
          final favorites = browserModel.favorites;
          if (favorites.isEmpty) {
            return const GlassEmpty(
                icon: Icons.star_border, text: "В избранном пока пусто");
          }
          return ListView(
            padding: padding,
            children: [
              GlassGroup(
                children: favorites.map((favorite) {
                  final url = favorite.url;
                  final faviconUrl = favorite.favicon != null
                      ? favorite.favicon!.url
                      : WebUri("${url?.origin ?? ""}/favicon.ico");
                  return GlassListRow(
                    leading:
                        CustomImage(url: faviconUrl, maxWidth: 24, height: 24),
                    title: (favorite.title?.isNotEmpty ?? false)
                        ? favorite.title!
                        : url?.toString() ?? "",
                    subtitle: url?.host,
                    onTap: () {
                      Navigator.pop(pageContext);
                      addNewTab(url: favorite.url);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => browserModel.removeFavorite(favorite),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------- история ----------

  void showHistory() {
    final webViewModel = Provider.of<WebViewModel>(context, listen: false);
    pushGlassPage(
      context,
      (pageContext) => GlassPage(
        title: "История",
        builder: (pageContext, padding) {
          return FutureBuilder<WebHistory?>(
            future: webViewModel.webViewController?.getCopyBackForwardList(),
            builder: (context, snapshot) {
              if (webViewModel.webViewController != null &&
                  snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data?.list?.reversed.toList() ?? [];
              if (items.isEmpty) {
                return const GlassEmpty(
                    icon: Icons.history, text: "История этой вкладки пуста");
              }
              return ListView(
                padding: padding,
                children: [
                  const GlassGroupTitle("Эта вкладка"),
                  GlassGroup(
                    children: items.map((historyItem) {
                      final url = historyItem.url;
                      return GlassListRow(
                        leading: CustomImage(
                            url: WebUri("${url?.origin ?? ""}/favicon.ico"),
                            maxWidth: 24,
                            height: 24),
                        title: (historyItem.title?.isNotEmpty ?? false)
                            ? historyItem.title!
                            : url.toString(),
                        subtitle: url?.host,
                        onTap: () {
                          webViewModel.webViewController
                              ?.goTo(historyItem: historyItem);
                          Navigator.pop(pageContext);
                        },
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ---------- сохранённые страницы ----------

  void showWebArchives() {
    pushGlassPage(
      context,
      (pageContext) => GlassPage(
        title: "Сохранённые страницы",
        builder: (pageContext, padding) {
          final browserModel =
              Provider.of<BrowserModel>(pageContext, listen: true);
          final archives = browserModel.webArchives.values.toList();
          if (archives.isEmpty) {
            return const GlassEmpty(
                icon: Icons.offline_pin_outlined,
                text: "Сохранённых страниц пока нет");
          }
          return ListView(
            padding: padding,
            children: [
              GlassGroup(
                children: archives.map((webArchive) {
                  final url = webArchive.url;
                  final path = webArchive.path;
                  return GlassListRow(
                    leading: CustomImage(
                        url: WebUri("${url?.origin ?? ""}/favicon.ico"),
                        maxWidth: 24,
                        height: 24),
                    title: (webArchive.title?.isNotEmpty ?? false)
                        ? webArchive.title!
                        : url?.toString() ?? "",
                    subtitle: url?.host,
                    onTap: () {
                      Navigator.pop(pageContext);
                      if (path != null) {
                        addNewTab(url: WebUri("file://$path"));
                      }
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () {
                        browserModel.removeWebArchive(webArchive);
                        browserModel.save();
                      },
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> saveOffline() async {
    final webViewModel = Provider.of<WebViewModel>(context, listen: false);
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final url = webViewModel.url;
    if (url == null || !url.scheme.startsWith("http")) {
      _toast("Эту страницу нельзя сохранить");
      return;
    }

    final webArchivePath =
        "$WEB_ARCHIVE_DIR${Platform.pathSeparator}${url.scheme}-${url.host}${url.path.replaceAll("/", "-")}${DateTime.now().microsecondsSinceEpoch}.${Util.isAndroid() ? WebArchiveFormat.MHT.toValue() : WebArchiveFormat.WEBARCHIVE.toValue()}";

    final savedPath = await webViewModel.webViewController
        ?.saveWebArchive(filePath: webArchivePath, autoname: false);

    if (savedPath != null) {
      browserModel.addWebArchive(
          url.toString(),
          WebArchiveModel(
              url: url,
              path: savedPath,
              title: webViewModel.title,
              favicon: webViewModel.favicon,
              timestamp: DateTime.now()));
      browserModel.save();
      _toast("Страница сохранена для офлайн-чтения");
    } else {
      _toast("Не удалось сохранить страницу");
    }
  }

  // ---------- прочее ----------

  void share() {
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final webViewModel = windowModel.getCurrentTab()?.webViewModel;
    final url = webViewModel?.url;
    if (url != null) {
      Share.share(url.toString(), subject: webViewModel?.title);
    }
  }

  Future<void> toggleDesktopMode() async {
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final webViewModel = windowModel.getCurrentTab()?.webViewModel;
    final webViewController = webViewModel?.webViewController;
    final currentWebViewModel =
        Provider.of<WebViewModel>(context, listen: false);

    if (webViewController != null && webViewModel != null) {
      webViewModel.isDesktopMode = !webViewModel.isDesktopMode;
      currentWebViewModel.isDesktopMode = webViewModel.isDesktopMode;

      final currentSettings = await webViewController.getSettings();
      if (currentSettings != null) {
        currentSettings.preferredContentMode = webViewModel.isDesktopMode
            ? UserPreferredContentMode.DESKTOP
            : UserPreferredContentMode.RECOMMENDED;
        await webViewController.setSettings(settings: currentSettings);
      }
      await webViewController.reload();
    }
  }

  void showUrlInfo() {
    final webViewModel = Provider.of<WebViewModel>(context, listen: false);
    final url = webViewModel.url;
    if (url == null || url.toString().isEmpty) return;

    const duration = Duration(milliseconds: 300);
    _urlInfoRoute = CustomPopupDialog.show(
      context: context,
      transitionDuration: duration,
      builder: (context) {
        return UrlInfoPopup(
          route: _urlInfoRoute!,
          transitionDuration: duration,
          onWebViewTabSettingsClicked: goToSettingsPage,
        );
      },
    );
  }

  void goToSettingsPage() {
    pushGlassPage(context, (context) => const SettingsPage());
  }

  Future<void> takeScreenshotAndShow() async {
    final webViewModel = Provider.of<WebViewModel>(context, listen: false);
    final screenshot = await webViewModel.webViewController?.takeScreenshot();
    if (screenshot == null || !mounted) return;

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        "${dir.path}/screenshot_${DateTime.now().microsecondsSinceEpoch}.png");
    await file.writeAsBytes(screenshot);
    if (!mounted) return;

    await pushGlassPage(
      context,
      (pageContext) => GlassPage(
        title: "Скриншот",
        actions: [
          StretchyGlassButton(
            width: 44,
            height: 44,
            onTap: () => Share.shareXFiles([XFile(file.path)]),
            child: const Icon(Icons.ios_share_rounded, size: 20),
          ),
        ],
        builder: (pageContext, padding) => SingleChildScrollView(
          padding: padding,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.memory(screenshot, fit: BoxFit.contain),
          ),
        ),
      ),
    );

    if (await file.exists()) file.delete();
  }

  // ---------- тема ----------

  bool isDarkTheme() => Theme.of(context).brightness == Brightness.dark;

  /// Переключить светлую / тёмную тему (и запомнить выбор).
  void toggleTheme() {
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final settings = browserModel.getSettings();
    settings.themeMode = isDarkTheme() ? 1 : 2;
    browserModel.updateSettings(settings);
    browserModel.save();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(milliseconds: 1600),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
    ));
  }

  Color glassText() => GlassColors.of(context).text;
}

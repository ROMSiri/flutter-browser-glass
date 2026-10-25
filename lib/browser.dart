import 'dart:async';

// import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_browser/custom_image.dart';
import 'package:flutter_browser/tab_viewer.dart';
import 'package:flutter_browser/app_bar/browser_app_bar.dart';
import 'package:flutter_browser/models/webview_model.dart';
import 'package:flutter_browser/util.dart';
import 'package:flutter_browser/webview_tab.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'app_bar/tab_viewer_app_bar.dart';
import 'empty_tab.dart';
import 'glass/glass_bar_controller.dart';
import 'glass/glass_bottom_bar.dart';
import 'glass/glass_find_bar.dart';
import 'glass/glass_tabs_page.dart';
import 'glass/glass_theme.dart';
import 'glass/tab_swipe.dart';
import 'glass/tabs_transition.dart';
import 'models/browser_model.dart';
import 'models/window_model.dart';

class Browser extends StatefulWidget {
  const Browser({super.key});

  @override
  State<Browser> createState() => _BrowserState();
}

class _BrowserState extends State<Browser> with SingleTickerProviderStateMixin {
  static const platform =
      MethodChannel('com.pichillilorenzo.flutter_browser.intent_data');

  var _isRestored = false;

  // поиск по странице: на месте нижней панели
  var _isFindingOnPage = false;

  @override
  void initState() {
    super.initState();
    getIntentData();
  }

  getIntentData() async {
    if (Util.isAndroid()) {
      String? url = await platform.invokeMethod("getIntentData");
      if (url != null) {
        if (mounted) {
          final windowModel = Provider.of<WindowModel>(context, listen: false);
          windowModel.addTab(WebViewTab(
            key: GlobalKey(),
            webViewModel: WebViewModel(url: WebUri(url)),
          ));
        }
      }
    }
  }

  restore() async {
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    browserModel.restore();
    windowModel.restoreInfo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isRestored) {
      _isRestored = true;
      restore();
      _listenForSave();
    }
    precacheImage(const AssetImage("assets/icon/icon.png"), context);
  }

  // Подписки на сохранение — один раз. Раньше они добавлялись при каждой
  // перестройке экрана, и каждое изменение страницы сохранялось десятки раз.
  void _listenForSave() {
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final currentWebViewModel =
        Provider.of<WebViewModel>(context, listen: false);
    browserModel.addListener(browserModel.save);
    windowModel.addListener(windowModel.saveInfo);
    currentWebViewModel.addListener(windowModel.saveInfo);
  }

  @override
  Widget build(BuildContext context) {
    return _buildBrowser();
  }

  Widget _buildBrowser() {
    final browserModel = Provider.of<BrowserModel>(context, listen: true);
    final windowModel = Provider.of<WindowModel>(context, listen: true);

    var canShowTabScroller =
        browserModel.showTabScroller && windowModel.webViewTabs.isNotEmpty;

    if (Util.isMobile()) {
      // экран вкладок лежит под страницей: при переходе сама живая страница
      // сжимается в свою карточку и раскрывается из неё обратно
      return Stack(
        children: [
          if (canShowTabScroller) Positioned.fill(child: GlassTabsPage()),
          // пока открыт экран вкладок, страница сверху не должна забирать
          // нажатия — иначе карточки и кнопки под ней не нажимаются
          Positioned.fill(
            child: AnimatedBuilder(
              animation: TabsTransition.instance,
              builder: (context, child) => IgnorePointer(
                // пока карточка раскрывается в страницу, капсула уже
                // нажимается: можно сразу вернуться во вкладки
                ignoring:
                    canShowTabScroller && !TabsTransition.instance.closing,
                child: child,
              ),
              child: _buildWebViewTabs(),
            ),
          ),
        ],
      );
    }

    return IndexedStack(
      index: canShowTabScroller ? 1 : 0,
      children: [
        _buildWebViewTabs(),
        canShowTabScroller ? _buildWebViewTabsViewer() : Container()
      ],
    );
  }

  /// Телефон: страница на весь экран, поверх неё — нижняя стеклянная панель.
  Widget _buildMobileScaffold() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final tabsShown =
        browserModel.showTabScroller && windowModel.webViewTabs.isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        // пока открыт экран вкладок, под страницей виден он
        backgroundColor:
            tabsShown ? Colors.transparent : GlassColors.of(context).page,
        // клавиатура ложится поверх страницы и не сжимает её
        resizeToAvoidBottomInset: false,
        body: _buildMobileBody(tabsShown),
      ),
    );
  }

  Widget _buildMobileBody(bool tabsShown) {
    // страница и панель строятся один раз, а на кадрах перехода
    // только сдвигаются и масштабируются
    final content = _buildWebViewTabsContent();
    final bar = _isFindingOnPage
        ? GlassFindBar(
            onClose: () => setState(() => _isFindingOnPage = false),
          )
        : GlassBottomBar(
            onFindOnPage: () => setState(() => _isFindingOnPage = true),
          );
    return AnimatedBuilder(
      animation: Listenable.merge([
        TabsTransition.instance,
        TabSwipe.instance,
        GlassBarController.instance,
      ]),
      builder: (context, _) {
        final tr = TabsTransition.instance;
        final t = tabsShown ? tr.t : 0.0;
        final visible = !tabsShown || tr.pageVisible;
        final sw = TabSwipe.instance;
        final swiping = !tabsShown && sw.active;
        final neighbor = swiping ? sw.neighbor : null;
        final cover = tabsShown ? null : sw.cover;
        final page = _pageRect();
        // слои с ключами: соседняя вкладка появляется и исчезает,
        // а страница и капсула не пересоздаются
        return Stack(
          children: [
            Positioned.fill(
              key: const ValueKey('page'),
              child: IgnorePointer(
                ignoring: tabsShown,
                child: Opacity(
                  opacity: visible ? 1 : 0,
                  // свайп по капсуле: живая страница едет за пальцем
                  child: Transform.translate(
                    offset: Offset(swiping ? sw.offset : 0, 0),
                    child: _transformedPage(
                        content, tabsShown ? tr.card : null, t, tr.radius),
                  ),
                ),
              ),
            ),
            // а рядом въезжает соседняя вкладка
            if (neighbor != null)
              Positioned.fromRect(
                key: const ValueKey('neighbor'),
                rect: page.shift(
                    Offset(sw.offset + sw.side * (page.width + 12), 0)),
                child: IgnorePointer(child: _tabPreview(neighbor)),
              ),
            // снимок новой вкладки, пока её страница не отрисовалась
            if (cover != null)
              Positioned.fromRect(
                key: const ValueKey('cover'),
                rect: page,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: sw.coverOpacity.clamp(0.0, 1.0),
                    child: Image.memory(cover,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        gaplessPlayback: true),
                  ),
                ),
              ),
            // при переходе к вкладкам капсула и кнопки уезжают вниз,
            // а при возврате выезжают снизу заранее, чтобы кнопка вкладок
            // нажималась сразу, не дожидаясь конца анимации
            Positioned.fill(
              key: const ValueKey('bar'),
              child: IgnorePointer(
                ignoring: tabsShown && !tr.closing,
                child: Transform.translate(
                  offset: Offset(
                      0,
                      160 *
                          (tr.closing
                              ? ((t - 0.6) / 0.4).clamp(0.0, 1.0)
                              : t.clamp(0.0, 1.0))),
                  child: bar,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Где на экране стоит страница в покое. Над капсулой со стеклянной
  /// полосой она кончается, чтобы нижние панели сайтов (кнопки, меню,
  /// поле ввода) были видны; когда панель сжата — идёт до самого низа.
  Rect _pageRect() {
    final media = MediaQuery.of(context);
    return GlassBarController.instance.pageRect(media.size, media.padding);
  }

  /// Соседняя вкладка при свайпе: её снимок, а если его нет — название.
  Widget _tabPreview(WebViewModel model) {
    final c = GlassColors.of(context);
    final shot = model.url == null ? null : model.screenshot;
    if (shot != null) {
      return ColoredBox(
        color: c.page,
        child: Image.memory(shot,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            gaplessPlayback: true),
      );
    }
    final title = model.url == null
        ? "Новая вкладка"
        : (model.title?.isNotEmpty ?? false)
            ? model.title!
            : model.url!.host;
    return ColoredBox(
      color: c.page,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.muted, fontSize: 17, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  /// Страница под строкой состояния. Во время перехода она уменьшается
  /// и ложится в [card] (место снимка в карточке), обрезаясь по его высоте.
  Widget _transformedPage(Widget content, Rect? card, double t, double radius) {
    final page = _pageRect();

    // одно и то же дерево и в покое, и при переходе — WebView не пересоздаётся
    final moving = card != null && t > 0.0001;
    final r = moving ? card : page;
    final scale = r.width / page.width;
    final clipH = r.height / scale;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          width: page.width,
          height: page.height,
          child: Transform(
            transform: Matrix4.identity()
              ..translate(r.left, r.top)
              ..scale(scale, scale),
            child: ClipRRect(
              clipper: _PageClipper(clipH, radius / scale),
              clipBehavior: moving ? Clip.antiAlias : Clip.none,
              child: content,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWebViewTabs() {
    return WillPopScope(
        onWillPop: () async {
          // открыт экран вкладок — «назад» плавно возвращает в текущую вкладку
          final tabsPage = glassTabsPageKey.currentState;
          if (tabsPage != null) {
            tabsPage.closeToCurrent();
            return false;
          }
          if (_isFindingOnPage) {
            setState(() => _isFindingOnPage = false);
            return false;
          }
          if (GlassBarController.instance.fullscreen) {
            GlassBarController.instance.setFullscreen(false);
            return false;
          }
          final windowModel = Provider.of<WindowModel>(context, listen: false);
          final webViewModel = windowModel.getCurrentTab()?.webViewModel;
          final webViewController = webViewModel?.webViewController;

          if (webViewController != null) {
            if (await webViewController.canGoBack()) {
              webViewController.goBack();
              return false;
            }
          }

          if (webViewModel != null && webViewModel.tabIndex != null) {
            setState(() {
              windowModel.closeTab(webViewModel.tabIndex!);
            });
            if (mounted) {
              FocusScope.of(context).unfocus();
            }
            return false;
          }

          return windowModel.webViewTabs.isEmpty;
        },
        child: Listener(
          onPointerUp: (_) {
            if (Util.isIOS() || Util.isAndroid()) {
              FocusScopeNode currentFocus = FocusScope.of(context);
              if (!currentFocus.hasPrimaryFocus &&
                  currentFocus.focusedChild != null) {
                currentFocus.focusedChild!.unfocus();
              }
            }
          },
          child: Util.isMobile()
              ? _buildMobileScaffold()
              : Scaffold(
                  appBar: BrowserAppBar(), body: _buildWebViewTabsContent()),
        ));
  }

  Widget _buildWebViewTabsContent() {
    final windowModel = Provider.of<WindowModel>(context, listen: true);

    if (windowModel.webViewTabs.isEmpty) {
      return const EmptyTab();
    }

    for (final webViewTab in windowModel.webViewTabs) {
      var isCurrentTab =
          webViewTab.webViewModel.tabIndex == windowModel.getCurrentTabIndex();

      if (isCurrentTab) {
        Future.delayed(const Duration(milliseconds: 100), () {
          webViewTabStateKey.currentState?.onShowTab();
        });
      } else {
        webViewTabStateKey.currentState?.onHideTab();
      }
    }

    var stackChildren = <Widget>[
      windowModel.getCurrentTab() ?? Container(),
      // на телефоне загрузка показывается полоской в адресной строке
      if (!Util.isMobile()) _createProgressIndicator()
    ];

    return Column(
      children: [
        Expanded(
            child: Stack(
          children: stackChildren,
        ))
      ],
    );
  }

  Widget _createProgressIndicator() {
    return Selector<WebViewModel, double>(
        selector: (context, webViewModel) => webViewModel.progress,
        builder: (context, progress, child) {
          if (progress >= 1.0) {
            return Container();
          }
          return PreferredSize(
              preferredSize: const Size(double.infinity, 4.0),
              child: SizedBox(
                  height: 4.0,
                  child: LinearProgressIndicator(
                    value: progress,
                  )));
        });
  }

  Widget _buildWebViewTabsViewer() {
    final browserModel = Provider.of<BrowserModel>(context, listen: true);
    final windowModel = Provider.of<WindowModel>(context, listen: true);

    return WillPopScope(
        onWillPop: () async {
          browserModel.showTabScroller = false;
          return false;
        },
        child: Scaffold(
            appBar: const TabViewerAppBar(),
            body: TabViewer(
              currentIndex: windowModel.getCurrentTabIndex(),
              children: windowModel.webViewTabs.map((webViewTab) {
                webViewTabStateKey.currentState?.pause();
                var screenshotData = webViewTab.webViewModel.screenshot;
                Widget screenshotImage = Container(
                  decoration: const BoxDecoration(color: Colors.white),
                  width: double.infinity,
                  child: screenshotData != null
                      ? Image.memory(screenshotData)
                      : null,
                );

                var url = webViewTab.webViewModel.url;
                var faviconUrl = webViewTab.webViewModel.favicon != null
                    ? webViewTab.webViewModel.favicon!.url
                    : (url != null && ["http", "https"].contains(url.scheme)
                        ? Uri.parse("${url.origin}/favicon.ico")
                        : null);

                var isCurrentTab = windowModel.getCurrentTabIndex() ==
                    webViewTab.webViewModel.tabIndex;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Material(
                      color: isCurrentTab
                          ? Colors.blue
                          : (webViewTab.webViewModel.isIncognitoMode
                              ? Colors.black
                              : Colors.white),
                      child: ListTile(
                        leading: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            // CachedNetworkImage(
                            //   placeholder: (context, url) =>
                            //   url == "about:blank"
                            //       ? Container()
                            //       : CircularProgressIndicator(),
                            //   imageUrl: faviconUrl,
                            //   height: 30,
                            // )
                            CustomImage(
                                url: faviconUrl, maxWidth: 30.0, height: 30.0)
                          ],
                        ),
                        title: Text(
                            webViewTab.webViewModel.title ??
                                webViewTab.webViewModel.url?.toString() ??
                                "",
                            maxLines: 2,
                            style: TextStyle(
                              color: webViewTab.webViewModel.isIncognitoMode ||
                                      isCurrentTab
                                  ? Colors.white
                                  : Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis),
                        subtitle:
                            Text(webViewTab.webViewModel.url?.toString() ?? "",
                                style: TextStyle(
                                  color:
                                      webViewTab.webViewModel.isIncognitoMode ||
                                              isCurrentTab
                                          ? Colors.white60
                                          : Colors.black54,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                size: 20.0,
                                color:
                                    webViewTab.webViewModel.isIncognitoMode ||
                                            isCurrentTab
                                        ? Colors.white60
                                        : Colors.black54,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (webViewTab.webViewModel.tabIndex !=
                                      null) {
                                    windowModel.closeTab(
                                        webViewTab.webViewModel.tabIndex!);
                                    if (windowModel.webViewTabs.isEmpty) {
                                      browserModel.showTabScroller = false;
                                    }
                                  }
                                });
                              },
                            )
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: screenshotImage,
                    )
                  ],
                );
              }).toList(),
              onTap: (index) async {
                browserModel.showTabScroller = false;
                windowModel.showTab(index);
              },
            )));
  }
}

/// Обрезает страницу по высоте карточки и скругляет нижние углы как у неё.
class _PageClipper extends CustomClipper<RRect> {
  final double height;
  final double radius;

  _PageClipper(this.height, this.radius);

  @override
  RRect getClip(Size size) => RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, size.width, height.clamp(0.0, size.height)),
        bottomLeft: Radius.circular(radius),
        bottomRight: Radius.circular(radius),
      );

  @override
  bool shouldReclip(_PageClipper old) =>
      old.height != height || old.radius != radius;
}

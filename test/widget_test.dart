import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_browser/browser.dart';
import 'package:flutter_browser/glass/glass_bar_controller.dart';
import 'package:flutter_browser/glass/glass.dart';
import 'package:flutter_browser/glass/glass_bottom_bar.dart';
import 'package:flutter_browser/glass/glass_tabs_page.dart';
import 'package:flutter_browser/glass/start_page.dart';
import 'package:flutter_browser/glass/tab_swipe.dart';
import 'package:flutter_browser/glass/tabs_transition.dart';
import 'package:flutter_browser/main.dart';
import 'package:flutter_browser/models/browser_model.dart';
import 'package:flutter_browser/models/webview_model.dart';
import 'package:flutter_browser/models/window_model.dart';
import 'package:flutter_browser/webview_tab.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview_android/flutter_inappwebview_android.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

late BrowserModel browserModel;
late WindowModel windowModel;

Widget app() {
  browserModel = BrowserModel();
  final webViewModel = WebViewModel();
  windowModel = WindowModel(id: null);
  windowModel.setCurrentWebViewModel(webViewModel);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: browserModel),
      ChangeNotifierProvider.value(value: webViewModel),
      ChangeNotifierProvider.value(value: windowModel),
    ],
    child: const FlutterBrowserApp(),
  );
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() {
    WEB_ARCHIVE_DIR = '/tmp';
    TAB_VIEWER_BOTTOM_OFFSET_1 = 150.0;
    TAB_VIEWER_BOTTOM_OFFSET_2 = 160.0;
    TAB_VIEWER_BOTTOM_OFFSET_3 = 170.0;
    AndroidInAppWebViewPlatform.registerWith();
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'com.pichillilorenzo.flutter_browser.intent_data'),
            (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'com.pichillilorenzo/flutter_inappwebview_manager'),
            (call) async => null);
  });

  testWidgets('starts on Android', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.byType(Browser), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  test('page ends above the glass strip, full height when compact or fullscreen',
      () {
    final bar = GlassBarController.instance;
    const screen = Size(360, 780);
    const pad = EdgeInsets.only(top: 24, bottom: 16);
    bar.reset();
    expect(bar.pageRect(screen, pad), const Rect.fromLTRB(0, 24, 360, 696));
    bar.setCompact(true);
    expect(bar.pageRect(screen, pad).bottom, 780);
    bar.setCompact(false);
    bar.setFullscreen(true);
    expect(bar.compact, isTrue);
    expect(bar.pageRect(screen, pad), const Rect.fromLTRB(0, 0, 360, 780));
    bar.setFullscreen(false);
    bar.reset();
  });

  testWidgets('new tab shows search on top and hides the bottom bar',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await settle(tester);
    windowModel
        .addTab(WebViewTab(key: GlobalKey(), webViewModel: WebViewModel()));
    await settle(tester);
    expect(find.byType(StartPage), findsOneWidget);
    // строка поиска сверху, клавиатура открылась — нижняя панель спрятана
    final search = tester.getRect(find.byType(TextField).first);
    expect(search.top, lessThan(200));
    expect(GlassBarController.instance.hidden, isTrue);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    expect(GlassBarController.instance.hidden, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 600)));
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('swipe on the capsule switches tabs; settings open',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await settle(tester);
    for (final title in ['A', 'B']) {
      windowModel.addTab(_FakeTab(
          key: GlobalKey(),
          webViewModel:
              WebViewModel(url: WebUri('about:blank'), title: title)));
    }
    await settle(tester);
    expect(windowModel.getCurrentTabIndex(), 1);

    final pill = find.text('Поиск или адрес сайта');
    await tester.drag(pill, const Offset(140, 0));
    await settle(tester);
    expect(windowModel.getCurrentTabIndex(), 0);
    await tester.drag(pill, const Offset(-140, 0));
    await settle(tester);
    expect(windowModel.getCurrentTabIndex(), 1);

    // короткий медленный свайп: страница пружинкой возвращается на место
    final gesture = await tester.startGesture(tester.getCenter(pill));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(TabSwipe.instance.offset, greaterThan(30));
    expect(TabSwipe.instance.neighbor?.title, 'A');
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await settle(tester);
    expect(windowModel.getCurrentTabIndex(), 1);
    expect(TabSwipe.instance.active, isFalse);

    // настройки: стеклянный экран, переключатель меняет настройку
    final state = tester.state<State>(find.byType(GlassBottomBar));
    (state as dynamic).goToSettingsPage();
    await settle(tester);
    expect(find.text('Настройки'), findsOneWidget);
    await tester.tap(find.text('Тёмная'));
    await settle(tester);
    expect(browserModel.getSettings().themeMode, 2);
    expect(browserModel.getSettings().blockPopups, isFalse);
    await tester.ensureVisible(find.text('Блокировать всплывающие окна'));
    await settle(tester);
    await tester.tap(find.text('Блокировать всплывающие окна'));
    await settle(tester);
    expect(browserModel.getSettings().blockPopups, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 600)));
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('page shrinks into the tabs screen and back', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await settle(tester);
    windowModel.addTab(_FakeTab(
        key: GlobalKey(),
        webViewModel: WebViewModel(url: WebUri('about:blank'), title: 'A')));
    await settle(tester);

    // сжатие панели при листании: адрес плавно уходит к домену
    GlassBarController.instance.setCompact(true);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settle(tester);
    GlassBarController.instance.setCompact(false);
    await settle(tester);

    browserModel.showTabScroller = true;
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // середина перехода: страница уже сжимается в карточку
    final mid = TabsTransition.instance;
    expect(mid.card, isNotNull);
    expect(mid.card!.width, lessThan(360));
    await settle(tester);
    expect(TabsTransition.instance.pageVisible, isFalse);

    // нажатие на карточку внутри настоящего браузера
    await tester.tap(find.descendant(
        of: find.byType(GlassTabsPage), matching: find.text('A')));
    await settle(tester);
    expect(browserModel.showTabScroller, isFalse);
    expect(find.byType(GlassTabsPage), findsNothing);

    // как в Safari: нажатия не ждут конца анимации
    final tabsButton = find.descendant(
        of: find.byType(GlassBottomBar), matching: find.byType(TabsCountIcon));
    await tester.tap(tabsButton);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // страница ещё сжимается, а карточку уже можно нажать
    await tester.tap(find
        .descendant(of: find.byType(GlassTabsPage), matching: find.text('A'))
        .hitTestable());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // карточка ещё раскрывается, а кнопка вкладок уже снова работает
    await tester.tap(tabsButton);
    await settle(tester);
    expect(browserModel.showTabScroller, isTrue);
    expect(TabsTransition.instance.t, closeTo(1, 0.01));

    // дать отложенному сохранению вкладок сработать
    // (оно сверяется с настоящими часами, а не с тестовыми)
    await tester.pumpWidget(const SizedBox());
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 600)));
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tabs page: open, pin, close, back to a tab', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    browserModel = BrowserModel();
    final webViewModel = WebViewModel();
    windowModel = WindowModel(id: null);
    windowModel.setCurrentWebViewModel(webViewModel);
    // не http — карточки не грузят значки сайтов из сети
    for (final title in ['A', 'B', 'C']) {
      windowModel.addTab(WebViewTab(
          key: GlobalKey(),
          webViewModel:
              WebViewModel(url: WebUri('about:blank'), title: title)));
    }
    browserModel.showTabScroller = true;

    // экран вкладок отдельно: WebView в тестах не создаётся
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: browserModel),
        ChangeNotifierProvider.value(value: webViewModel),
        ChangeNotifierProvider.value(value: windowModel),
      ],
      child: MaterialApp(home: GlassTabsPage()),
    ));
    await settle(tester);
    expect(find.text('Вкладки: 3'), findsOneWidget);

    // долгое нажатие на карточку — панель действий, закрепить
    await tester.longPress(find.text('A'));
    await settle(tester);
    expect(find.text('Закрепить'), findsOneWidget);
    await tester.tap(find.text('Закрепить'));
    await settle(tester);
    expect(windowModel.webViewTabs[0].webViewModel.isPinned, isTrue);

    // закрытие крестиком
    await tester.tap(find.byIcon(Icons.close_rounded).at(1));
    await settle(tester);
    expect(windowModel.webViewTabs.length, 2);

    // «Закрыть все» оставляет закреплённую
    glassTabsPageKey.currentState!.closeAllTabs();
    await settle(tester);
    expect(windowModel.webViewTabs.length, 1);
    expect(find.text('1 вкладка'), findsOneWidget);

    // разделы открываются полноценными экранами и закрываются кнопкой «назад»
    glassTabsPageKey.currentState!.showFavorites();
    await settle(tester);
    expect(find.text('В избранном пока пусто'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await settle(tester);
    glassTabsPageKey.currentState!.showHistory();
    await settle(tester);
    expect(find.text('История этой вкладки пуста'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await settle(tester);
    expect(find.text('История'), findsNothing);

    // выбор карточки раскрывает её и закрывает экран вкладок
    await tester.tap(find.text('A'));
    await settle(tester);
    expect(browserModel.showTabScroller, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}

/// Вкладка без настоящего WebView: в тестах окна Android нет.
class _FakeTab extends WebViewTab {
  const _FakeTab({super.key, required super.webViewModel});

  @override
  State<WebViewTab> createState() => _FakeTabState();
}

class _FakeTabState extends State<WebViewTab> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.white);
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_browser/browser.dart';
import 'package:flutter_browser/glass/glass_tabs_page.dart';
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

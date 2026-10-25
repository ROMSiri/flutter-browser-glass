import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_browser/browser.dart';
import 'package:flutter_browser/main.dart';
import 'package:flutter_browser/models/browser_model.dart';
import 'package:flutter_browser/models/webview_model.dart';
import 'package:flutter_browser/models/window_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('starts on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.pichillilorenzo.flutter_browser.intent_data'),
        (call) async => null);
    WEB_ARCHIVE_DIR = '/tmp';
    TAB_VIEWER_BOTTOM_OFFSET_1 = 150.0;
    TAB_VIEWER_BOTTOM_OFFSET_2 = 160.0;
    TAB_VIEWER_BOTTOM_OFFSET_3 = 170.0;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => BrowserModel()),
        ChangeNotifierProvider(create: (context) => WebViewModel()),
        ChangeNotifierProxyProvider<WebViewModel, WindowModel>(
          update: (context, webViewModel, windowModel) {
            windowModel!.setCurrentWebViewModel(webViewModel);
            return windowModel;
          },
          create: (context) => WindowModel(id: null),
        ),
      ],
      child: const FlutterBrowserApp(),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(Browser), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

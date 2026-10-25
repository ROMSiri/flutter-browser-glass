import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../glass/glass_page.dart';
import '../../glass/glass_theme.dart';
import '../../models/browser_model.dart';
import '../../models/page_settings.dart';
import '../../models/search_engine_model.dart';
import '../../models/window_model.dart';

/// Настройки браузера — в том же стеклянном стиле, что и остальные разделы.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _homeController = TextEditingController();
  String _version = "";

  @override
  void initState() {
    super.initState();
    final settings =
        Provider.of<BrowserModel>(context, listen: false).getSettings();
    _homeController.text = settings.customUrlHomePage;
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _homeController.dispose();
    super.dispose();
  }

  BrowserModel get _browser =>
      Provider.of<BrowserModel>(context, listen: false);

  void _update(void Function(BrowserSettings s) change, {bool pages = false}) {
    final settings = _browser.getSettings();
    change(settings);
    _browser.updateSettings(settings);
    _browser.save();
    if (pages) _applyToOpenTabs(settings);
    setState(() {});
  }

  /// Новые настройки страниц сразу действуют во всех открытых вкладках.
  void _applyToOpenTabs(BrowserSettings settings) {
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final dark = Theme.of(context).brightness == Brightness.dark;
    for (final tab in windowModel.webViewTabs) {
      final model = tab.webViewModel;
      final webViewSettings = model.settings ?? InAppWebViewSettings();
      applyPageSettings(webViewSettings, settings, dark: dark);
      model.settings = webViewSettings;
      model.webViewController
          ?.setSettings(settings: webViewSettings)
          .catchError((_) {});
    }
    windowModel.saveInfo();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1600),
    ));
  }

  Future<bool> _confirm(String title, String text, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Отмена")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF3B30)),
              child: Text(action)),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    final settings =
        Provider.of<BrowserModel>(context, listen: true).getSettings();
    const themes = ["Как в системе", "Светлая", "Тёмная"];

    return GlassPage(
      title: "Настройки",
      builder: (context, padding) => ListView(
        padding: padding,
        children: [
          const GlassGroupTitle("Оформление"),
          GlassGroup(children: [
            for (var i = 0; i < themes.length; i++)
              GlassCheckRow(
                title: themes[i],
                checked: settings.themeMode.clamp(0, 2) == i,
                onTap: () => _update((s) => s.themeMode = i),
              ),
          ]),
          const GlassGroupTitle("Поиск и новая вкладка"),
          GlassGroup(children: [
            GlassRow(
              icon: Icons.search_rounded,
              title: "Поисковая система",
              value: settings.searchEngine.name,
              chevron: true,
              onTap: () => pushGlassPage(
                  context, (context) => const _SearchEnginePage()),
            ),
            GlassSwitchRow(
              icon: Icons.home_outlined,
              title: "Своя домашняя страница",
              subtitle: "Открывается в новой вкладке вместо поиска",
              value: settings.homePageEnabled,
              onChanged: (v) => _update((s) => s.homePageEnabled = v),
            ),
            if (settings.homePageEnabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(60, 4, 16, 12),
                child: TextField(
                  controller: _homeController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: TextStyle(color: c.text, fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: "https://example.com",
                    hintStyle: TextStyle(color: c.muted),
                    filled: true,
                    fillColor: c.hover,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    var url = v.trim();
                    if (url.isNotEmpty && !url.contains("://")) {
                      url = "https://$url";
                    }
                    _update((s) => s.customUrlHomePage = url);
                  },
                ),
              ),
          ]),
          const GlassGroupTitle("Страницы"),
          GlassGroup(children: [
            GlassSwitchRow(
              icon: Icons.code_rounded,
              title: "JavaScript",
              subtitle: "Без него многие сайты не работают",
              value: settings.javaScriptEnabled,
              onChanged: (v) =>
                  _update((s) => s.javaScriptEnabled = v, pages: true),
            ),
            GlassSwitchRow(
              icon: Icons.zoom_in_rounded,
              title: "Масштабирование",
              subtitle: "Увеличивать страницу двумя пальцами",
              value: settings.supportZoom,
              onChanged: (v) => _update((s) => s.supportZoom = v, pages: true),
            ),
            GlassSwitchRow(
              icon: Icons.play_circle_outline_rounded,
              title: "Видео только по нажатию",
              subtitle: "Видео и звук не включаются сами",
              value: settings.mediaNeedsGesture,
              onChanged: (v) =>
                  _update((s) => s.mediaNeedsGesture = v, pages: true),
            ),
            GlassSwitchRow(
              icon: Icons.block_rounded,
              title: "Блокировать всплывающие окна",
              value: settings.blockPopups,
              onChanged: (v) => _update((s) => s.blockPopups = v, pages: true),
            ),
            GlassSwitchRow(
              icon: Icons.dark_mode_outlined,
              title: "Тёмные сайты",
              subtitle: "Затемнять светлые сайты в тёмной теме",
              value: settings.darkPages,
              onChanged: (v) => _update((s) => s.darkPages = v, pages: true),
            ),
            GlassRow(
              icon: Icons.format_size_rounded,
              title: "Размер текста",
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.remove_rounded, color: c.text),
                    onPressed: settings.textZoom <= 50
                        ? null
                        : () => _update((s) => s.textZoom -= 10, pages: true),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text("${settings.textZoom}%",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.text, fontSize: 15)),
                  ),
                  IconButton(
                    icon: Icon(Icons.add_rounded, color: c.text),
                    onPressed: settings.textZoom >= 200
                        ? null
                        : () => _update((s) => s.textZoom += 10, pages: true),
                  ),
                ],
              ),
            ),
          ]),
          const GlassGroupTitle("Данные"),
          GlassGroup(children: [
            GlassRow(
              icon: Icons.cached_rounded,
              title: "Очистить кэш",
              subtitle: "Сохранённые картинки и файлы сайтов",
              onTap: () async {
                await InAppWebViewController.clearAllCache().catchError((_) {});
                _toast("Кэш очищен");
              },
            ),
            GlassRow(
              icon: Icons.cookie_outlined,
              title: "Удалить cookie и данные сайтов",
              subtitle: "Придётся снова входить на сайты",
              destructive: true,
              onTap: () async {
                if (!await _confirm("Удалить данные сайтов?",
                    "Cookie и данные всех сайтов будут удалены.", "Удалить")) {
                  return;
                }
                await CookieManager.instance()
                    .deleteAllCookies()
                    .catchError((_) => false);
                await WebStorageManager.instance()
                    .deleteAllData()
                    .catchError((_) {});
                _toast("Данные сайтов удалены");
              },
            ),
            GlassRow(
              icon: Icons.history_rounded,
              title: "Очистить историю вкладок",
              destructive: true,
              onTap: () async {
                if (!await _confirm(
                    "Очистить историю?",
                    "История переходов во всех вкладках будет удалена.",
                    "Очистить")) {
                  return;
                }
                if (!mounted) return;
                final windowModel =
                    Provider.of<WindowModel>(context, listen: false);
                for (final tab in windowModel.webViewTabs) {
                  await tab.webViewModel.webViewController
                      ?.clearHistory()
                      .catchError((_) {});
                }
                _toast("История очищена");
              },
            ),
          ]),
          GlassGroup(children: [
            GlassRow(
              icon: Icons.restart_alt_rounded,
              title: "Сбросить настройки",
              destructive: true,
              onTap: () async {
                if (!await _confirm("Сбросить настройки?",
                    "Все настройки вернутся к исходным.", "Сбросить")) {
                  return;
                }
                _homeController.clear();
                final fresh = BrowserSettings();
                _browser.updateSettings(fresh);
                _browser.save();
                _applyToOpenTabs(fresh);
                setState(() {});
              },
            ),
          ]),
          if (_version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Center(
                child: Text("Версия $_version",
                    style: TextStyle(color: c.muted, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Выбор поисковой системы.
class _SearchEnginePage extends StatelessWidget {
  const _SearchEnginePage();

  @override
  Widget build(BuildContext context) {
    final browserModel = Provider.of<BrowserModel>(context, listen: true);
    final settings = browserModel.getSettings();
    return GlassPage(
      title: "Поисковая система",
      builder: (context, padding) => ListView(
        padding: padding,
        children: [
          GlassGroup(children: [
            for (final engine in SearchEngines)
              GlassCheckRow(
                title: engine.name,
                leading: Image.asset(engine.assetIcon, width: 24, height: 24),
                checked: settings.searchEngine == engine,
                onTap: () {
                  settings.searchEngine = engine;
                  browserModel.updateSettings(settings);
                  browserModel.save();
                },
              ),
          ]),
        ],
      ),
    );
  }
}

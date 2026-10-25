import 'package:flutter/material.dart';
import 'package:flutter_browser/custom_image.dart';
import 'package:flutter_browser/models/browser_model.dart';
import 'package:flutter_browser/models/window_model.dart';
import 'package:flutter_browser/webview_tab.dart';
import 'package:flutter_font_icons/flutter_font_icons.dart';
import 'package:provider/provider.dart';

import 'browser_actions.dart';
import 'glass.dart';
import 'glass_menu.dart';
import 'glass_theme.dart';

/// Экран вкладок: карточки со снимками страниц в две колонки
/// и стеклянная панель снизу (новая вкладка, «Готово», меню).
class GlassTabsPage extends StatefulWidget {
  const GlassTabsPage({super.key});

  @override
  State<GlassTabsPage> createState() => _GlassTabsPageState();
}

class _GlassTabsPageState extends State<GlassTabsPage>
    with BrowserActions<GlassTabsPage> {
  bool _menuOpen = false;
  Rect _anchor = Rect.zero;
  final _menuKey = GlobalKey();
  final _stackKey = GlobalKey();

  void _openTab(int index) {
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    browserModel.showTabScroller = false;
    windowModel.showTab(index);
  }

  void _closeTab(WebViewTab tab) {
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final index = tab.webViewModel.tabIndex;
    if (index == null) return;
    setState(() => windowModel.closeTab(index));
    if (windowModel.webViewTabs.isEmpty) browserModel.showTabScroller = false;
  }

  Rect _anchorRect() {
    final button = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null || stack == null) return Rect.zero;
    final topLeft = stack.globalToLocal(button.localToGlobal(Offset.zero));
    return topLeft & button.size;
  }

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    final media = MediaQuery.of(context);
    final windowModel = Provider.of<WindowModel>(context, listen: true);
    final tabs = windowModel.webViewTabs;
    final current = windowModel.getCurrentTabIndex();

    return Scaffold(
      backgroundColor: c.page,
      body: Stack(
        key: _stackKey,
        children: [
          // карточки вкладок
          Positioned.fill(
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(
                  14, media.padding.top + 64, 14, media.padding.bottom + 96),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.7,
              ),
              itemCount: tabs.length,
              itemBuilder: (context, i) => _TabCard(
                tab: tabs[i],
                isCurrent: tabs[i].webViewModel.tabIndex == current,
                onOpen: () => _openTab(i),
                onClose: () => _closeTab(tabs[i]),
              ),
            ),
          ),

          // заголовок
          Positioned(
            left: 20,
            right: 20,
            top: media.padding.top + 14,
            child: Text(
              tabs.length == 1 ? "1 вкладка" : "Вкладки: ${tabs.length}",
              style: TextStyle(
                  color: c.text, fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ),

          // меню вкладок
          Positioned.fill(
            child: GlassPopupMenu(
              open: _menuOpen,
              anchor: _anchor,
              alignRight: true,
              width: 248,
              entries: [
                GlassMenuEntry(
                    icon: MaterialCommunityIcons.incognito,
                    label: "Вкладка инкогнито",
                    onSelected: addNewIncognitoTab),
                GlassMenuEntry(
                    icon: Icons.close_rounded,
                    label: "Закрыть все вкладки",
                    enabled: tabs.isNotEmpty,
                    onSelected: closeAllTabs),
                const GlassMenuEntry.divider(),
                GlassMenuEntry(
                    icon: Icons.settings_outlined,
                    label: "Настройки",
                    onSelected: goToSettingsPage),
              ],
              onClose: () => setState(() => _menuOpen = false),
            ),
          ),

          // нижняя панель
          Positioned(
            left: 16,
            right: 16,
            bottom: media.padding.bottom + 12,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 528),
                child: Row(
                  children: [
                    StretchyGlassButton(
                      onTap: () => addNewTab(),
                      child: const Icon(Icons.add_rounded, size: 26),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, cons) => StretchyGlassButton(
                          width: cons.maxWidth,
                          height: 48,
                          onTap: () {
                            if (current >= 0) _openTab(current);
                          },
                          child: const Text(
                            "Готово",
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    StretchyGlassButton(
                      key: _menuKey,
                      onTap: () => setState(() {
                        _anchor = _anchorRect();
                        _menuOpen = !_menuOpen;
                      }),
                      child: const Icon(Icons.more_horiz_rounded, size: 26),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabCard extends StatelessWidget {
  final WebViewTab tab;
  final bool isCurrent;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  const _TabCard({
    required this.tab,
    required this.isCurrent,
    required this.onOpen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    final model = tab.webViewModel;
    final incognito = model.isIncognitoMode;
    final url = model.url;
    final faviconUrl = model.favicon != null
        ? model.favicon!.url
        : (url != null && ["http", "https"].contains(url.scheme)
            ? Uri.parse("${url.origin}/favicon.ico")
            : null);
    final title = (model.title?.isNotEmpty ?? false)
        ? model.title!
        : (url?.host.isNotEmpty ?? false)
            ? url!.host
            : "Новая вкладка";
    final cardColor = incognito ? const Color(0xFF1C1C1E) : c.card;
    final textColor = incognito ? Colors.white : c.text;

    return Dismissible(
      key: ValueKey(model.tabIndex.toString() + (url?.toString() ?? "")),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => onClose(),
      child: GestureDetector(
        onTap: onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isCurrent ? GlassColors.active : c.stroke,
              width: isCurrent ? 2.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    if (incognito)
                      const Icon(MaterialCommunityIcons.incognito,
                          size: 16, color: Colors.white)
                    else
                      CustomImage(url: faviconUrl, maxWidth: 16, height: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onClose,
                      child: SizedBox(
                        width: 36,
                        height: 40,
                        child: Icon(Icons.close_rounded,
                            size: 18, color: textColor.withOpacity(0.6)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: incognito ? const Color(0xFF2C2C2E) : Colors.white,
                  child: model.screenshot != null
                      ? Image.memory(
                          model.screenshot!,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          gaplessPlayback: true,
                        )
                      : Center(
                          child: Icon(Icons.public_rounded,
                              size: 36,
                              color: incognito
                                  ? Colors.white24
                                  : Colors.black12),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

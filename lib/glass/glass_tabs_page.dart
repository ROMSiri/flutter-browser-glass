import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_browser/custom_image.dart';
import 'package:flutter_browser/models/browser_model.dart';
import 'package:flutter_browser/models/webview_model.dart';
import 'package:flutter_browser/models/window_model.dart';
import 'package:flutter_font_icons/flutter_font_icons.dart';
import 'package:provider/provider.dart';

import 'browser_actions.dart';
import 'glass.dart';
import 'glass_menu.dart';
import 'glass_theme.dart';
import 'tabs_transition.dart';

/// Через него кнопка «назад» телефона закрывает экран вкладок с анимацией.
final glassTabsPageKey = GlobalKey<GlassTabsPageState>();

/// Экран вкладок: карточки со снимками страниц в две колонки
/// и стеклянная панель снизу (новая вкладка, «Готово», меню).
///
/// Открывается так, будто сама страница уменьшается и становится карточкой,
/// а при выборе вкладки карточка так же раскрывается обратно в страницу.
/// Карточки при закрытии и добавлении вкладок плавно переезжают на новые места.
class GlassTabsPage extends StatefulWidget {
  GlassTabsPage() : super(key: glassTabsPageKey);

  @override
  State<GlassTabsPage> createState() => GlassTabsPageState();
}

class GlassTabsPageState extends State<GlassTabsPage>
    with SingleTickerProviderStateMixin, BrowserActions<GlassTabsPage> {
  // ---- сетка ----
  static const double _side = 14;
  static const double _spacing = 14;
  static const double _aspect = 0.7;
  static const double _header = 40; // строка с названием над снимком
  static const double _radius = 22;
  static const double _topGap = 64; // место под заголовком экрана
  static const double _bottomGap = 96; // место под нижней панелью

  static const _spring =
      SpringDescription(mass: 1, stiffness: 240, damping: 29);

  /// 0 — карточка на весь экран (это страница), 1 — карточка в сетке.
  late final AnimationController _hero;
  late final ScrollController _scroll;

  /// Вкладка, которая сейчас «летит» между страницей и сеткой.
  WebViewModel? _flying;
  bool _busy = false;

  final Set<WebViewModel> _closing = {};
  late final Set<WebViewModel> _known;

  bool _menuOpen = false;
  WebViewModel? _actionTab; // вкладка, для которой открыта панель действий
  Rect _anchor = Rect.zero;
  final _menuKey = GlobalKey();
  final _stackKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    _known = windowModel.webViewTabs.map((t) => t.webViewModel).toSet();
    _flying = windowModel.getCurrentTab()?.webViewModel;
    _hero = AnimationController.unbounded(vsync: this, value: 0)
      ..addListener(_publish);
    _scroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _intro());
  }

  @override
  void dispose() {
    TabsTransition.instance.resetSilently();
    _hero.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- раскладка ----------

  List<WebViewModel> _ordered(WindowModel windowModel) {
    final all = windowModel.webViewTabs.map((t) => t.webViewModel).toList();
    // закреплённые — первыми
    return [
      ...all.where((m) => m.isPinned),
      ...all.where((m) => !m.isPinned),
    ];
  }

  Size _cardSize(Size screen) {
    final w = (screen.width - _side * 2 - _spacing) / 2;
    return Size(w, w / _aspect);
  }

  /// Место карточки в прокручиваемом содержимом.
  Rect _slot(int i, Size screen, double top) {
    final s = _cardSize(screen);
    final col = i % 2, row = i ~/ 2;
    return Rect.fromLTWH(_side + col * (s.width + _spacing),
        top + row * (s.height + _spacing), s.width, s.height);
  }

  double _contentHeight(int count, Size screen, EdgeInsets pad) {
    final s = _cardSize(screen);
    final rows = (count + 1) ~/ 2;
    return pad.top +
        _topGap +
        rows * s.height +
        math.max(0, rows - 1) * _spacing +
        pad.bottom +
        _bottomGap;
  }

  /// Где на экране страница: под строкой состояния и до самого низа.
  /// Строка с названием карточки спрятана над ней.
  Rect _pageRect(Size screen, EdgeInsets pad) => Rect.fromLTWH(
      0, pad.top - _header, screen.width, screen.height - pad.top + _header);

  // ---------- переходы ----------

  Future<void> _runHero(double to) async {
    // через setState: иначе последний кадр анимации так и остаётся
    // с отключёнными нажатиями, и карточки перестают открываться
    setState(() => _busy = true);
    final sim = SpringSimulation(_spring, _hero.value, to, _hero.velocity);
    try {
      await _hero.animateWith(sim).orCancel;
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  /// Страница уменьшается и становится карточкой.
  Future<void> _intro() async {
    if (!mounted) return;
    final media = MediaQuery.of(context);
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final order = _ordered(windowModel);
    final i = _flying != null ? order.indexOf(_flying!) : -1;
    if (i >= 0 && _scroll.hasClients) {
      // текущая вкладка — посередине экрана
      final slot = _slot(i, media.size, media.padding.top + _topGap);
      final target = slot.center.dy - media.size.height / 2;
      _scroll.jumpTo(
          target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
    }
    await _runHero(1);
    // живая страница уже лежит на месте карточки; прячем её,
    // когда готов снимок, — тогда подмена незаметна
    try {
      await TabsTransition.instance.screenshotReady
          ?.timeout(const Duration(milliseconds: 1600), onTimeout: () {});
    } catch (_) {}
    if (!mounted) return;
    // если пока ждали снимок, уже выбрали вкладку — её не трогаем
    if (_hero.value < 0.99) return;
    setState(() => _flying = null);
    _publish();
  }

  /// Где рамка летящей карточки: от страницы на весь экран до места в сетке.
  Rect _heroRect(WebViewModel model, double t) {
    final media = MediaQuery.of(context);
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final order = _ordered(windowModel);
    final page = _pageRect(media.size, media.padding);
    final i = order.indexOf(model);
    if (i < 0) return page;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final slot = _slot(i, media.size, media.padding.top + _topGap)
        .shift(Offset(0, -offset));
    return Rect.lerp(page, slot, t)!;
  }

  /// Сообщить браузеру, куда сейчас положить живую страницу.
  void _publish() {
    if (!mounted) return;
    final model = _flying;
    if (model == null) {
      TabsTransition.instance
          .update(t: _hero.value, card: null, radius: 0, pageVisible: false);
      return;
    }
    final frame = _heroRect(model, _hero.value);
    final tc = _hero.value.clamp(0.0, 1.0);
    TabsTransition.instance.update(
      t: _hero.value,
      // снимок в карточке — под строкой с названием
      card: Rect.fromLTRB(frame.left, frame.top + _header, frame.right,
          math.max(frame.top + _header, frame.bottom)),
      radius: lerpD(0, _radius, tc),
      pageVisible: true,
    );
  }

  /// Карточка раскрывается в страницу, и экран вкладок закрывается.
  Future<void> openTab(WebViewModel model) async {
    if (_busy) return;
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    setState(() {
      _menuOpen = false;
      _actionTab = null;
      _flying = model;
    });
    _publish();
    // страница под экраном вкладок переключается сразу —
    // к концу анимации она уже на месте карточки
    if (model.tabIndex != null) windowModel.showTab(model.tabIndex!);
    await _runHero(0);
    browserModel.showTabScroller = false;
  }

  /// Кнопка «назад» и «Готово»: вернуться в текущую вкладку.
  void closeToCurrent() {
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final current = windowModel.getCurrentTab()?.webViewModel;
    if (current != null) {
      openTab(current);
    } else {
      Provider.of<BrowserModel>(context, listen: false).showTabScroller = false;
    }
  }

  void _closeTab(WebViewModel model, {bool animate = true}) {
    if (_closing.contains(model)) return;
    if (!animate) {
      _removeTab(model);
      return;
    }
    setState(() => _closing.add(model));
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _closing.remove(model);
      _removeTab(model);
    });
  }

  void _removeTab(WebViewModel model) {
    final browserModel = Provider.of<BrowserModel>(context, listen: false);
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final index = model.tabIndex;
    if (index == null) return;
    setState(() => windowModel.closeTab(index));
    if (windowModel.webViewTabs.isEmpty) browserModel.showTabScroller = false;
  }

  void _openActions(WebViewModel model) {
    HapticFeedback.mediumImpact();
    setState(() {
      _menuOpen = false;
      _actionTab = model;
    });
  }

  Rect _menuAnchorRect() {
    final button = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null || stack == null) return Rect.zero;
    final topLeft = stack.globalToLocal(button.localToGlobal(Offset.zero));
    return topLeft & button.size;
  }

  // ---------- отрисовка ----------

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    final media = MediaQuery.of(context);
    final screen = media.size;
    final windowModel = Provider.of<WindowModel>(context, listen: true);
    final order = _ordered(windowModel);
    final current = windowModel.getCurrentTab()?.webViewModel;
    final gridTop = media.padding.top + _topGap;
    final barBottom = media.padding.bottom + 12;

    // панель действий растёт из нижней панели, во всю её ширину
    final actionsAnchor = Rect.fromLTWH(
        16, screen.height - barBottom - 48, screen.width - 32, 48);

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: AnimatedBuilder(
        animation: _hero,
        builder: (context, _) {
          final t = _hero.value;
          final tc = t.clamp(0.0, 1.0);
          return Stack(
            key: _stackKey,
            children: [
              // фон проявляется по мере того, как страница становится карточкой
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: c.page.withOpacity(tc)),
                ),
              ),

              // карточки
              Positioned.fill(
                child: Opacity(
                  opacity: tc,
                  child: Transform.scale(
                    scale: lerpD(0.92, 1, tc),
                    child: IgnorePointer(
                      ignoring: _busy,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: SizedBox(
                          height: _contentHeight(
                              order.length, screen, media.padding),
                          child: Stack(
                            children: [
                              for (var i = 0; i < order.length; i++)
                                _positionedCard(
                                    order[i], i, screen, gridTop, current, c),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // заголовок
              Positioned(
                left: 20,
                right: 20,
                top: media.padding.top + 14,
                child: Opacity(
                  opacity: tc,
                  child: Text(
                    order.length == 1
                        ? "1 вкладка"
                        : "Вкладки: ${order.length}",
                    style: TextStyle(
                        color: c.text,
                        fontSize: 26,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),

              // летящая карточка: страница ↔ место в сетке
              if (_flying != null) _heroCard(_flying!, t, current),

              // меню «⋯»
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
                        enabled: order.any((m) => !m.isPinned),
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

              // панель действий с вкладкой (долгое нажатие на карточку)
              Positioned.fill(
                child: GlassPopupMenu(
                  open: _actionTab != null,
                  anchor: actionsAnchor,
                  width: actionsAnchor.width,
                  entries: _actionEntries(_actionTab),
                  onClose: () => setState(() => _actionTab = null),
                ),
              ),

              // нижняя панель
              Positioned(
                left: 16,
                right: 16,
                bottom: barBottom,
                // кнопки выезжают снизу и уезжают вниз
                child: Transform.translate(
                  offset: Offset(0, 160 * (1 - tc)),
                  child: IgnorePointer(
                    ignoring: _busy,
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
                                  onTap: closeToCurrent,
                                  child: const Text(
                                    "Готово",
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            StretchyGlassButton(
                              key: _menuKey,
                              onTap: () => setState(() {
                                _anchor = _menuAnchorRect();
                                _actionTab = null;
                                _menuOpen = !_menuOpen;
                              }),
                              child: const Icon(Icons.more_horiz_rounded,
                                  size: 26),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _positionedCard(WebViewModel model, int i, Size screen, double top,
      WebViewModel? current, GlassColors c) {
    final slot = _slot(i, screen, top);
    final isNew = !_known.contains(model);
    if (isNew) _known.add(model);
    final closing = _closing.contains(model);
    final lifted = _actionTab == model;

    Widget card = _TabCardView(
      model: model,
      isCurrent: model == current,
      onClose: () => _closeTab(model),
    );

    card = GestureDetector(
      onTap: () => openTab(model),
      onLongPress: () => _openActions(model),
      child: card,
    );

    card = AnimatedScale(
      scale: closing ? 0.8 : (lifted ? 1.04 : 1),
      duration: Duration(milliseconds: closing ? 200 : 260),
      curve: closing ? Curves.easeIn : Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: closing ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: card,
      ),
    );

    // новая карточка (например, копия вкладки) вырастает на своём месте
    if (isNew) {
      card = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        builder: (context, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: lerpD(0.7, 1, v), child: child),
        ),
        child: card,
      );
    }

    card = Dismissible(
      key: ObjectKey(model),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => _closeTab(model, animate: false),
      child: card,
    );

    return AnimatedPositioned(
      key: ObjectKey(model),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      left: slot.left,
      top: slot.top,
      width: slot.width,
      height: slot.height,
      // пока карточка летит, её место в сетке пустое
      child: Visibility(
        visible: model != _flying,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: card,
      ),
    );
  }

  Widget _heroCard(WebViewModel model, double t, WebViewModel? current) {
    final rect = _heroRect(model, t);
    final tc = t.clamp(0.0, 1.0);
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: _TabCardView(
          model: model,
          isCurrent: model == current,
          radius: lerpD(0, _radius, tc),
          chrome: tc,
        ),
      ),
    );
  }

  List<GlassMenuEntry> _actionEntries(WebViewModel? model) {
    if (model == null) return const [];
    final hasUrl = model.url != null && model.url.toString().isNotEmpty;
    final others = Provider.of<WindowModel>(context, listen: false)
        .webViewTabs
        .any((t) => t.webViewModel != model && !t.webViewModel.isPinned);
    return [
      GlassMenuEntry(
          icon: Icons.open_in_full_rounded,
          label: "Открыть",
          onSelected: () => openTab(model)),
      GlassMenuEntry(
          icon: model.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          label: model.isPinned ? "Открепить" : "Закрепить",
          onSelected: () => togglePinTab(model)),
      GlassMenuEntry(
          icon: Icons.copy_all_rounded,
          label: "Дублировать",
          enabled: hasUrl,
          onSelected: () => duplicateTab(model)),
      GlassMenuEntry(
          icon: Icons.link_rounded,
          label: "Копировать ссылку",
          enabled: hasUrl,
          onSelected: () => copyTabLink(model)),
      GlassMenuEntry(
          icon: Icons.ios_share_rounded,
          label: "Поделиться",
          enabled: hasUrl,
          onSelected: () => shareTab(model)),
      const GlassMenuEntry.divider(),
      GlassMenuEntry(
          icon: Icons.tab_unselected_rounded,
          label: "Закрыть другие вкладки",
          enabled: others,
          onSelected: () => closeOtherTabs(model)),
      GlassMenuEntry(
          icon: Icons.close_rounded,
          label: "Закрыть вкладку",
          onSelected: () => _closeTab(model)),
    ];
  }
}

/// Карточка вкладки: строка с названием и снимок страницы.
/// [chrome] — насколько видны строка с названием и рамка (0 у летящей
/// карточки, пока она ещё страница на весь экран).
class _TabCardView extends StatelessWidget {
  final WebViewModel model;
  final bool isCurrent;
  final VoidCallback? onClose;
  final double radius;
  final double chrome;

  const _TabCardView({
    required this.model,
    required this.isCurrent,
    this.onClose,
    this.radius = 22,
    this.chrome = 1,
  });

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
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
    final borderColor = c.stroke;

    return Container(
      decoration: BoxDecoration(
        color: cardColor.withOpacity(chrome),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor.withOpacity(borderColor.opacity * chrome),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: Opacity(
              opacity: chrome,
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
                  if (model.isPinned)
                    Padding(
                      padding: EdgeInsets.only(right: onClose == null ? 12 : 0),
                      child: Icon(Icons.push_pin,
                          size: 14, color: textColor.withOpacity(0.6)),
                    ),
                  if (onClose != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onClose,
                      child: SizedBox(
                        width: 36,
                        height: 40,
                        child: Icon(Icons.close_rounded,
                            size: 18, color: textColor.withOpacity(0.6)),
                      ),
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
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
                          color: incognito ? Colors.white24 : Colors.black12),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

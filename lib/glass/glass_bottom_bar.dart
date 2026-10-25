import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_browser/models/webview_model.dart';
import 'package:flutter_browser/models/window_model.dart';
import 'package:flutter_font_icons/flutter_font_icons.dart';
import 'package:provider/provider.dart';

import 'browser_actions.dart';
import 'glass.dart';
import 'glass_bar_controller.dart';
import 'glass_menu.dart';
import 'glass_theme.dart';
import 'spring.dart';

enum _Part { menu, pill, tabs }

/// Нижняя панель браузера: слева кнопка меню, по центру адресная строка,
/// справа кнопка вкладок. Три отдельные стеклянные формы одной высоты.
///
/// • Листаешь страницу вниз — адресная строка сжимается до домена,
///   а кнопки уменьшаются, размываются и уходят под неё.
/// • Каждая часть сама по себе: зажал — чуть увеличилась, тянешь — туго тянется,
///   отпустил — пружинкой на место. Под пальцем — синяя.
/// • Кнопка меню открывает пружинную панель меню.
///
/// Ставится в Stack поверх страницы на весь экран (Positioned.fill).
class GlassBottomBar extends StatefulWidget {
  final VoidCallback? onFindOnPage;

  const GlassBottomBar({super.key, this.onFindOnPage});

  @override
  State<GlassBottomBar> createState() => _GlassBottomBarState();
}

class _GlassBottomBarState extends State<GlassBottomBar>
    with TickerProviderStateMixin, BrowserActions<GlassBottomBar> {
  // ---- размеры ----
  static const double _h = 48; // высота кнопок и адресной строки
  static const double _gap = 10; // между кнопками и строкой
  static const double _margin = 16;
  static const double _maxW = 560;
  static const double _compactW = 180;
  static const double _compactH = 36;
  static const double _bottom = 12; // над системной полоской
  static const double _hideBlur = 4;

  late final StretchController _menuS;
  late final StretchController _pillS;
  late final StretchController _tabsS;
  late final SpringAnimator _compact; // 0 — обычная, 1 — сжатая
  late final SpringAnimator _edit; // 0 — адрес, 1 — ввод адреса
  late final SpringAnimator _hide; // 1 — панель уехала вниз

  final _stackKey = GlobalKey();
  final _urlController = TextEditingController();
  final _urlFocus = FocusNode();

  _Part? _pressed;
  _Part? _hot;
  Offset _downAt = Offset.zero;
  bool _moved = false;
  bool _longPressed = false;
  bool _wasCompact = false; // нажали на сжатую панель — только раскрыть
  Timer? _longPressTimer;

  bool _menuOpen = false;
  bool _tabsMenuOpen = false;
  bool _editing = false;

  // последняя геометрия — для нажатий
  Rect _pillRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    _menuS = StretchController(vsync: this, growTo: 1.04);
    _pillS = StretchController(vsync: this, growTo: 1.015);
    _tabsS = StretchController(vsync: this, growTo: 1.04);
    _compact = SpringAnimator(vsync: this, params: (_) => Springs.morph);
    _edit = SpringAnimator(vsync: this, params: (_) => Springs.morph);
    _hide = SpringAnimator(
        vsync: this,
        initial: GlassBarController.instance.hidden ? 1 : 0,
        params: (_) => Springs.morph);
    GlassBarController.instance.addListener(_onCompactChanged);
    _urlFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    GlassBarController.instance.removeListener(_onCompactChanged);
    _longPressTimer?.cancel();
    _menuS.dispose();
    _pillS.dispose();
    _tabsS.dispose();
    _compact.dispose();
    _edit.dispose();
    _hide.dispose();
    _urlController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  // ---------- сжатие при листании ----------

  void _onCompactChanged() {
    final hidden = GlassBarController.instance.hidden;
    if ((_hide.target == 1) != hidden) {
      if (hidden) {
        setState(() {
          _menuOpen = false;
          _tabsMenuOpen = false;
        });
      }
      _hide.animateTo(hidden ? 1 : 0);
    }
    final compact = GlassBarController.instance.compact;
    if (compact && (_editing || _pressed != null)) {
      // пока палец на панели или идёт ввод адреса — не сжимаемся
      scheduleMicrotask(() => GlassBarController.instance.setCompact(false));
      return;
    }
    if (compact && (_menuOpen || _tabsMenuOpen)) {
      setState(() {
        _menuOpen = false;
        _tabsMenuOpen = false;
      });
    }
    _compact.animateTo(compact ? 1 : 0);
  }

  void _expand() {
    GlassBarController.instance.setCompact(false);
    _compact.animateTo(0);
  }

  // ---------- ввод адреса ----------

  void _startEditing() {
    final webViewModel = Provider.of<WebViewModel>(context, listen: false);
    _urlController.text = webViewModel.url?.toString() ?? "";
    _urlController.selection =
        TextSelection(baseOffset: 0, extentOffset: _urlController.text.length);
    setState(() => _editing = true);
    _edit.animateTo(1);
    _urlFocus.requestFocus();
  }

  void _stopEditing() {
    if (!_editing) return;
    setState(() => _editing = false);
    _edit.animateTo(0);
    _urlFocus.unfocus();
  }

  void _onFocusChanged() {
    if (!_urlFocus.hasFocus && _editing) _stopEditing();
  }

  // ---------- палец ----------

  Offset _toLocal(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  Rect _menuRect = Rect.zero;
  Rect _tabsRect = Rect.zero;

  _Part? _partAt(Offset global) {
    final p = _toLocal(global);
    if (_menuRect.inflate(4).contains(p)) return _Part.menu;
    if (_tabsRect.inflate(4).contains(p)) return _Part.tabs;
    if (_pillRect.inflate(4).contains(p)) return _Part.pill;
    return null;
  }

  StretchController _stretchOf(_Part part) => switch (part) {
        _Part.menu => _menuS,
        _Part.pill => _pillS,
        _Part.tabs => _tabsS,
      };

  void _onDown(_Part part, PointerDownEvent e) {
    if (_editing && part == _Part.pill)
      return; // в поле ввода — обычная работа с текстом
    _pressed = part;
    _downAt = e.position;
    _moved = false;
    _longPressed = false;
    _wasCompact = _compact.value > 0.5;
    if (GlassBarController.instance.compact || _compact.target == 1) {
      _expand(); // при зажатии сжатая панель раскрывается
    }
    _stretchOf(part).press();
    setState(() => _hot = part);

    _longPressTimer?.cancel();
    if (part == _Part.tabs) {
      _longPressTimer = Timer(const Duration(milliseconds: 450), () {
        if (_pressed == _Part.tabs && !_moved && mounted) {
          _longPressed = true;
          HapticFeedback.mediumImpact();
          setState(() {
            _tabsMenuOpen = true;
            _menuOpen = false;
          });
        }
      });
    }
  }

  void _onMove(_Part part, PointerMoveEvent e) {
    if (_pressed != part) return;
    final dx = e.position.dx - _downAt.dx, dy = e.position.dy - _downAt.dy;
    if (dx * dx + dy * dy > 100) _moved = true;
    _stretchOf(part).pull(dx, dy);
    final over = _partAt(e.position) == part ? part : null;
    if (over != _hot) setState(() => _hot = over); // ушёл — синий гаснет
  }

  void _onUp(_Part part, PointerUpEvent e) {
    if (_pressed != part) return;
    _pressed = null;
    _longPressTimer?.cancel();
    _stretchOf(part).release();
    final over = _partAt(e.position) == part;
    setState(() => _hot = null);
    if (_longPressed) return;

    // свайп по капсуле вбок — соседняя вкладка
    final dx = e.position.dx - _downAt.dx, dy = e.position.dy - _downAt.dy;
    if (part == _Part.pill &&
        !_editing &&
        dx.abs() > 48 &&
        dx.abs() > dy.abs() * 1.4) {
      _switchTab(dx < 0 ? 1 : -1);
      return;
    }

    if (!over || _wasCompact || _moved) return;
    _onTap(part, _toLocal(e.position));
  }

  /// Влево — следующая вкладка, вправо — предыдущая.
  void _switchTab(int delta) {
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    final count = windowModel.webViewTabs.length;
    final index = windowModel.getCurrentTabIndex() + delta;
    if (count < 2 || index < 0 || index >= count) {
      HapticFeedback.lightImpact(); // дальше вкладок нет
      return;
    }
    HapticFeedback.selectionClick();
    GlassBarController.instance.reset();
    windowModel.showTab(index);
  }

  void _onCancel(_Part part) {
    if (_pressed != part) return;
    _pressed = null;
    _longPressTimer?.cancel();
    _stretchOf(part).release();
    setState(() => _hot = null);
  }

  void _onTap(_Part part, Offset local) {
    switch (part) {
      case _Part.menu:
        setState(() {
          _menuOpen = !_menuOpen;
          _tabsMenuOpen = false;
        });
        break;
      case _Part.tabs:
        setState(() {
          _menuOpen = false;
          _tabsMenuOpen = false;
        });
        openTabViewer();
        break;
      case _Part.pill:
        if (_editing) return;
        final x = local.dx - _pillRect.left;
        if (x < 44) {
          showUrlInfo(); // замок — сведения о сайте
        } else {
          _startEditing();
        }
        break;
    }
  }

  Widget _listen(_Part part, Widget child) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _onDown(part, e),
      onPointerMove: (e) => _onMove(part, e),
      onPointerUp: (e) => _onUp(part, e),
      onPointerCancel: (_) => _onCancel(part),
      child: child,
    );
  }

  // ---------- отрисовка ----------

  @override
  Widget build(BuildContext context) {
    final windowModel = Provider.of<WindowModel>(context, listen: true);
    final webViewModel = Provider.of<WebViewModel>(context, listen: true);
    return LayoutBuilder(
      key: _stackKey,
      builder: (context, constraints) {
        final size = constraints.biggest;
        final w = math.min(size.width, _maxW);
        final x0 = (size.width - w) / 2;
        final cy = _centerY(context, size);

        // где кнопки стоят в покое — от них растёт меню
        final menuAnchor = Rect.fromCenter(
            center: Offset(x0 + _margin + _h / 2, cy), width: _h, height: _h);
        final tabsAnchor = Rect.fromCenter(
            center: Offset(x0 + w - _margin - _h / 2, cy),
            width: _h,
            height: _h);

        return Stack(
          children: [
            // меню перестраиваются только когда меняются их пункты,
            // а не на каждом кадре анимации панели
            Positioned.fill(
              child: GlassPopupMenu(
                open: _menuOpen,
                anchor: menuAnchor,
                entries: _menuEntries(webViewModel),
                quickActions: _quickActions(webViewModel),
                onClose: () => setState(() => _menuOpen = false),
              ),
            ),
            Positioned.fill(
              child: GlassPopupMenu(
                open: _tabsMenuOpen,
                anchor: tabsAnchor,
                alignRight: true,
                width: 248,
                entries: _tabsEntries(windowModel),
                onClose: () => setState(() => _tabsMenuOpen = false),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge(
                      [_menuS, _pillS, _tabsS, _compact, _edit, _hide]),
                  builder: (context, _) {
                    final bar =
                        _buildBar(context, size, webViewModel, windowModel);
                    final h = _hide.value;
                    // поиск новой вкладки: капсула и кнопки уезжают вниз
                    return IgnorePointer(
                      ignoring: GlassBarController.instance.hidden,
                      child: Transform.translate(
                        offset: Offset(0, 160 * h),
                        child: bar,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Середина панели по высоте. Клавиатура ложится поверх страницы,
  /// а панель поднимается над ней только пока вводится адрес.
  double _centerY(BuildContext context, Size size) {
    final media = MediaQuery.of(context);
    final keyboard = _editing ? media.viewInsets.bottom + 8 : 0.0;
    final gap = math.max(media.padding.bottom + _bottom, keyboard);
    return size.height - gap - _h / 2;
  }

  Widget _buildBar(BuildContext context, Size size, WebViewModel webViewModel,
      WindowModel windowModel) {
    final c = GlassColors.of(context);

    final w = math.min(size.width, _maxW);
    final x0 = (size.width - w) / 2;
    final cy = _centerY(context, size);

    final t = _compact.value; // с пружинкой может чуть перескочить
    final tc = t.clamp(0.0, 1.0);
    final e = _edit.value.clamp(0.0, 1.0);

    // общая высота: кнопки и строка всегда одинаковые
    final h = lerpD(lerpD(_h, _compactH, t), _h, e);

    // ---- адресная строка ----
    final pl0 = x0 + _margin + _h + _gap, pr0 = x0 + w - _margin - _h - _gap;
    final pw0 = pr0 - pl0;
    var pw = lerpD(pw0, math.min(_compactW, pw0), t);
    pw = lerpD(pw, w - _margin * 2, e); // при вводе — на всю ширину
    final pcx = size.width / 2;
    final dP = _pillS.deform;
    // широкая форма тянется в пикселях, иначе разъедется
    // вбок капсула тянется только в ту сторону, куда тянут:
    // противоположный край стоит на месте
    final pW = pw * dP.grow - dP.vert * 0.5;
    final pullDir = dP.tx.sign;
    final pullExt = dP.side * 1.1;
    final pH = h * dP.grow + dP.vert * 0.45 - dP.side * 0.12;
    var pL = pcx - pW / 2 - (pullDir < 0 ? pullExt : 0);
    var pR = pcx + pW / 2 + (pullDir > 0 ? pullExt : 0);

    // ---- кнопки: подъезжают к строке, затем размываются и уходят под неё ----
    final tMove = math.max(math.min(1.05, t * 1.35), e);
    final hide = math.max(((tc - 0.2) / 0.7).clamp(0.0, 1.0), e);
    final hideScale = lerpD(1, 0.6, hide);

    Rect button(_Part part, double dir, double restX) {
      final d = _stretchOf(part).deform;
      final hiddenX = pcx + dir * (pw / 2 - h / 2);
      final x = lerpD(restX, hiddenX, tMove) + d.tx;
      final s = h * hideScale;
      final bw = s * d.scaleX, bh = s * d.scaleY;
      return Rect.fromCenter(
          center: Offset(x, cy + d.ty), width: bw, height: bh);
    }

    var menuR = button(_Part.menu, -1, x0 + _margin + _h / 2);
    var tabsR = button(_Part.tabs, 1, x0 + w - _margin - _h / 2);

    // части не наезжают друг на друга при растяжении:
    // упирается та, которую тянут, соседняя стоит на месте
    if (hide < 0.05) {
      const minGap = 4.0;
      var over = menuR.right - (pL - minGap);
      if (over > 0) {
        if (_pressed == _Part.menu) {
          menuR = menuR.shift(Offset(-over, 0));
        } else {
          pL += over;
        }
      }
      over = (pR + minGap) - tabsR.left;
      if (over > 0) {
        if (_pressed == _Part.tabs) {
          tabsR = tabsR.shift(Offset(over, 0));
        } else {
          pR -= over;
        }
      }
    }

    _pillRect = Rect.fromLTRB(pL, cy - pH / 2 + dP.ty, pR, cy + pH / 2 + dP.ty);
    _menuRect = menuR;
    _tabsRect = tabsR;

    final buttonsActive = tc < 0.6 && e < 0.3;

    return Stack(
      children: [
        // кнопка меню
        Positioned.fromRect(
          rect: menuR,
          child: IgnorePointer(
            ignoring: !buttonsActive,
            child: _listen(
              _Part.menu,
              _roundButton(
                c: c,
                hot: _hot == _Part.menu || _menuOpen,
                hide: hide,
                hideScale: hideScale,
                deform: _menuS.deform,
                child: const Icon(Icons.menu_rounded, size: 24),
              ),
            ),
          ),
        ),

        // кнопка вкладок
        Positioned.fromRect(
          rect: tabsR,
          child: IgnorePointer(
            ignoring: !buttonsActive,
            child: _listen(
              _Part.tabs,
              _roundButton(
                c: c,
                hot: _hot == _Part.tabs || _tabsMenuOpen,
                hide: hide,
                hideScale: hideScale,
                deform: _tabsS.deform,
                child: TabsCountIcon(count: windowModel.webViewTabs.length),
              ),
            ),
          ),
        ),

        // адресная строка — поверх кнопок
        Positioned.fromRect(
          rect: _pillRect,
          child: _listen(
            _Part.pill,
            _pill(c, webViewModel, tc, e, dP, pH),
          ),
        ),
      ],
    );
  }

  Widget _roundButton({
    required GlassColors c,
    required bool hot,
    required double hide,
    required double hideScale,
    required StretchDeform deform,
    required Widget child,
  }) {
    Widget icon = Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..scale(deform.ix * hideScale, deform.iy * hideScale),
      child: HotColor(hot: hot, color: c.text, child: child),
    );
    // уходя под капсулу, значок размывается и гаснет
    // (само стекло гаснет через fade — без Opacity, иначе пропадёт блюр)
    if (hide > 0.01) {
      final s = _hideBlur * hide;
      icon = Opacity(
        opacity: (1 - hide).clamp(0.0, 1.0),
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s),
          child: icon,
        ),
      );
    }
    return GlassBox(
      circle: true,
      fade: 1 - hide,
      child: Center(child: icon),
    );
  }

  Widget _pill(GlassColors c, WebViewModel webViewModel, double tc, double e,
      StretchDeform dP, double pH) {
    final url = webViewModel.url;
    final host = url?.host ?? "";
    final blank = url == null || url.toString() == "about:blank";
    final path = blank || url.path == "/" ? "" : url.path;
    final progress = webViewModel.progress;

    IconData leadIcon;
    Color leadColor;
    if (webViewModel.isIncognitoMode) {
      leadIcon = MaterialCommunityIcons.incognito;
      leadColor = c.text;
    } else if (url == null || url.toString().isEmpty) {
      leadIcon = Icons.search_rounded;
      leadColor = c.muted;
    } else if (url.scheme == "file") {
      leadIcon = Icons.offline_pin_outlined;
      leadColor = c.muted;
    } else if (webViewModel.isSecure) {
      leadIcon = Icons.lock_outline_rounded;
      leadColor = c.muted;
    } else {
      leadIcon = Icons.info_outline_rounded;
      leadColor = Colors.orange;
    }

    final contentScale = lerpD(1, 0.86, tc);

    Widget content;
    if (_editing) {
      content = Padding(
        padding: const EdgeInsets.only(left: 16, right: 6),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 20, color: c.muted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _urlController,
                focusNode: _urlFocus,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                style: TextStyle(color: c.text, fontSize: 16),
                cursorColor: GlassColors.active,
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: "Поиск или адрес сайта",
                  hintStyle: TextStyle(color: c.muted, fontSize: 16),
                ),
                onSubmitted: (value) {
                  openInput(value);
                  _stopEditing();
                },
              ),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: c.muted, size: 20),
              onPressed: () {
                if (_urlController.text.isNotEmpty) {
                  _urlController.clear();
                } else {
                  _stopEditing();
                }
              },
            ),
          ],
        ),
      );
    } else {
      content = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scale(dP.ix * contentScale, dP.iy * contentScale),
        child: Row(
          children: [
            SizedBox(
              width: lerpD(44, 30, tc),
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(leadIcon, size: 16, color: leadColor),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: HotColor(
                hot: _hot == _Part.pill,
                color: c.text,
                child: _AddressText(
                  host: blank || host.isEmpty ? "Поиск или адрес сайта" : host,
                  path: path,
                  t: tc,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: blank || host.isEmpty ? c.muted : null,
                  ),
                ),
              ),
            ),
            SizedBox(width: lerpD(18, 12, tc)),
          ],
        ),
      );
    }

    return GlassBox(
      child: Stack(
        children: [
          Positioned.fill(child: content),
          // загрузка страницы — тонкая синяя полоска внизу строки
          if (progress > 0 && progress < 1)
            Positioned(
              left: pH / 2,
              right: pH / 2,
              bottom: 3,
              height: 2.5,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress.clamp(0.05, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: GlassColors.active,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- пункты меню ----------

  List<GlassMenuQuickAction> _quickActions(WebViewModel webViewModel) {
    final hasPage = webViewModel.webViewController != null;
    return [
      GlassMenuQuickAction(
        icon: Icons.arrow_back_rounded,
        enabled: hasPage,
        onSelected: () => webViewModel.webViewController?.goBack(),
      ),
      GlassMenuQuickAction(
        icon: Icons.arrow_forward_rounded,
        enabled: hasPage,
        onSelected: () => webViewModel.webViewController?.goForward(),
      ),
      GlassMenuQuickAction(
        icon: Icons.refresh_rounded,
        enabled: hasPage,
        onSelected: () => webViewModel.webViewController?.reload(),
      ),
      GlassMenuQuickAction(
        icon: isCurrentFavorite()
            ? Icons.star_rounded
            : Icons.star_border_rounded,
        active: isCurrentFavorite(),
        enabled: hasPage,
        closeOnSelect: false,
        onSelected: toggleFavorite,
      ),
      GlassMenuQuickAction(
        icon: Icons.ios_share_rounded,
        enabled: hasPage,
        onSelected: share,
      ),
    ];
  }

  List<GlassMenuEntry> _menuEntries(WebViewModel webViewModel) {
    final hasPage = webViewModel.webViewController != null;
    return [
      // новая вкладка и инкогнито — по долгому нажатию на кнопку вкладок
      GlassMenuEntry(
          icon: Icons.star_border_rounded,
          label: "Избранное",
          onSelected: showFavorites),
      GlassMenuEntry(
          icon: Icons.history_rounded,
          label: "История",
          enabled: hasPage,
          onSelected: showHistory),
      GlassMenuEntry(
          icon: Icons.offline_pin_outlined,
          label: "Сохранённые страницы",
          onSelected: showWebArchives),
      GlassMenuEntry(
          icon: Icons.file_download_outlined,
          label: "Сохранить офлайн",
          enabled: hasPage,
          onSelected: saveOffline),
      const GlassMenuEntry.divider(),
      GlassMenuEntry(
          icon: Icons.search_rounded,
          label: "Найти на странице",
          enabled: hasPage,
          onSelected: widget.onFindOnPage),
      GlassMenuEntry(
          icon: Icons.desktop_windows_outlined,
          label: "Версия для ПК",
          enabled: hasPage,
          checked: webViewModel.isDesktopMode,
          onSelected: toggleDesktopMode),
      GlassMenuEntry(
          icon: MaterialCommunityIcons.cellphone_screenshot,
          label: "Скриншот",
          enabled: hasPage,
          onSelected: takeScreenshotAndShow),
      GlassMenuEntry(
          icon: Icons.dark_mode_outlined,
          label: "Тёмная тема",
          checked: isDarkTheme(),
          onSelected: toggleTheme),
      const GlassMenuEntry.divider(),
      GlassMenuEntry(
          icon: Icons.settings_outlined,
          label: "Настройки",
          onSelected: goToSettingsPage),
    ];
  }

  List<GlassMenuEntry> _tabsEntries(WindowModel windowModel) {
    return [
      GlassMenuEntry(
          icon: Icons.add_rounded,
          label: "Новая вкладка",
          onSelected: addNewTab),
      GlassMenuEntry(
          icon: MaterialCommunityIcons.incognito,
          label: "Вкладка инкогнито",
          onSelected: addNewIncognitoTab),
      GlassMenuEntry(
          icon: Icons.close_rounded,
          label: "Закрыть все вкладки",
          enabled: windowModel.webViewTabs.isNotEmpty,
          onSelected: closeAllTabs),
    ];
  }
}

/// Адрес в капсуле: домен и путь. Пока панель сжимается, путь плавно
/// сужается и гаснет, а домен так же плавно съезжает к середине —
/// без скачка от полного адреса к домену.
class _AddressText extends StatelessWidget {
  final String host;
  final String path;
  final double t; // 0 — обычная панель, 1 — сжатая
  final TextStyle style;

  const _AddressText({
    required this.host,
    required this.path,
    required this.t,
    required this.style,
  });

  static const double _fade = 18;

  @override
  Widget build(BuildContext context) {
    final textStyle = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text) {
      if (text.isEmpty) return 0;
      final painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      return painter.width;
    }

    return LayoutBuilder(builder: (context, constraints) {
      final avail = constraints.maxWidth;
      final hostW = math.min(measure(host), avail);
      final fullPathW = measure(path);
      final roomForPath = math.max(0.0, avail - hostW);
      final pathW = math.min(fullPathW, roomForPath) * (1 - t);
      final left = (avail - hostW - pathW) / 2 * t;
      final cut = fullPathW > roomForPath + 0.5;

      Widget pathText = Text(
        path,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: textStyle,
      );
      if (cut || t > 0) {
        // обрезанный край пути растворяется, а не обрывается
        pathText = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            colors: const [Colors.white, Colors.transparent],
            stops: [
              ((rect.width - _fade) / math.max(rect.width, 1)).clamp(0.0, 1.0),
              1,
            ],
          ).createShader(rect),
          child: pathText,
        );
      }

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: left,
            width: hostW,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                host,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
          ),
          if (pathW > 0.5)
            Positioned(
              left: left + hostW,
              width: pathW,
              top: 0,
              bottom: 0,
              child: Opacity(
                opacity: (1 - t * 1.3).clamp(0.0, 1.0),
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: pathText,
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

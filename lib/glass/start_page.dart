import 'package:flutter/material.dart';
import 'package:flutter_browser/custom_image.dart';
import 'package:flutter_browser/util.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../models/browser_model.dart';
import 'glass.dart';
import 'glass_bar_controller.dart';
import 'glass_theme.dart';
import 'spring.dart';

/// Страница новой вкладки: сверху стеклянная строка поиска, которая
/// выезжает пружинкой, под ней — избранное плитками.
/// Пока в строке идёт ввод, нижняя капсула с кнопками уезжает вниз.
/// Найденное открывается в этой же вкладке через [onOpen].
class StartPage extends StatefulWidget {
  final ValueChanged<WebUri> onOpen;
  final bool autofocus;

  const StartPage({super.key, required this.onOpen, this.autofocus = true});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final SpringAnimator _appear;

  @override
  void initState() {
    super.initState();
    _appear = SpringAnimator(vsync: this, params: (_) => Springs.menuOpen);
    _appear.animateTo(1);
    _focus.addListener(_onFocus);
    if (widget.autofocus) {
      // клавиатура открывается, когда строка уже выехала
      Future.delayed(const Duration(milliseconds: 260), () {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _onFocus() {
    GlassBarController.instance.setHidden(_focus.hasFocus);
  }

  @override
  void dispose() {
    GlassBarController.instance.setHidden(false);
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    _appear.dispose();
    super.dispose();
  }

  WebUri _urlFrom(String value) {
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

  void _submit(String value) {
    if (value.trim().isEmpty) return;
    _focus.unfocus();
    widget.onOpen(_urlFrom(value));
  }

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    final media = MediaQuery.of(context);
    final browserModel = Provider.of<BrowserModel>(context, listen: true);
    final settings = browserModel.getSettings();
    final favorites = browserModel.favorites.take(12).toList();
    const searchH = 52.0;
    // страница уже начинается под строкой состояния
    const searchTop = 12.0;

    return ColoredBox(
      color: c.page,
      child: Stack(
        children: [
          // логотип поисковика и избранное
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _focus.unfocus(),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, searchTop + searchH + 36, 20,
                    media.padding.bottom + 120),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: SizedBox(
                            height: 56,
                            child: Image(
                                image: AssetImage(
                                    settings.searchEngine.assetIcon)),
                          ),
                        ),
                        if (favorites.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          Text(
                            "Избранное",
                            style: TextStyle(
                                color: c.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: favorites
                                .map((f) => _tile(c, f.url, f.title, f.favicon))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // строка поиска сверху — выезжает пружинкой
          AnimatedBuilder(
            animation: _appear,
            builder: (context, child) {
              final p = _appear.value;
              return Positioned(
                left: 16,
                right: 16,
                top: searchTop - 40 * (1 - p),
                height: searchH,
                child: Opacity(
                  opacity: p.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: lerpD(0.85, 1, p),
                    child: child,
                  ),
                ),
              );
            },
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: GlassBox(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 18, right: 4),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: c.muted, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Material(
                            type: MaterialType.transparency,
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              onSubmitted: _submit,
                              textInputAction: TextInputAction.go,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              style: TextStyle(color: c.text, fontSize: 17),
                              cursorColor: GlassColors.active,
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
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded,
                              color: GlassColors.active),
                          onPressed: () => _submit(_controller.text),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(GlassColors c, WebUri? url, String? title, Favicon? favicon) {
    final faviconUrl = favicon != null
        ? favicon.url
        : WebUri("${url?.origin ?? ""}/favicon.ico");
    final name = (title?.isNotEmpty ?? false) ? title! : url?.host ?? "";
    return GestureDetector(
      onTap: () {
        if (url == null) return;
        _focus.unfocus();
        widget.onOpen(url);
      },
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
              child: CustomImage(url: faviconUrl, maxWidth: 28, height: 28),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'glass.dart';
import 'glass_theme.dart';

/// Открыть раздел (избранное, историю, настройки…) полноценным экраном:
/// он въезжает справа, предыдущий уходит влево; назад — кнопкой
/// или жестом от левого края.
Future<T?> pushGlassPage<T>(BuildContext context, WidgetBuilder builder) {
  return Navigator.of(context).push<T>(CupertinoPageRoute<T>(builder: builder));
}

/// Экран раздела: матовая шапка с кнопкой «назад» и заголовком,
/// содержимое прокручивается под ней.
class GlassPage extends StatelessWidget {
  final String title;
  final List<Widget> actions;

  /// [padding] — отступы, чтобы содержимое начиналось под шапкой
  /// и не пряталось под системной полоской снизу.
  final Widget Function(BuildContext context, EdgeInsets padding) builder;

  const GlassPage({
    super.key,
    required this.title,
    required this.builder,
    this.actions = const [],
  });

  static const double _headerH = 64;

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    final media = MediaQuery.of(context);
    final top = media.padding.top + _headerH;

    return Scaffold(
      backgroundColor: c.page,
      body: Stack(
        children: [
          Positioned.fill(
            child: builder(
              context,
              EdgeInsets.fromLTRB(12, top + 4, 12, media.padding.bottom + 24),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: top,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.page.withOpacity(0.72),
                    border: Border(bottom: BorderSide(color: c.stroke)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, media.padding.top, 12, 0),
                    child: Row(
                      children: [
                        StretchyGlassButton(
                          width: 44,
                          height: 44,
                          onTap: () => Navigator.of(context).maybePop(),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ...actions,
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
}

/// Группа строк на светлой карточке со скруглением — как в настройках телефона.
class GlassGroup extends StatelessWidget {
  final List<Widget> children;

  const GlassGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, indent: 60, color: c.hover),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Подпись над группой.
class GlassGroupTitle extends StatelessWidget {
  final String text;

  const GlassGroupTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Text(
        text,
        style: TextStyle(
            color: c.muted, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

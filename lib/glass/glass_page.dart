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

/// Строка с переключателем.
class GlassSwitchRow extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const GlassSwitchRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GlassRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: Switch.adaptive(
        value: value,
        activeColor: GlassColors.active,
        onChanged: onChanged,
      ),
    );
  }
}

/// Строка настроек: значок, название, пояснение и что-то справа.
class GlassRow extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final String? value; // текущее значение серым справа
  final Widget? trailing;
  final bool chevron; // стрелка — откроется отдельный экран
  final bool destructive;
  final VoidCallback? onTap;

  const GlassRow({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.chevron = false,
    this.destructive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    final titleColor = destructive ? const Color(0xFFFF3B30) : c.text;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: (iconColor ?? GlassColors.active).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon,
                      size: 18,
                      color: destructive
                          ? titleColor
                          : (iconColor ?? GlassColors.active)),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: TextStyle(color: titleColor, fontSize: 15.5)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!,
                            style: TextStyle(color: c.muted, fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
              if (value != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(value!,
                      style: TextStyle(color: c.muted, fontSize: 15)),
                ),
              if (trailing != null) trailing!,
              if (chevron)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.chevron_right_rounded,
                      color: c.muted, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка выбора одного варианта из нескольких — с галочкой.
class GlassCheckRow extends StatelessWidget {
  final String title;
  final Widget? leading;
  final bool checked;
  final VoidCallback onTap;

  const GlassCheckRow({
    super.key,
    required this.title,
    this.leading,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (leading != null) ...[
                SizedBox(width: 30, height: 30, child: Center(child: leading)),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Text(title,
                    style: TextStyle(color: c.text, fontSize: 15.5)),
              ),
              AnimatedOpacity(
                opacity: checked ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.check_rounded,
                    color: GlassColors.active, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

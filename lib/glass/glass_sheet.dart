import 'package:flutter/material.dart';

import 'glass.dart';
import 'glass_theme.dart';

/// Стеклянная панель снизу — для избранного, истории, сохранённых страниц и т.п.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  List<Widget> actions = const [],
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.25),
    elevation: 0,
    builder: (sheetContext) {
      return GlassSheet(title: title, actions: actions, child: builder(sheetContext));
    },
  );
}

class GlassSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;

  const GlassSheet({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, media.padding.bottom + 10),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.78),
        child: GlassBox(
          borderRadius: const BorderRadius.all(Radius.circular(28)),
          blur: 16,
          // чуть плотнее, чтобы список читался поверх любой страницы
          tint: c.tint.withOpacity((c.tint.opacity + 0.12).clamp(0.0, 1.0)),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.muted.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
                Flexible(child: child),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка списка в стеклянной панели.
class GlassListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const GlassListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[
              SizedBox(width: 30, height: 30, child: Center(child: leading)),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.text, fontSize: 15),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 12.5),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Пустой список.
class GlassEmpty extends StatelessWidget {
  final IconData icon;
  final String text;

  const GlassEmpty({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: c.muted),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(color: c.muted, fontSize: 15)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_browser/models/window_model.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'glass.dart';
import 'glass_theme.dart';

/// Поиск по странице: стеклянная строка ввода и круглые кнопки
/// «назад», «вперёд», «закрыть» — на месте нижней панели.
class GlassFindBar extends StatefulWidget {
  final VoidCallback onClose;

  const GlassFindBar({super.key, required this.onClose});

  @override
  State<GlassFindBar> createState() => _GlassFindBarState();
}

class _GlassFindBarState extends State<GlassFindBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  FindInteractionController? get _find {
    final windowModel = Provider.of<WindowModel>(context, listen: false);
    return windowModel.getCurrentTab()?.webViewModel.findInteractionController;
  }

  void _close() {
    _find?.clearMatches();
    _controller.clear();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final c = GlassColors.of(context);
    final media = MediaQuery.of(context);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, media.padding.bottom + 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: GlassBox(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, size: 20, color: c.muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              textInputAction: TextInputAction.search,
                              style: TextStyle(color: c.text, fontSize: 16),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: "Найти на странице",
                                hintStyle:
                                    TextStyle(color: c.muted, fontSize: 16),
                              ),
                              onChanged: (value) {
                                if (value.isEmpty) {
                                  _find?.clearMatches();
                                } else {
                                  _find?.findAll(find: value);
                                }
                              },
                              onSubmitted: (_) =>
                                  _find?.findNext(forward: true),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StretchyGlassButton(
                onTap: () => _find?.findNext(forward: false),
                child: const Icon(Icons.keyboard_arrow_up_rounded, size: 26),
              ),
              const SizedBox(width: 8),
              StretchyGlassButton(
                onTap: () => _find?.findNext(forward: true),
                child: const Icon(Icons.keyboard_arrow_down_rounded, size: 26),
              ),
              const SizedBox(width: 8),
              StretchyGlassButton(
                onTap: _close,
                child: const Icon(Icons.close_rounded, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

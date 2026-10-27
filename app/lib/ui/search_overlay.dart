import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/util.dart';
import 'launch.dart';
import 'theme.dart';

class _Result {
  const _Result(this.type, this.name, this.action);
  final String type;
  final String name;
  final VoidCallback action;
}

/// نافذة البحث (searchModal في الموقع): تبحث في الأقسام ثم القنوات (50 نتيجة كحد أقصى).
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({super.key, required this.state});
  final AppState state;

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
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

  void _close() => widget.state.setSearch(false);

  List<_Result> _results(String query) {
    final term = normalizeSearchText(query);
    if (term.isEmpty) return const [];
    final s = widget.state;
    final all = <_Result>[
      for (final c in s.categories.values)
        _Result('قسم', c.name, () {
          _close();
          if (c.link.isNotEmpty) {
            openExternalPage(c.link);
            return;
          }
          s.jumpToCategory(c.id);
        }),
      for (final ch in s.channels)
        _Result('قناة', ch.name, () {
          _close();
          s.openChannel(ch);
        }),
    ];
    return all.where((r) => normalizeSearchText(r.name).contains(term)).take(50).toList();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final term = normalizeSearchText(_controller.text);
    final results = _results(_controller.text);
    final maxResultsHeight = MediaQuery.sizeOf(context).height * 0.6;

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: const Color.fromRGBO(0, 0, 0, .72),
              padding: EdgeInsets.fromLTRB(16, top + 88, 16, 24),
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: () {}, // لا نغلق عند الضغط داخل الصندوق
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 620),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171717),
                    border: Border.all(color: const Color.fromRGBO(255, 255, 255, .16)),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Color.fromRGBO(0, 0, 0, .5), offset: Offset(0, 20), blurRadius: 70),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _input(term.isNotEmpty)),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _close,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text('×', style: cairo(size: 24)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxResultsHeight),
                        child: _body(term, results),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _input(bool hasText) {
    final focused = _focus.hasFocus;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: focused ? kOrangeLight : const Color.fromRGBO(255, 255, 255, .2),
          width: focused ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          if (hasText)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _controller.clear();
                setState(() {});
                _focus.requestFocus();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('×', style: cairo(size: 20, color: const Color.fromRGBO(255, 255, 255, .65))),
              ),
            ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              style: cairo(size: 16),
              cursorColor: kOrangeLight,
              decoration: InputDecoration(
                hintText: 'ابحث عن قسم أو قناة...',
                hintStyle: cairo(size: 16, color: const Color.fromRGBO(255, 255, 255, .45)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(String term, List<_Result> results) {
    if (term.isEmpty) {
      return _note('اكتب اسم قسم أو قناة للبحث');
    }
    if (results.isEmpty) {
      return _note('لا توجد نتائج مطابقة');
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: results.length,
      itemBuilder: (context, i) => _ResultRow(result: results[i]),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: cairo(size: 14, color: const Color.fromRGBO(255, 255, 255, .6)),
        ),
      );
}

class _ResultRow extends StatefulWidget {
  const _ResultRow({required this.result});
  final _Result result;

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = _pressed ? kOrangeLight : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.result.action,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: _pressed ? const Color.fromRGBO(255, 140, 0, .08) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: Color.fromRGBO(255, 255, 255, .08))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                widget.result.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cairo(size: 14, weight: 700, color: color),
              ),
            ),
            const SizedBox(width: 12),
            Text(widget.result.type, style: cairo(size: 12, color: const Color.fromRGBO(255, 255, 255, .5))),
          ],
        ),
      ),
    );
  }
}

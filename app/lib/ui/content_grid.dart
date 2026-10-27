import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'launch.dart';
import 'theme.dart';

class _GridItem {
  const _GridItem(this.title, this.img, this.onTap);
  final String title;
  final String img;
  final VoidCallback onTap;
}

/// محتوى الصفحة الرئيسية: شبكة الأقسام والقنوات (renderCurrentView في الموقع).
/// المقاسات مطابقة للموقع: بطاقة 110px، فجوة 8px، الحد الأقصى للشبكة 1200px.
class ContentGrid extends StatelessWidget {
  const ContentGrid({
    super.key,
    required this.state,
    required this.controller,
    required this.topInset,
    required this.bottomInset,
  });

  final AppState state;
  final ScrollController controller;
  final double topInset; // ارتفاع الترويسة الثابتة
  final double bottomInset; // ارتفاع الشريط السفلي الثابت

  static const double cardWidth = 110;
  static const double gap = 8;

  List<_GridItem> _items() {
    final currentId = state.currentCategoryId;
    final items = <_GridItem>[];

    void addCategory(Category c) {
      items.add(_GridItem(c.name, c.img, () {
        if (c.link.isNotEmpty) {
          openExternalPage(c.link);
          return;
        }
        state.pushCategory(c.id);
      }));
    }

    if (currentId == null) {
      for (final c in state.childrenOf('')) {
        addCategory(c);
      }
      return items;
    }
    for (final c in state.childrenOf(currentId)) {
      addCategory(c);
    }
    for (final ch in state.channelsIn(currentId)) {
      if (ch.id.isEmpty) continue;
      items.add(_GridItem(ch.name, ch.img, () => state.openChannel(ch)));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final mobile = w <= 768;
    final pad = mobile ? 12.0 : 16.0;
    final listPadding = EdgeInsets.fromLTRB(
      pad,
      topInset + (mobile ? 20 : 30), // 84/94px - ارتفاع الترويسة 64px
      pad,
      bottomInset + 36, // 100px - ارتفاع الشريط 64px
    );

    if (!state.loaded) {
      return const Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            color: kOrange,
            backgroundColor: Color(0x26FFFFFF),
          ),
        ),
      );
    }

    if (state.noLinkMessage) {
      return ListView(
        controller: controller,
        padding: listPadding,
        children: const [_MessagePill('لا يوجد رابط بث صالح لهذه القناة')],
      );
    }

    final items = _items();
    if (items.isEmpty) {
      final text = state.currentCategoryId == null
          ? 'لا توجد أقسام مضافة بعد'
          : 'عذراً، لا توجد محتويات في هذا القسم حالياً';
      return ListView(
        controller: controller,
        padding: listPadding,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: cairo(size: 14, weight: 700, color: const Color.fromRGBO(255, 255, 255, .6)),
            ),
          ),
        ],
      );
    }

    final available = min(w, 1400.0) - pad * 2;
    final gridWidth = min(available, 1200.0);
    final cols = max(1, ((gridWidth + gap) / (cardWidth + gap)).floor());
    final blockWidth = cols * cardWidth + (cols - 1) * gap;
    final rows = (items.length / cols).ceil();
    final double fontSize = (w * 0.015).clamp(11.0, 13.0).toDouble();

    return ListView.builder(
      controller: controller,
      padding: listPadding,
      itemCount: rows,
      itemBuilder: (context, row) {
        final start = row * cols;
        final end = min(start + cols, items.length);
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: blockWidth,
            child: Padding(
              padding: const EdgeInsets.only(bottom: gap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = start; i < end; i++) ...[
                    if (i > start) const SizedBox(width: gap),
                    _Card(item: items[i], mobile: mobile, fontSize: fontSize),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.item, required this.mobile, required this.fontSize});

  final _GridItem item;
  final bool mobile;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final padding = mobile ? 8.0 : 6.0;
    final imgSize = ContentGrid.cardWidth - padding * 2;
    return GestureDetector(
      onTap: item.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: ContentGrid.cardWidth,
        constraints: BoxConstraints(minHeight: mobile ? 130 : 0),
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, .92),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(color: Color.fromRGBO(0, 0, 0, .15), offset: Offset(0, 1), blurRadius: 4),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: imgSize,
                height: imgSize,
                child: _CardImage(url: item.img),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: cairo(size: fontSize, weight: 700, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(kDefaultImageAsset, fit: BoxFit.cover);
    if (url.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 300,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => const SizedBox.expand(),
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

class _MessagePill extends StatelessWidget {
  const _MessagePill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(0, 0, 0, .4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: cairo(size: 13)),
      ),
    );
  }
}

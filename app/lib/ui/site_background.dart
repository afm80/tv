import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// خلفية الموقع: body { background: url(...) center / cover no-repeat fixed }.
class SiteBackground extends StatelessWidget {
  const SiteBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: CachedNetworkImage(
          imageUrl: kBackgroundUrl,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          fadeInDuration: Duration.zero,
          placeholder: (_, __) => const SizedBox.expand(),
          errorWidget: (_, __, ___) => const SizedBox.expand(),
        ),
      ),
    );
  }
}

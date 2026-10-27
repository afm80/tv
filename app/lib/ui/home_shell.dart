import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'content_grid.dart';
import 'fa_codes.dart';
import 'fa_icon.dart';
import 'launch.dart';
import 'player_overlay.dart';
import 'search_overlay.dart';
import 'site_background.dart';
import 'theme.dart';

const double kBarHeight = 64; // ارتفاع الترويسة والشريط السفلي في الموقع

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});
  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) widget.state.reconnect();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final s = widget.state;
        final pad = MediaQuery.paddingOf(context);
        final headerH = kBarHeight + pad.top;
        final navH = kBarHeight + pad.bottom;
        final playerOpen = s.currentChannel != null;

        return PopScope(
          canPop: !s.canGoBack,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) s.back();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            resizeToAvoidBottomInset: false,
            body: Stack(
              fit: StackFit.expand,
              children: [
                const SiteBackground(),
                Positioned.fill(
                  child: Offstage(
                  offstage: playerOpen,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: ContentGrid(
                          state: s,
                          controller: _scroll,
                          topInset: headerH,
                          bottomInset: navH,
                        ),
                      ),
                      if (s.sidebarOpen)
                        Positioned(
                          top: headerH,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => s.setSidebar(false),
                            child: const ColoredBox(color: Color.fromRGBO(0, 0, 0, .45)),
                          ),
                        ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: headerH,
                        child: _SiteHeader(state: s, topInset: pad.top),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: navH,
                        child: _BottomNav(state: s, bottomInset: pad.bottom),
                      ),
                      _Sidebar(state: s, top: headerH),
                    ],
                  ),
                  ),
                ),
                if (playerOpen)
                  Positioned.fill(
                    child: PlayerOverlay(
                      key: ValueKey('player-${s.currentChannel!.id}'),
                      channel: s.currentChannel!,
                    ),
                  ),
                if (s.searchOpen && !playerOpen) SearchOverlay(state: s),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ الترويسة

class _SiteHeader extends StatelessWidget {
  const _SiteHeader({required this.state, required this.topInset});
  final AppState state;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width <= 768;
    final sidePad = mobile ? 10.0 : 14.0;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          color: const Color.fromRGBO(0, 0, 0, .78),
          padding: EdgeInsets.only(top: topInset, left: sidePad, right: sidePad),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // في الواجهة RTL: زر البحث على اليمين والقائمة على اليسار (مثل الموقع).
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _HeaderButton(
                  label: 'بحث',
                  onTap: () => state.setSearch(true),
                  child: FaIcon('FASolid', faSolidCodes['magnifying-glass']!, size: 20, color: Colors.white),
                ),
              ),
              GestureDetector(
                onTap: state.goHome,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: CachedNetworkImage(
                    imageUrl: kLogoUrl,
                    height: 48,
                    fit: BoxFit.contain,
                    fadeInDuration: Duration.zero,
                    placeholder: (_, __) => Image.asset(kLogoAsset, height: 48, fit: BoxFit.contain),
                    errorWidget: (_, __, ___) => Image.asset(kLogoAsset, height: 48, fit: BoxFit.contain),
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _HeaderButton(
                  label: 'فتح القائمة',
                  onTap: () => state.setSidebar(!state.sidebarOpen),
                  child: FaIcon('FASolid', faSolidCodes['bars']!, size: 22, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.child, required this.onTap, required this.label});
  final Widget child;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(width: 42, height: 42, child: Center(child: child)),
      ),
    );
  }
}

// ------------------------------------------------------------------ الشريط السفلي

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.state, required this.bottomInset});
  final AppState state;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          color: const Color.fromRGBO(0, 0, 0, .85),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Row(
            children: [
              // الصفحة الرئيسية (نشطة دائماً كما في الموقع).
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    state.setSidebar(false);
                    state.goHome();
                  },
                  child: Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: Text('الصفحة الرئيسية', style: cairo(size: 14, weight: 700, color: kOrangeLight)),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    state.setSidebar(false);
                    openExternalPage(state.settings.matchesLink);
                  },
                  child: Container(
                    alignment: Alignment.center,
                    child: Opacity(
                      opacity: .6,
                      child: Text(
                        state.settings.matchesTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: cairo(size: 13, weight: 700),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ القائمة الجانبية

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.state, required this.top});
  final AppState state;
  final double top;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.4; // width: 40vw
    final links = state.sidebarLinks.isNotEmpty
        ? state.sidebarLinks
        : [for (final m in kDefaultSidebarLinks) sidebarLinkFromMap(m)];

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.ease,
      top: top,
      bottom: 0,
      left: state.sidebarOpen ? 0 : -width - 8,
      width: width,
      child: Container(
        color: const Color.fromRGBO(0, 0, 0, .98),
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(kBrandImageAsset, width: 72, height: 72, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 15),
                    Text(kAppName, style: cairo(size: 18, weight: 800)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Column(
                  children: [
                    for (final l in links)
                      if (l.name.isNotEmpty && l.url.isNotEmpty) _SidebarItem(link: l),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({required this.link});
  final SidebarLink link;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final icon = sidebarIconFor(widget.link);
    final color = _pressed ? const Color(0xFFFF6600) : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () => openExternalPage(widget.link.url, inApp: false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: _pressed ? const Color.fromRGBO(255, 102, 0, .15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Center(child: FaIcon(icon.family, icon.codePoint, size: 18, color: color)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.link.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cairo(size: 14, weight: 700, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

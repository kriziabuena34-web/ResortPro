import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/notifications.dart';
import '../theme/app_theme.dart';

/// Realtime in-app banner: lumalabas sa itaas ng screen (kahit anong page)
/// kapag may bagong notification habang bukas ang app.
class InAppNotificationBanner {
  InAppNotificationBanner._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    BuildContext context,
    Map<String, dynamic> n, {
    required VoidCallback onOpen,
  }) {
    hide();
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (context) => _BannerView(
        title: notificationTitle(n),
        body: notificationBody(n),
        icon: notificationIcon(n['type'] as String?),
        onTap: () {
          hide();
          UserNotifications.instance.markRead(n);
          onOpen();
        },
        onDismiss: hide,
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(const Duration(seconds: 5), hide);
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _BannerView extends StatefulWidget {
  const _BannerView({
    required this.title,
    required this.body,
    required this.icon,
    required this.onTap,
    required this.onDismiss,
  });

  final String title;
  final String body;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<_BannerView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -1.4), end: Offset.zero)
            .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack)),
        child: Dismissible(
          key: const ValueKey('in-app-banner'),
          direction: DismissDirection.up,
          onDismissed: (_) => widget.onDismiss(),
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              onTap: widget.onTap,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Color(0x330F172A), blurRadius: 30, offset: Offset(0, 12)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: AppColors.ink.withValues(alpha: 0.86),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF14B8A6), AppColors.primary],
                              ),
                            ),
                            child: Icon(widget.icon, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.inkText, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: widget.onDismiss,
                            icon: const Icon(Icons.close, color: AppColors.inkText, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

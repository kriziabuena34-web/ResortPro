import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/admin_data.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

export 'ui_kit.dart';

/// Button para pumili ng wika (English, Filipino, Cebuano).
class LanguageMenuButton extends StatelessWidget {
  const LanguageMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final current = appLanguage.value;
    return PopupMenuButton<AppLanguage>(
      tooltip: tr('language'),
      initialValue: current,
      onSelected: (language) => setLanguage(language),
      itemBuilder: (context) => [
        for (final language in AppLanguage.values)
          CheckedPopupMenuItem<AppLanguage>(
            value: language,
            checked: language == current,
            child: Text(language.nativeName),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, size: 20), // globo (hindi na ang 文A)
            const SizedBox(width: 4),
            Text(current.shortCode, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Card na may title, ginagamit ng bawat section sa dashboard.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EDF2)),
        boxShadow: floatShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: theme.textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(22), child: child),
        ],
      ),
    );
  }
}

/// Neumorphic na KPI card. Ilagay sa `StatGrid` para pantay ang lapad.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.width,
    this.caption,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  /// Luma; hindi na kailangan kapag nasa StatGrid.
  final double? width;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = NeuCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
      child: Row(
        children: [
          // Neumorphic na "pressed" na icon well
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.70)],
              ),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6)),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                // Laging may linya para pantay ang taas ng lahat ng stat card.
                Text(
                    caption ?? ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            statusLabel(status),
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(color: Color(0xFFEDF1F4), shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label at value na magkatabi, para sa detail dialogs.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmText,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('cancel')),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmText ?? tr('confirm')),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Ipinapakita kapag hindi pa na-run ang supabase/admin_setup.sql.
class SetupNeededNotice extends StatelessWidget {
  const SetupNeededNotice({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storage_rounded, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                tr('setupNeededTitle'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(tr('setupNeededBody'), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(tr('tryAgain')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/ui_kit.dart';
import '../services/offline_cache.dart';
import '../services/session.dart';
import 'sign_in_page.dart';
import 'verification_form_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  bool _uploadingPhoto = false;
  DateTime? _offlineSavedAt;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      final profile = await supabase.from('profiles').select().eq('id', userId).single();

      List<Map<String, dynamic>> bookings = [];
      try {
        final rows = await supabase
            .from('bookings')
            .select('id, status, booking_date, total_amount, payments(amount, status)')
            .eq('client_id', userId);
        bookings = List<Map<String, dynamic>>.from(rows);
      } catch (_) {}

      OfflineCache.save('account', {'profile': profile, 'bookings': bookings});
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _bookings = bookings;
        _offlineSavedAt = null;
        _isLoading = false;
      });
    } catch (e) {
      final cached = isOfflineError(e) ? await OfflineCache.load('account') : null;
      if (!mounted) return;
      setState(() {
        if (cached != null) {
          final d = Map<String, dynamic>.from(cached.data as Map);
          _profile = Map<String, dynamic>.from(d['profile'] as Map);
          _bookings = [for (final b in d['bookings'] as List) Map<String, dynamic>.from(b as Map)];
          _offlineSavedAt = cached.savedAt;
        }
        _isLoading = false;
      });
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------------------
  // Profile picture
  // -------------------------------------------------------------------------

  Future<void> _changePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            if ('${_profile?['avatar_url'] ?? ''}'.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove photo', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removePhoto();
                },
              ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final file = await ImagePicker().pickImage(source: source, maxWidth: 800, imageQuality: 80);
    if (file == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      final bytes = await file.readAsBytes();
      final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );
      final url = supabase.storage.from('avatars').getPublicUrl(path);
      await supabase.from('profiles').update({'avatar_url': url}).eq('id', uid);
      setState(() => _profile?['avatar_url'] = url);
      _show('Profile picture updated.');
    } catch (e) {
      _show('$e'.contains('Bucket not found')
          ? 'Profile photos are not set up yet. Please ask the admin to run account_setup.sql in Supabase.'
          : 'Could not update photo: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      await supabase.from('profiles').update({'avatar_url': null}).eq('id', uid);
      setState(() => _profile?['avatar_url'] = null);
    } catch (e) {
      _show('Could not remove photo: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Username (pwedeng palitan). Ang real name ay HINDI pwedeng i-edit dito.
  // -------------------------------------------------------------------------

  Future<void> _editUsername() async {
    // Ang dialog mismo ang may-ari ng text box, kaya ligtas itong nalilinis
    // pagkatapos ng animation ng pagsara (iwas sa '_dependents.isEmpty' error).
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _UsernameDialog(initial: '${_profile?['username'] ?? ''}'),
    );
    if (value == null) return;

    try {
      final uid = supabase.auth.currentUser!.id;
      await supabase.from('profiles').update({'username': value}).eq('id', uid);
      if (!mounted) return;
      setState(() => _profile?['username'] = value);
      _show('Username updated.');
    } on PostgrestException catch (e) {
      _show(e.code == '23505' ? 'That username is already taken.' : 'Could not save username: ${e.message}');
    } catch (e) {
      _show('Could not save username: $e');
    }
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  String get _realName {
    final p = _profile;
    if (p == null) return '';
    final first = '${p['first_name'] ?? ''}'.trim();
    final last = '${p['last_name'] ?? ''}'.trim();
    if (first.isEmpty && last.isEmpty) return '';
    final middle = '${p['middle_name'] ?? ''}'.trim();
    final suffix = '${p['suffix'] ?? ''}'.trim();
    return [
      '$last,',
      first,
      if (middle.isNotEmpty && middle != 'N/A') middle,
      if (suffix.isNotEmpty && suffix != 'N/A') suffix,
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final user = supabase.auth.currentUser;
    final email = user?.email ?? '';
    final googleName = '${user?.userMetadata?['full_name'] ?? email}';
    final googlePhoto = '${user?.userMetadata?['avatar_url'] ?? user?.userMetadata?['picture'] ?? ''}';
    final photo = '${_profile?['avatar_url'] ?? ''}'.isNotEmpty ? '${_profile?['avatar_url']}' : googlePhoto;
    final username = '${_profile?['username'] ?? ''}'.trim();
    final status = '${_profile?['verification_status'] ?? 'unverified'}';
    final verified = status == 'verified';
    final realName = _realName;

    // Booking stats
    final today = DateUtils.dateOnly(DateTime.now());
    final active = _bookings.where((b) => !isInactiveStatus(b['status'] as String?)).toList();
    final upcoming = active.where((b) {
      final d = parseDate(b['booking_date']);
      return d != null && !d.isBefore(today) && b['status'] != 'completed';
    }).toList()
      ..sort((a, b) => parseDate(a['booking_date'])!.compareTo(parseDate(b['booking_date'])!));
    final completed = _bookings.where((b) => b['status'] == 'completed').length;
    final spent = _bookings.fold<double>(0, (s, b) => s + verifiedPaid(b['payments'] as List?));
    final memberSince = DateTime.tryParse(user?.createdAt ?? '');

    return AmbientBackground(
      child: RefreshIndicator(
        onRefresh: _fetchProfile,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_offlineSavedAt != null)
              OfflineNotice(
                savedAt: _offlineSavedAt!,
                margin: const EdgeInsets.only(bottom: 12),
                onRetry: _fetchProfile,
              ),
            // ---- Profile header ----
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.ink, Color(0xFF0E4D5A), AppColors.primary],
                ),
                boxShadow: floatShadow,
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _uploadingPhoto ? null : _changePhoto,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                          child: CircleAvatar(
                            radius: 48,
                            backgroundColor: const Color(0xFFDDF2EF),
                            backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
                            // Offline: walang larawan, kulay lang ang ipapakita (hindi magka-crash).
                            onBackgroundImageError: photo.isEmpty ? null : (_, _) {},
                            child: photo.isEmpty
                                ? Text(
                                    googleName.isEmpty ? '?' : googleName[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryDark,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        if (_uploadingPhoto)
                          const Positioned.fill(
                            child: CircleAvatar(
                              backgroundColor: Colors.black45,
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.accent,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.photo_camera, size: 18, color: AppColors.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    googleName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(email, style: const TextStyle(color: Color(0xFFCFE3E6), fontSize: 13)),
                  const SizedBox(height: 12),
                  _StatusPill(status: status),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ---- Booking stats (neumorphic) ----
            StatGrid(
              minWidth: 140,
              children: [
                _MiniStat(icon: Icons.event_note, label: 'Total bookings', value: '${_bookings.length}', color: AppColors.primary),
                _MiniStat(
                  icon: Icons.upcoming,
                  label: 'Upcoming',
                  value: '${upcoming.length}',
                  caption: upcoming.isEmpty ? null : formatDate(parseDate(upcoming.first['booking_date'])),
                  color: AppColors.info,
                ),
                _MiniStat(icon: Icons.task_alt, label: 'Completed stays', value: '$completed', color: AppColors.success),
                _MiniStat(icon: Icons.payments_outlined, label: 'Total spent', value: peso(spent), color: AppColors.accent),
              ],
            ),
            const SizedBox(height: 16),

            // ---- Profile details ----
            AppCard(
              child: Column(
                children: [
                  _InfoTile(
                    icon: Icons.alternate_email,
                    label: 'Username',
                    value: username.isEmpty ? 'Add a username' : '@$username',
                    muted: username.isEmpty,
                    trailing: IconButton(
                      tooltip: 'Edit username',
                      onPressed: _editUsername,
                      icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                    ),
                  ),
                  const Divider(height: 1, indent: 60),
                  _InfoTile(
                    icon: Icons.badge_outlined,
                    label: 'Real name',
                    value: realName.isEmpty ? 'Added when you verify your account' : realName,
                    muted: realName.isEmpty,
                    trailing: Tooltip(
                      message: verified
                          ? 'Your verified real name cannot be edited.'
                          : 'Your real name comes from your verification.',
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.lock_outline, color: AppColors.muted, size: 20),
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 60),
                  _InfoTile(icon: Icons.mail_outline, label: 'Google account', value: email),
                  if ('${_profile?['phone'] ?? ''}'.isNotEmpty) ...[
                    const Divider(height: 1, indent: 60),
                    _InfoTile(icon: Icons.phone_outlined, label: 'Contact', value: '${_profile?['phone']}'),
                  ],
                  if (verified) ...[
                    const Divider(height: 1, indent: 60),
                    _InfoTile(
                      icon: Icons.cake_outlined,
                      label: 'Birth date',
                      value: formatDate(parseDate(_profile?['birth_date'])),
                    ),
                    const Divider(height: 1, indent: 60),
                    _InfoTile(
                      icon: Icons.credit_card_outlined,
                      label: 'ID type',
                      value: '${_profile?['government_id_type'] ?? 'N/A'}',
                    ),
                  ],
                  const Divider(height: 1, indent: 60),
                  _InfoTile(
                    icon: Icons.calendar_today_outlined,
                    label: 'Member since',
                    value: memberSince == null ? '—' : formatDate(memberSince.toLocal()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ---- Verification ----
            if (!verified)
              GlassPanel(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          status == 'pending' ? Icons.hourglass_top : Icons.verified_user_outlined,
                          color: status == 'rejected' ? AppColors.danger : AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            switch (status) {
                              'pending' => 'Your verification is under review. Please check back later.',
                              'rejected' => 'Your verification was rejected. Please submit again with correct details.',
                              _ => 'Verify your account to start booking.',
                            },
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: status == 'rejected' ? AppColors.danger : AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (status != 'pending') ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const VerificationFormPage()),
                          );
                          _fetchProfile();
                        },
                        icon: const Icon(Icons.verified_user_outlined),
                        label: Text(status == 'rejected' ? 'Resubmit Verification' : 'Verify Account'),
                      ),
                    ],
                  ],
                ),
              ),
            if (!verified) const SizedBox(height: 16),

            // ---- Danger zone ----
            AppCard(
              child: ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.delete_forever_outlined, color: AppColors.danger, size: 20),
                ),
                title: const Text(
                  'Delete account',
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Permanently remove your account and personal data'),
                trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                onTap: _deleting ? null : _confirmDeleteAccount,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Delete account
  // -------------------------------------------------------------------------

  bool _deleting = false;

  /// Burahin ang sariling files sa storage. Tahimik na lalaktawan kapag may error.
  Future<void> _removeMyFiles(String uid) async {
    try {
      final avatars = await supabase.storage.from('avatars').list(path: uid);
      if (avatars.isNotEmpty) {
        await supabase.storage.from('avatars').remove([for (final f in avatars) '$uid/${f.name}']);
      }
    } catch (_) {}
    try {
      await supabase.storage.from('government-ids').remove(['$uid/id_front.jpg']);
    } catch (_) {}
  }

  Future<void> _confirmDeleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _DeleteAccountDialog(),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      final uid = supabase.auth.currentUser!.id;
      // Suriin muna kung may paparating na booking, bago burahin ang mga file.
      final active = await supabase
          .from('bookings')
          .select('id')
          .eq('client_id', uid)
          .inFilter('status', ['reserved', 'confirmed', 'fully_paid', 'checked_in'])
          .gte('booking_date', dateKey(DateTime.now()))
          .limit(1);
      if ((active as List).isNotEmpty) throw Exception('HAS_ACTIVE_BOOKING');

      // Burahin ang profile picture at litrato ng ID sa storage (privacy).
      await _removeMyFiles(uid);

      await supabase.rpc('delete_my_account');
      // Burado na ang account, kaya baka mag-error ang sign out sa server; ayos lang.
      try {
        await signOutCompletely();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // loading
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const SignInPage()),
        (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // loading
      setState(() => _deleting = false);
      final text = '$e';
      final message = text.contains('HAS_ACTIVE_BOOKING')
          ? 'You still have an upcoming booking. Please cancel it or wait until your stay is finished '
              'before deleting your account.'
          : text.contains('ADMIN_ACCOUNT')
              ? 'Admin accounts cannot be deleted from the app.'
              : text.contains('delete_my_account')
                  ? 'Account deletion is not set up yet. Please ask the admin to run account_setup.sql in Supabase.'
                  : 'Could not delete your account: $e';
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.info_outline, color: AppColors.warning),
          title: const Text('Account not deleted'),
          content: Text(message),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK')),
          ],
        ),
      );
    }
  }
}

/// Dialog para palitan ang username.
class _UsernameDialog extends StatefulWidget {
  const _UsernameDialog({required this.initial});
  final String initial;

  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit username'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 20,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            prefixText: '@',
            hintText: 'e.g. izia.buena',
            helperText: 'Letters, numbers, dot and underscore only.',
          ),
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.length < 3) return 'At least 3 characters.';
            if (!RegExp(r'^[A-Za-z0-9._]+$').hasMatch(t)) return 'Letters, numbers, . and _ only.';
            return null;
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// "Are you sure?" na may 3-segundong hintay bago mapindot ang Delete.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  static const _waitSeconds = 3;
  int _left = _waitSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _left <= 0;
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 40),
      title: const Text('Are you sure you want to delete your account?'),
      content: const Text(
        'This cannot be undone. Your profile, username, photo, and notifications will be removed, '
        'and you will be signed out.\n\n'
        'Your past bookings and payments stay in the resort\'s records under your name.',
        style: TextStyle(height: 1.45),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: ready ? () => Navigator.pop(context, true) : null,
          icon: ready
              ? const Icon(Icons.delete_forever)
              : SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    value: (_waitSeconds - _left) / _waitSeconds,
                  ),
                ),
          label: Text(ready ? 'Delete' : 'Delete ($_left)'),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (status) {
      'verified' => (const Color(0xFF34D399), 'Verified', Icons.verified),
      'pending' => (const Color(0xFFFBBF24), 'Pending Review', Icons.hourglass_top),
      'rejected' => (const Color(0xFFF87171), 'Rejected', Icons.cancel_outlined),
      _ => (const Color(0xFFCBD5E1), 'Not Verified', Icons.shield_outlined),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label, required this.value, required this.color, this.caption});

  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.72)]),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4),
          ),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          // Laging may linya para pantay ang taas.
          Text(
            caption ?? ' ',
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value, this.trailing, this.muted = false});

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: const Color(0xFFEDF7F5), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: muted ? AppColors.muted : AppColors.text,
                    fontStyle: muted ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing! else const SizedBox(height: 48),
        ],
      ),
    );
  }
}

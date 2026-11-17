import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/list_controls.dart';

/// Gallery manager: ang photos dito ang lalabas sa carousel ng
/// landing page ng client app. May live preview na kamukha ng landing.
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

enum _GalleryFilter { all, onLanding, hidden }

class _GalleryPageState extends State<GalleryPage> {
  final supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _images = [];
  bool _loading = true;
  bool _setupNeeded = false;
  bool _uploading = false;
  String _query = '';
  _GalleryFilter _filter = _GalleryFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await supabase
          .from('gallery_images')
          .select()
          .order('sort_order')
          .order('id');
      if (!mounted) return;
      setState(() {
        _images = List<Map<String, dynamic>>.from(rows);
        _setupNeeded = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _setupNeeded = true;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _landingImages =>
      _images.where((i) => i['show_on_landing'] == true).toList();

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _upload() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(maxWidth: 1920, imageQuality: 85);
    if (files.isEmpty) return;

    setState(() => _uploading = true);
    var nextOrder = _images.isEmpty
        ? 0
        : _images.map((i) => (i['sort_order'] as num?)?.toInt() ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    var uploaded = 0;

    try {
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final name = file.name.toLowerCase();
        final ext = name.endsWith('.png')
            ? 'png'
            : name.endsWith('.webp')
                ? 'webp'
                : 'jpg';
        final contentType = ext == 'jpg' ? 'image/jpeg' : 'image/$ext';
        final path = 'landing/${DateTime.now().millisecondsSinceEpoch}_$uploaded.$ext';

        await supabase.storage.from('gallery').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: false),
            );
        final url = supabase.storage.from('gallery').getPublicUrl(path);

        await supabase.from('gallery_images').insert({
          'storage_path': path,
          'image_url': url,
          'sort_order': nextOrder,
          'show_on_landing': true,
        });
        nextOrder++;
        uploaded++;
      }
      if (!mounted) return;
      showToast(context, tr('galleryUploaded', {'n': uploaded}));
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('galleryUploadFailed', {'e': e}));
    } finally {
      if (mounted) setState(() => _uploading = false);
      await _load();
    }
  }

  Future<void> _update(Map<String, dynamic> image, Map<String, dynamic> changes) async {
    try {
      await supabase.from('gallery_images').update(changes).eq('id', image['id']);
      await _load();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    }
  }

  Future<void> _move(Map<String, dynamic> image, int delta) async {
    final ordered = [..._images];
    final i = ordered.indexOf(image);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= ordered.length) return;
    ordered.removeAt(i);
    ordered.insert(j, image);
    setState(() => _images = ordered);

    try {
      for (var k = 0; k < ordered.length; k++) {
        if ((ordered[k]['sort_order'] as num?)?.toInt() != k) {
          await supabase.from('gallery_images').update({'sort_order': k}).eq('id', ordered[k]['id']);
          ordered[k]['sort_order'] = k;
        }
      }
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
      await _load();
    }
  }

  Future<void> _editCaption(Map<String, dynamic> image) async {
    final controller = TextEditingController(text: '${image['caption'] ?? ''}');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('editCaption')),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            decoration: InputDecoration(labelText: tr('caption'), hintText: tr('captionHint')),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(tr('save')),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _update(image, {'caption': result.isEmpty ? null : result});
  }

  Future<void> _delete(Map<String, dynamic> image) async {
    final ok = await confirmDialog(
      context,
      title: tr('deletePhotoQ'),
      message: tr('deletePhotoMsg'),
      confirmText: tr('delete'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await supabase.from('gallery_images').delete().eq('id', image['id']);
      try {
        await supabase.storage.from('gallery').remove(['${image['storage_path']}']);
      } catch (_) {}
      if (!mounted) return;
      showToast(context, tr('photoDeleted'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    }
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  static const _caps = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted);

  @override
  Widget build(BuildContext context) {
    if (_loading && _images.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_setupNeeded) {
      return SetupNeededNotice(onRetry: _load);
    }

    final landing = _landingImages.length;
    final hidden = _images.length - landing;
    final q = _query.trim().toLowerCase();
    final shown = _images.where((i) {
      final onLanding = i['show_on_landing'] == true;
      if (_filter == _GalleryFilter.onLanding && !onLanding) return false;
      if (_filter == _GalleryFilter.hidden && onLanding) return false;
      if (q.isEmpty) return true;
      return '${i['caption'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1050;

        final preview = AppCard(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.smartphone_rounded, size: 18, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Text(tr('landingPreview').toUpperCase(), style: _caps),
                  ],
                ),
                const SizedBox(height: 4),
                Text(tr('landingPreviewSub', {'n': landing}),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 16),
                _LandingPreview(images: _landingImages),
              ],
            ),
          ),
        );

        final manager = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SearchBox(
                            controller: _searchController,
                            hint: tr('searchCaptionHint'),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                          ),
                          onPressed: _uploading ? null : _upload,
                          icon: _uploading
                              ? const SizedBox(
                                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.add_photo_alternate_outlined, size: 19),
                          label: Text(_uploading ? tr('uploading') : tr('uploadPhotos')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CountTabs<_GalleryFilter>(
                        value: _filter,
                        onChanged: (v) => setState(() => _filter = v),
                        items: [
                          (value: _GalleryFilter.all, label: tr('filterAll'), count: _images.length),
                          (value: _GalleryFilter.onLanding, label: tr('onLanding'), count: landing),
                          (value: _GalleryFilter.hidden, label: tr('hiddenPhotos'), count: hidden),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_images.isEmpty || shown.isEmpty)
              AppCard(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _images.isEmpty
                      ? EmptyState(icon: Icons.photo_library_outlined, message: tr('noPhotos'))
                      : EmptyState(icon: Icons.search_off, message: tr('noPhotosMatch')),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, c) {
                  final columns = c.maxWidth >= 900
                      ? 3
                      : c.maxWidth >= 560
                          ? 2
                          : 1;
                  return CardGrid(
                    columns: columns,
                    children: [for (final image in shown) _photoCard(image)],
                  );
                },
              ),
          ],
        );

        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: pageInsets(context),
            children: [
              Text(tr('glSubtitle'), style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 14),
              _overviewCard(landing, hidden, wide: constraints.maxWidth >= 700),
              const SizedBox(height: 18),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 400, child: preview),
                    const SizedBox(width: 18),
                    Expanded(child: manager),
                  ],
                )
              else ...[
                manager,
                const SizedBox(height: 18),
                preview,
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _overviewCard(int landing, int hidden, {required bool wide}) {
    final captioned = _images.where((i) => '${i['caption'] ?? ''}'.trim().isNotEmpty).length;
    final tiles = [
      _tile(tr('glKTotal'), tr('glKTotalSub'), '${_images.length}', Colors.white, Icons.photo_library_outlined,
          () => setState(() => _filter = _GalleryFilter.all)),
      _tile(tr('glKLanding'), tr('glKLandingSub'), '$landing', const Color(0xFF4ADE80), Icons.visibility_outlined,
          () => setState(() => _filter = _GalleryFilter.onLanding)),
      _tile(tr('glKHidden'), tr('glKHiddenSub'), '$hidden', const Color(0xFF94A3B8), Icons.visibility_off_outlined,
          () => setState(() => _filter = _GalleryFilter.hidden)),
      _tile(tr('glKCaption'), tr('glKCaptionSub', {'n': _images.length - captioned}), '$captioned',
          const Color(0xFF60A5FA), Icons.short_text_rounded, null),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.collections_rounded, color: AppColors.inkText, size: 20),
              const SizedBox(width: 8),
              Text(tr('glOverview'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          if (wide)
            Row(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: tiles[i]),
                ],
              ],
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: tiles,
            ),
        ],
      ),
    );
  }

  Widget _tile(String label, String sub, String value, Color valueColor, IconData icon, VoidCallback? onTap) {
    return Material(
      color: AppColors.inkRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.inkLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.inkText, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                  Icon(icon, size: 16, color: const Color(0xFF7F93A6)),
                ],
              ),
              const SizedBox(height: 2),
              Text(sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF7F93A6), fontSize: 10.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(color: valueColor, fontSize: 24, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onTap, {Color color = AppColors.text}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: onTap == null ? AppColors.border : color),
          ),
        ),
      ),
    );
  }

  Widget _photoCard(Map<String, dynamic> image) {
    final index = _images.indexOf(image);
    final onLanding = image['show_on_landing'] == true;
    final caption = '${image['caption'] ?? ''}'.trim();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Material(
                  color: AppColors.subtle,
                  child: InkWell(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        clipBehavior: Clip.antiAlias,
                        child: InteractiveViewer(child: Image.network('${image['image_url']}')),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(
                          opacity: onLanding ? 1 : 0.4,
                          child: Image.network(
                            '${image['image_url']}',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) =>
                                const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.muted)),
                          ),
                        ),
                        if (!onLanding)
                          const Center(
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: Color(0x99000000),
                              child: Icon(Icons.visibility_off_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                        Positioned(
                          left: 10,
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xB3000000),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('#${index + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: onLanding ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(onLanding ? tr('glShown') : tr('hiddenPhotos'),
                                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: () => _editCaption(image),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          caption.isEmpty ? tr('glAddCaption') : caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: caption.isEmpty ? FontWeight.w600 : FontWeight.w600,
                            color: caption.isEmpty ? AppColors.primary : AppColors.text,
                            fontStyle: caption.isEmpty ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_outlined, size: 15, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tr('showOnLanding'),
                          style: const TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
                    ),
                    Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: onLanding,
                        onChanged: (v) => _update(image, {'show_on_landing': v}),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  children: [
                    _iconBtn(Icons.arrow_back_rounded, tr('moveEarlier'), index > 0 ? () => _move(image, -1) : null),
                    const SizedBox(width: 6),
                    _iconBtn(Icons.arrow_forward_rounded, tr('moveLater'),
                        index < _images.length - 1 ? () => _move(image, 1) : null),
                    const Spacer(),
                    _iconBtn(Icons.delete_outline_rounded, tr('delete'), () => _delete(image), color: AppColors.danger),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kamukha ng carousel sa home ng client app (may silip ng susunod na litrato).
class _LandingPreview extends StatefulWidget {
  const _LandingPreview({required this.images});
  final List<Map<String, dynamic>> images;

  @override
  State<_LandingPreview> createState() => _LandingPreviewState();
}

class _LandingPreviewState extends State<_LandingPreview> {
  final _controller = PageController(viewportFraction: 0.84);
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      final n = widget.images.length;
      if (n < 2 || !_controller.hasClients) return;
      _controller.animateToPage(
        (_page + 1) % n,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final page = images.isEmpty ? 0 : _page.clamp(0, images.length - 1);

    Widget bar(double w, {double h = 10, Color color = const Color(0xFFE6EBF0)}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        );

    return Center(
      child: Container(
        width: 330,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(40),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Container(
            color: AppColors.background,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status bar at notch
                SizedBox(
                  height: 30,
                  child: Stack(
                    children: [
                      const Positioned(
                        left: 22,
                        top: 9,
                        child: Text('9:41', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          margin: const EdgeInsets.only(top: 7),
                          width: 86,
                          height: 18,
                          decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const Positioned(
                        right: 20,
                        top: 8,
                        child: Row(
                          children: [
                            Icon(Icons.signal_cellular_alt_rounded, size: 13),
                            SizedBox(width: 3),
                            Icon(Icons.battery_full_rounded, size: 13),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Header na kamukha ng home ng app
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('glPreviewHi'),
                                style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
                            const Text("Aryana's Guests House",
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const Icon(Icons.notifications_none_rounded, size: 20),
                    ],
                  ),
                ),
                SizedBox(
                  height: 200,
                  child: images.isEmpty
                      ? Container(
                          margin: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6EBF0),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(24),
                          child: Text(tr('previewEmpty'),
                              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                        )
                      : PageView.builder(
                          controller: _controller,
                          itemCount: images.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (context, i) {
                            final caption = '${images[i]['caption'] ?? ''}'.trim();
                            return AnimatedPadding(
                              duration: const Duration(milliseconds: 300),
                              padding: EdgeInsets.symmetric(horizontal: 5, vertical: i == page ? 0 : 10),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      '${images[i]['image_url']}',
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stack) =>
                                          const Center(child: Icon(Icons.broken_image_outlined)),
                                    ),
                                    if (caption.isNotEmpty)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          padding: const EdgeInsets.fromLTRB(12, 26, 12, 12),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [Colors.transparent, Colors.black54],
                                            ),
                                          ),
                                          child: Text(caption,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < images.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == page ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == page ? AppColors.primary : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                // Placeholder ng Quick actions at packages
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final ic in const [Icons.event_available_rounded, Icons.chat_bubble_outline_rounded, Icons.map_outlined])
                            Container(
                              width: 80,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Icon(ic, color: AppColors.primary, size: 20),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      bar(110, h: 11, color: const Color(0xFFD5DDE5)),
                      const SizedBox(height: 10),
                      for (var i = 0; i < 2; i++)
                        Container(
                          height: 48,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              bar(30, h: 30),
                              const SizedBox(width: 10),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [bar(90), const SizedBox(height: 6), bar(56, h: 8)],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

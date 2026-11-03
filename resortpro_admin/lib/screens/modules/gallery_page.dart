import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
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

  @override
  Widget build(BuildContext context) {
    if (_loading && _images.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_setupNeeded) {
      return SetupNeededNotice(onRetry: _load);
    }

    final theme = Theme.of(context);
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
        final wide = constraints.maxWidth >= 1000;

        final preview = SectionCard(
          title: tr('landingPreview'),
          subtitle: tr('landingPreviewSub', {'n': _landingImages.length}),
          child: _LandingPreview(images: _landingImages),
        );

        final manager = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('allPhotos', {'n': _images.length}),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    SearchBox(
                      controller: _searchController,
                      hint: tr('searchCaptionHint'),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final f in _GalleryFilter.values)
                          ChoiceChip(
                            label: Text(switch (f) {
                              _GalleryFilter.all => tr('filterAll'),
                              _GalleryFilter.onLanding => tr('onLanding'),
                              _GalleryFilter.hidden => tr('hiddenPhotos'),
                            }),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_images.isEmpty)
              EmptyState(icon: Icons.photo_library_outlined, message: tr('noPhotos'))
            else if (shown.isEmpty)
              EmptyState(icon: Icons.search_off, message: tr('noPhotosMatch'))
            else
              LayoutBuilder(
                builder: (context, c) {
                  final columns = c.maxWidth >= 900
                      ? 4
                      : c.maxWidth >= 600
                          ? 3
                          : 2;
                  return CardGrid(
                    columns: columns,
                    children: [
                      for (final image in shown) _photoCard(theme, image),
                    ],
                  );
                },
              ),
          ],
        );

        return ModuleBody(
          fab: AppFab(
            icon: _uploading ? Icons.hourglass_top : Icons.add_photo_alternate_outlined,
            label: _uploading ? tr('uploading') : tr('uploadPhotos'),
            onPressed: _uploading ? null : _upload,
          ),
          child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: pageInsets(context, fab: true),
            children: [
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 420, child: preview),
                    const SizedBox(width: 16),
                    Expanded(child: manager),
                  ],
                )
              else ...[
                preview,
                const SizedBox(height: 16),
                manager,
              ],
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _photoCard(ThemeData theme, Map<String, dynamic> image) {
    final index = _images.indexOf(image);
    final onLanding = image['show_on_landing'] == true;
    final caption = '${image['caption'] ?? ''}'.trim();

    return AppCard(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      child: InteractiveViewer(child: Image.network('${image['image_url']}')),
                    ),
                  ),
                  child: Opacity(
                    opacity: onLanding ? 1 : 0.45,
                    child: Image.network(
                      '${image['image_url']}',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '#${index + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Text(
              caption.isEmpty ? tr('noCaption') : caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: caption.isEmpty
                  ? theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)
                  : theme.textTheme.bodyMedium,
            ),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 12, right: 4),
            title: Text(tr('showOnLanding'), style: theme.textTheme.bodySmall),
            value: onLanding,
            onChanged: (v) => _update(image, {'show_on_landing': v}),
          ),
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('moveEarlier'),
                onPressed: index > 0 ? () => _move(image, -1) : null,
                icon: const Icon(Icons.arrow_back),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('moveLater'),
                onPressed: index < _images.length - 1 ? () => _move(image, 1) : null,
                icon: const Icon(Icons.arrow_forward),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('editCaption'),
                onPressed: () => _editCaption(image),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('delete'),
                onPressed: () => _delete(image),
                icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kamukha ng carousel sa landing page ng client app.
class _LandingPreview extends StatefulWidget {
  const _LandingPreview({required this.images});
  final List<Map<String, dynamic>> images;

  @override
  State<_LandingPreview> createState() => _LandingPreviewState();
}

class _LandingPreviewState extends State<_LandingPreview> {
  final _controller = PageController();
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
        duration: const Duration(milliseconds: 400),
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
    final theme = Theme.of(context);
    final images = widget.images;

    return Center(
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: theme.colorScheme.outlineVariant, width: 6),
          color: theme.colorScheme.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pekeng app bar, para kamukha ng client app
            Container(
              height: 44,
              color: theme.colorScheme.primary,
              alignment: Alignment.center,
              child: Text(
                'ResortPro',
                style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              height: 230,
              child: images.isEmpty
                  ? Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: Text(tr('previewEmpty'), textAlign: TextAlign.center),
                    )
                  : Stack(
                      children: [
                        PageView.builder(
                          controller: _controller,
                          itemCount: images.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (context, i) => Image.network(
                            '${images[i]['image_url']}',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (context, error, stack) =>
                                const Center(child: Icon(Icons.broken_image_outlined)),
                          ),
                        ),
                        if ('${images[_page.clamp(0, images.length - 1)]['caption'] ?? ''}'.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 24, 12, 26),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black54],
                                ),
                              ),
                              child: Text(
                                '${images[_page.clamp(0, images.length - 1)]['caption']}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 8,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < images.length; i++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: i == _page ? 18 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: i == _page ? Colors.white : Colors.white54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            // Placeholder ng package cards sa ilalim ng carousel
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (var i = 0; i < 2; i++)
                    Container(
                      height: 44,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

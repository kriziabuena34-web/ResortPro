import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/booking_workflow.dart';
import '../../widgets/admin_widgets.dart';

/// Gumawa ng booking para sa walk-in o phone na guest (pwedeng walang account).
/// Ibinabalik ang true kapag na-save.
Future<bool> showNewBookingDialog(BuildContext context, AdminData data) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _NewBookingDialog(data: data),
  );
  return result ?? false;
}

class _NewBookingDialog extends StatefulWidget {
  const _NewBookingDialog({required this.data});
  final AdminData data;

  @override
  State<_NewBookingDialog> createState() => _NewBookingDialogState();
}

class _NewBookingDialogState extends State<_NewBookingDialog> {
  final supabase = Supabase.instance.client;

  String _source = 'walk_in';
  bool _existingClient = false;
  String? _clientId;
  final _guestName = TextEditingController();
  final _guestPhone = TextEditingController();

  String? _packageId;
  DateTime? _date;
  bool _checking = false;
  Map<String, dynamic>? _availability;

  final _pax = {
    'adults': TextEditingController(text: '1'),
    'children': TextEditingController(text: '0'),
    'teens': TextEditingController(text: '0'),
    'infants': TextEditingController(text: '0'),
    'elderly': TextEditingController(text: '0'),
  };
  final _eventType = TextEditingController();
  final _total = TextEditingController();
  final _payment = TextEditingController(text: '0');
  String _method = 'cash';
  final _notes = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_guestName, _guestPhone, _eventType, _total, _payment, _notes, ..._pax.values]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _totalPax => _pax.values.fold<int>(0, (s, c) => s + (int.tryParse(c.text) ?? 0));

  Map<String, dynamic>? get _package =>
      _packageId == null ? null : widget.data.packageById(_packageId);

  Future<void> _checkAvailability() async {
    final pkg = _package;
    final date = _date;
    if (pkg == null || date == null) return;

    setState(() {
      _checking = true;
      _availability = null;
    });

    Map<String, dynamic> result;
    try {
      final r = await supabase.rpc('check_availability', params: {
        'p_package_id': asInt(pkg['id']),
        'p_date': dateKey(date),
      });
      result = Map<String, dynamic>.from(r as Map);
    } catch (_) {
      // Hindi pa na-run ang SQL: lokal na check na lang.
      final taken = widget.data.bookings.any((b) =>
          '${b['package_id']}' == '${pkg['id']}' && bookingDateOf(b) == date && !isInactive(b));
      final blocked = widget.data.blocksOn(date, packageId: pkg['id']).isNotEmpty;
      result = {
        'available': !taken && !blocked,
        'reason': blocked ? 'blocked' : (taken ? 'booked' : null),
        'price': priceForLocal(pkg, date, widget.data.pricingRules),
      };
    }

    if (!mounted) return;
    setState(() {
      _availability = result;
      _checking = false;
      if (result['available'] == true) {
        final price = asDouble(result['price'] ?? pkg['price']);
        _total.text = price.toStringAsFixed(0);
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() => _date = DateUtils.dateOnly(picked));
    await _checkAvailability();
  }

  Future<void> _save() async {
    final pkg = _package;
    setState(() => _error = null);

    if (pkg == null || _date == null) {
      setState(() => _error = tr('nbErrPackageDate'));
      return;
    }
    if (_availability?['available'] != true) {
      setState(() => _error = tr('nbErrUnavailable'));
      return;
    }
    if (_existingClient ? _clientId == null : _guestName.text.trim().isEmpty) {
      setState(() => _error = tr('nbErrGuest'));
      return;
    }
    if (_totalPax <= 0) {
      setState(() => _error = tr('nbErrPax'));
      return;
    }
    final maxPax = pkg['max_pax'] == null ? null : asInt(pkg['max_pax']);
    if (maxPax != null && _totalPax > maxPax) {
      setState(() => _error = tr('nbErrCapacity', {'max': maxPax}));
      return;
    }
    final total = double.tryParse(_total.text.replaceAll(',', ''));
    final paid = double.tryParse(_payment.text.replaceAll(',', '')) ?? 0;
    if (total == null || total <= 0) {
      setState(() => _error = tr('invalidPrice'));
      return;
    }
    if (paid < 0 || paid > total + 0.01) {
      setState(() => _error = tr('overBalance', {'amount': peso(total)}));
      return;
    }

    setState(() => _saving = true);
    try {
      final fullyPaid = paid >= total - 0.01;
      final booking = await supabase
          .from('bookings')
          .insert({
            'client_id': _existingClient ? _clientId : null,
            'guest_name': _existingClient ? null : _guestName.text.trim(),
            'guest_phone': _existingClient ? null : _guestPhone.text.trim(),
            'source': _source,
            'package_id': pkg['id'],
            'booking_date': dateKey(_date!),
            'total_pax': _totalPax,
            for (final e in _pax.entries) e.key: int.tryParse(e.value.text) ?? 0,
            'total_amount': total,
            'status': fullyPaid ? 'fully_paid' : 'confirmed',
            'event_type': _eventType.text.trim().isEmpty ? null : _eventType.text.trim(),
            if (_notes.text.trim().isNotEmpty) 'admin_notes': _notes.text.trim(),
          })
          .select()
          .single();

      if (paid > 0) {
        await supabase.from('payments').insert({
          'booking_id': booking['id'],
          'amount': paid,
          'method': _method,
          'kind': fullyPaid ? 'balance' : 'downpayment',
          'received_by': supabase.auth.currentUser?.id,
          'status': 'verified',
        });
      }

      await BookingWorkflow.log(
        booking['id'],
        'created',
        toStatus: '${booking['status']}',
        note: '${sourceLabel(_source)}${paid > 0 ? ' · ${peso(paid)} ${methodLabel(_method)}' : ''}',
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      final code = BookingWorkflow.friendlyError(e);
      setState(() {
        _saving = false;
        _error = code == 'DATE_TAKEN'
            ? tr('nbErrTaken')
            : code == 'DATE_BLOCKED'
                ? tr('nbErrBlocked')
                : tr('failed', {'e': e});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pkg = _package;
    final available = _availability?['available'] == true;
    final reason = _availability?['reason'];
    final basePrice = pkg == null ? null : asDouble(pkg['price']);
    final price = _availability?['price'] == null ? null : asDouble(_availability!['price']);

    final clients = [...widget.data.clients]
      ..sort((a, b) => '${a['google_display_name'] ?? a['first_name'] ?? ''}'
          .toLowerCase()
          .compareTo('${b['google_display_name'] ?? b['first_name'] ?? ''}'.toLowerCase()));

    return AlertDialog(
      title: Text(tr('nbTitle')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Source ----
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'walk_in',
                    icon: Icon(sourceIcon('walk_in')),
                    label: Text(sourceLabel('walk_in')),
                  ),
                  ButtonSegment(
                    value: 'phone',
                    icon: Icon(sourceIcon('phone')),
                    label: Text(sourceLabel('phone')),
                  ),
                ],
                selected: {_source},
                onSelectionChanged: (s) => setState(() => _source = s.first),
              ),
              const SizedBox(height: 16),

              // ---- Guest ----
              _label(theme, tr('nbGuest')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('nbExistingClient')),
                value: _existingClient,
                onChanged: (v) => setState(() => _existingClient = v),
              ),
              if (_existingClient)
                DropdownButtonFormField<String>(
                  initialValue: _clientId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('fieldClient')),
                  items: [
                    for (final c in clients)
                      DropdownMenuItem(
                        value: '${c['id']}',
                        child: Text(
                          '${c['google_display_name'] ?? '${c['first_name'] ?? ''} ${c['last_name'] ?? ''}'}'
                          '${c['phone'] != null ? ' · ${c['phone']}' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _clientId = v),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _guestName,
                        decoration: InputDecoration(labelText: tr('nbGuestName')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _guestPhone,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(labelText: tr('fieldPhone')),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),

              // ---- Package & date ----
              _label(theme, tr('nbPackageDate')),
              DropdownButtonFormField<String>(
                initialValue: _packageId,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('navPackages')),
                items: [
                  for (final p in widget.data.packages)
                    DropdownMenuItem(
                      value: '${p['id']}',
                      child: Text('${p['name']} · ${peso(asDouble(p['price']))}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  setState(() => _packageId = v);
                  _checkAvailability();
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(_date == null ? tr('nbChooseDate') : formatDate(_date)),
              ),
              const SizedBox(height: 8),
              if (_checking)
                const LinearProgressIndicator()
              else if (_availability != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (available ? const Color(0xFF2E9E5B) : theme.colorScheme.error)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    available
                        ? tr('nbAvailable', {'price': peso(price ?? basePrice ?? 0)}) +
                            (price != null && basePrice != null && price != basePrice
                                ? '  ${tr('nbSeasonal', {'base': peso(basePrice)})}'
                                : '')
                        : reason == 'blocked'
                            ? tr('nbBlockedReason', {'note': '${_availability?['note'] ?? ''}'})
                            : tr('nbErrTaken'),
                    style: TextStyle(
                      color: available ? const Color(0xFF1E7A45) : theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // ---- Guests ----
              _label(theme, '${tr('fieldGuests')} (${tr('paxCount', {'n': _totalPax})})'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in {
                    'adults': tr('guestAdults'),
                    'children': tr('guestChildren'),
                    'teens': tr('guestTeens'),
                    'infants': tr('guestInfants'),
                    'elderly': tr('guestElderly'),
                  }.entries)
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _pax[e.key],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: e.value, isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _eventType,
                decoration: InputDecoration(labelText: '${tr('fieldEventType')} (${tr('optional')})'),
              ),
              const SizedBox(height: 16),

              // ---- Payment ----
              _label(theme, tr('nbPayment')),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _total,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: tr('fieldTotal'), prefixText: '₱ '),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _payment,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: tr('nbPaidNow'), prefixText: '₱ '),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: InputDecoration(labelText: tr('paymentMethod')),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                  DropdownMenuItem(value: 'maya', child: Text('Maya')),
                ],
                onChanged: (v) => setState(() => _method = v ?? 'cash'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: InputDecoration(labelText: '${tr('adminNotes')} (${tr('optional')})'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(tr('cancel')),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(tr('nbSave')),
        ),
      ],
    );
  }

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
      );
}

/// Maliit na helper para sa ibang module: ipakita ang toast pagkatapos mag-save.
Future<void> openNewBooking(BuildContext context, AdminData data, Future<void> Function() onSaved) async {
  final saved = await showNewBookingDialog(context, data);
  if (!saved || !context.mounted) return;
  showToast(context, tr('nbSaved'));
  await onSaved();
}

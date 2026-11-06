import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/booking_workflow.dart';
import '../../services/receipt.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/payment_entry.dart';

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
  final _clientSearch = TextEditingController();
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
  PaymentDetails _payDetails = const PaymentDetails(method: 'cash');

  /// 0.5 = 50% downpayment, 1.0 = buong bayad, null = mano-manong halaga.
  double? _payShare = 0.5;

  /// Kailangan ng resort ng downpayment bago ma-reserve ang petsa.
  static const _minDownRate = 0.5;
  final _notes = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_guestName, _guestPhone, _clientSearch, _eventType, _total, _payment, _notes, ..._pax.values]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _totalPax => _pax.values.fold<int>(0, (s, c) => s + (int.tryParse(c.text) ?? 0));

  Map<String, dynamic>? get _package =>
      _packageId == null ? null : widget.data.packageById(_packageId);

  String _guestDisplayName() {
    if (!_existingClient) return _guestName.text.trim();
    final c = _selectedClient;
    if (c == null) return '—';
    final name = _fullName(c);
    return name.isEmpty ? '—' : name;
  }

  Map<String, dynamic>? get _selectedClient =>
      widget.data.clients.where((c) => '${c['id']}' == _clientId).firstOrNull;

  static String _part(dynamic v) {
    final t = '${v ?? ''}'.trim();
    return t.isEmpty || t.toUpperCase() == 'N/A' ? '' : t;
  }

  /// "Dela Cruz, Juan Santos Jr." (apelyido, pangalan, gitnang pangalan) gaya ng nasa account.
  static String _fullName(Map<String, dynamic> c) {
    final last = _part(c['last_name']);
    final first = _part(c['first_name']);
    final middle = _part(c['middle_name']);
    final suffix = _part(c['suffix']);
    if (last.isEmpty && first.isEmpty) return _part(c['google_display_name']);
    final rest = [first, middle, suffix].where((e) => e.isNotEmpty).join(' ');
    return rest.isEmpty ? last : (last.isEmpty ? rest : '$last, $rest');
  }

  /// Para sa A–Z: apelyido muna, saka pangalan.
  static String _sortKey(Map<String, dynamic> c) => _fullName(c).toLowerCase();

  int? get _maxPax {
    final pkg = _package;
    return pkg == null || pkg['max_pax'] == null ? null : asInt(pkg['max_pax']);
  }

  double get _totalValue => double.tryParse(_total.text.replaceAll(',', '')) ?? 0;

  /// Itakda ang total; kusang susunod ang "Binayaran ngayon" kapag 50% o buo ang napili.
  void _setTotal(double total) {
    _total.text = total.toStringAsFixed(0);
    _applyShare();
  }

  void _applyShare() {
    final share = _payShare;
    if (share == null) return;
    _payment.text = (_totalValue * share).roundToDouble().toStringAsFixed(0);
  }

  /// Mga petsang may aktibong booking na kasabay ng oras ng package (iisang lugar ang resort,
  /// kaya bawal ang Day Tour + Function Hall Day hours; pwede ang Day Tour + Overnight).
  Set<String> _bookedKeys(dynamic packageId) {
    final mine = widget.data.slotsOf(packageId);
    return {
      for (final b in widget.data.bookings)
        if (!isInactive(b) &&
            bookingDateOf(b) != null &&
            widget.data.slotsOf(b['package_id']).intersection(mine).isNotEmpty)
          dateKey(bookingDateOf(b)!),
    };
  }

  bool _selectable(DateTime day, dynamic packageId, Set<String> booked) =>
      !booked.contains(dateKey(day)) && widget.data.blocksOn(day, packageId: packageId).isEmpty;

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
      final taken = widget.data.isTimeTaken(date, pkg['id']);
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
        _setTotal(asDouble(result['price'] ?? pkg['price']));
      }
    });
  }

  Future<void> _pickDate() async {
    final pkg = _package;
    if (pkg == null) {
      setState(() => _error = tr('nbErrPackageFirst'));
      return;
    }
    // Mula ngayon hanggang huling araw ng taon lang; bawal ang may booking na o naka-block.
    final today = DateUtils.dateOnly(DateTime.now());
    final last = DateTime(today.year, 12, 31);
    final booked = _bookedKeys(pkg['id']);
    DateTime? first;
    for (var d = today; !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
      if (_selectable(d, pkg['id'], booked)) {
        first = d;
        break;
      }
    }
    if (first == null) {
      setState(() => _error = tr('nbErrNoDates'));
      return;
    }
    final current = _date;
    final initial = current != null && !current.isBefore(today) && !current.isAfter(last) &&
            _selectable(current, pkg['id'], booked)
        ? current
        : first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: last,
      selectableDayPredicate: (d) => _selectable(DateUtils.dateOnly(d), pkg['id'], booked),
      helpText: tr('nbDateHelp'),
    );
    if (picked == null) return;
    setState(() => _error = null);
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
    final minDown = (total * _minDownRate).roundToDouble();
    if (paid + 0.01 < minDown) {
      setState(() => _error = tr('nbErrDownpayment', {'amount': peso(minDown)}));
      return;
    }
    final payError = _payDetails.validate(paid);
    if (payError != null) {
      setState(() => _error = tr(payError));
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

      final d = _payDetails;
      Map<String, dynamic>? payment;
      if (paid > 0) {
        payment = await supabase
            .from('payments')
            .insert({
              'booking_id': booking['id'],
              'amount': paid,
              'method': d.method,
              'kind': fullyPaid ? 'balance' : 'downpayment',
              'received_by': supabase.auth.currentUser?.id,
              'status': 'verified',
              if (!d.isCash) 'reference_no': d.reference,
            })
            .select()
            .single();
      }

      await BookingWorkflow.log(
        booking['id'],
        'created',
        toStatus: '${booking['status']}',
        note: [
          sourceLabel(_source),
          if (paid > 0) '${peso(paid)} ${methodLabel(d.method)}',
          if (!d.isCash && d.reference.isNotEmpty) 'Ref ${d.reference}',
          if (d.isCash && d.cashReceived != null)
            '${tr('peCashReceived')} ${peso(d.cashReceived!)}, ${tr('rcChange')} ${peso(d.changeFor(paid))}',
        ].join(' · '),
      );

      if (!mounted) return;
      // Resibo (kapag may bayad)
      if (payment != null) {
        await showPaymentReceipt(
          context,
          PaymentReceipt(
            paymentId: payment['id'],
            date: DateTime.now(),
            guest: _guestDisplayName(),
            packageName: '${pkg['name']}',
            bookingDate: _date,
            source: _source,
            amount: paid,
            method: d.method,
            reference: d.isCash ? '' : d.reference,
            cashReceived: d.isCash ? d.cashReceived : null,
            totalAmount: total,
            paidSoFar: paid,
            staff: supabase.auth.currentUser?.email ?? 'Admin',
            claimCode: booking['claim_code'] as String?,
            checkinCode: booking['checkin_code'] as String?,
          ),
        );
      } else if ('${booking['claim_code'] ?? ''}'.isNotEmpty) {
        // Walang bayad pa: ipakita pa rin ang code para ma-link ng guest sa app.
        await showClaimCodeDialog(context, '${booking['claim_code']}');
      }
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

    final clients = [...widget.data.clients]..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
    final maxPax = _maxPax;
    final overPax = maxPax != null && _totalPax > maxPax;

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
                _clientPicker(theme, clients)
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
                  setState(() {
                    _packageId = v;
                    _error = null;
                    final p = _package;
                    if (p != null) {
                      // Lalabas agad ang presyo; papalitan kung may seasonal na presyo sa petsa.
                      _setTotal(asDouble(p['price']));
                      final d = _date;
                      if (d != null && !_selectable(d, p['id'], _bookedKeys(p['id']))) {
                        _date = null;
                        _availability = null;
                      }
                    }
                  });
                  _checkAvailability();
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(_date == null ? tr('nbChooseDate') : formatDate(_date)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr('nbDateRule', {'year': DateTime.now().year}),
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
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
              _label(theme, tr('fieldGuests')),
              // Kabuuang bisita at maximum ng package (pula kapag lumampas)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: (overPax ? theme.colorScheme.error : const Color(0xFF0F766E)).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (overPax ? theme.colorScheme.error : const Color(0xFF0F766E)).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(overPax ? Icons.error_outline : Icons.groups_outlined,
                        size: 20, color: overPax ? theme.colorScheme.error : const Color(0xFF0F766E)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        overPax
                            ? tr('nbPaxOver', {'n': _totalPax, 'max': maxPax})
                            : maxPax == null
                                ? tr('nbPaxTotal', {'n': _totalPax})
                                : tr('nbPaxOfMax', {'n': _totalPax, 'max': maxPax}),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: overPax ? theme.colorScheme.error : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
                      width: 168,
                      child: _PaxField(
                        label: e.value,
                        controller: _pax[e.key]!,
                        // Hindi na madadagdagan gamit ang + kapag puno na ang package.
                        canAdd: maxPax == null || _totalPax < maxPax,
                        onChanged: () => setState(() {}),
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
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: InputDecoration(labelText: tr('fieldTotal'), prefixText: '₱ '),
                      onChanged: (_) => setState(_applyShare),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _payment,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: InputDecoration(labelText: tr('nbPaidNow'), prefixText: '₱ '),
                      onChanged: (_) => setState(() => _payShare = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Mabilis na pagpili ng halaga
              Wrap(
                spacing: 8,
                children: [
                  for (final e in {'nbPayDown': 0.5, 'nbPayFull': 1.0}.entries)
                    ChoiceChip(
                      label: Text(tr(e.key)),
                      selected: _payShare == e.value,
                      onSelected: (_) => setState(() {
                        _payShare = e.value;
                        _applyShare();
                      }),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr('nbDownNote', {'amount': peso((_totalValue * _minDownRate).roundToDouble())}),
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 12),
              // Paraan ng bayad: Cash (may sukli) / GCash / Maya (e-payment, may reference number)
              Text(tr('paymentMethod'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              PaymentEntry(
                amount: double.tryParse(_payment.text.replaceAll(',', '')) ?? 0,
                onChanged: (d) => _payDetails = d,
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

  /// Hanapin at piliin ang client (A–Z ayon sa apelyido). Ipinapakita ang birth date at phone ng napili.
  Widget _clientPicker(ThemeData theme, List<Map<String, dynamic>> clients) {
    final selected = _selectedClient;
    if (selected != null) {
      final phone = _part(selected['phone']);
      final birth = parseDate(selected['birth_date']);
      final verified = selected['verification_status'] == 'verified';
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F766E).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ClientAvatar(client: selected, name: _fullName(selected), radius: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_fullName(selected), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('${tr('birthDate')}: ${birth == null ? tr('notSet') : formatDate(birth)}'),
                  Text('${tr('fieldPhone')}: ${phone.isEmpty ? tr('notSet') : phone}'),
                  const SizedBox(height: 4),
                  Text(
                    verified ? tr('nbClientVerified') : tr('nbClientNotVerified'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: verified ? const Color(0xFF15803D) : const Color(0xFFC2410C),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _clientId = null),
              child: Text(tr('nbChangeClient')),
            ),
          ],
        ),
      );
    }

    // Bawat salita sa hinahanap ay dapat nasa pangalan o phone, kahit anong pagkakasunod
    // (hal. "krizia buena" at "buena krizia" ay parehong makikita).
    final words = _clientSearch.text.toLowerCase().split(RegExp(r'[\s,]+')).where((w) => w.isNotEmpty).toList();
    final matches = clients.where((c) {
      if (words.isEmpty) return true;
      final hay = [
        _fullName(c),
        _part(c['google_display_name']),
        _part(c['username']),
        _part(c['phone']),
        _part(c['phone']).replaceAll(RegExp(r'\D'), ''),
        // +63 9XX… → 09XX… para mahanap din kapag 0 ang simula ng tina-type
        _part(c['phone']).replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^63'), '0'),
      ].join(' ').toLowerCase();
      return words.every(hay.contains);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _clientSearch,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: tr('nbSearchClient'),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: matches.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr('noResults'), textAlign: TextAlign.center),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: matches.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = matches[i];
                    final phone = _part(c['phone']);
                    return ListTile(
                      dense: true,
                      leading: _ClientAvatar(client: c, name: _fullName(c), radius: 17),
                      title: Text(_fullName(c), overflow: TextOverflow.ellipsis),
                      subtitle: phone.isEmpty ? null : Text(phone),
                      onTap: () => setState(() {
                        _clientId = '${c['id']}';
                        _clientSearch.clear();
                      }),
                    );
                  },
                ),
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

/// Bilang ng bisita na may − at +. Nawawala ang "0" kapag pinindot para makapag-type agad,
/// at bumabalik sa 0 kapag iniwang blangko (gaya sa app).
class _PaxField extends StatefulWidget {
  const _PaxField({required this.label, required this.controller, required this.canAdd, required this.onChanged});

  final String label;
  final TextEditingController controller;
  final bool canAdd;
  final VoidCallback onChanged;

  @override
  State<_PaxField> createState() => _PaxFieldState();
}

class _PaxFieldState extends State<_PaxField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      final c = widget.controller;
      if (_focus.hasFocus && c.text == '0') {
        c.clear();
      } else if (!_focus.hasFocus && c.text.trim().isEmpty) {
        c.text = '0';
        widget.onChanged();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(widget.controller.text) ?? 0;

  void _set(int v) {
    widget.controller.text = '${v < 0 ? 0 : v}';
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        prefixIcon: IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove, size: 18),
          onPressed: _value > 0 ? () => _set(_value - 1) : null,
        ),
        suffixIcon: IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 18),
          onPressed: widget.canAdd ? () => _set(_value + 1) : null,
        ),
      ),
      onChanged: (_) => widget.onChanged(),
    );
  }
}

/// Profile picture ng client (sariling litrato sa app, o galing Google). Inisyal kapag wala o hindi ma-load.
class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.client, required this.name, required this.radius});

  final Map<String, dynamic> client;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    String pick(dynamic v) => '${v ?? ''}'.trim();
    final url = pick(client['avatar_url']).isNotEmpty ? pick(client['avatar_url']) : pick(client['google_avatar_url']);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Container(
      color: const Color(0xFF0F766E),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: radius * 0.85),
      ),
    );
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: ClipOval(
        child: url.isEmpty
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (context, child, progress) => progress == null ? child : fallback,
              ),
      ),
    );
  }
}

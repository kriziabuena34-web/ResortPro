import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/offline_cache.dart';
import '../services/payment_proof.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'home_page.dart';
import 'info_pages.dart';

class BookingPage extends StatefulWidget {
  final Package package;

  const BookingPage({super.key, required this.package});

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  DateTime? _selectedDate;
  bool _checkingAvailability = false;
  bool _dateAvailable = true;
  String? _unavailableReason; // 'booked' o 'blocked'

  /// Para maibalik ang tingin sa "SELECT DATE" kapag hindi available ang petsa.
  final _dateKey = GlobalKey();
  String? _blockNote;

  /// Presyo para sa napiling petsa (pwedeng iba tuwing weekend/holiday).
  double? _datePrice;

  final _infantController = TextEditingController(text: '0');
  final _childController = TextEditingController(text: '0');
  final _teenController = TextEditingController(text: '0');
  final _adultController = TextEditingController(text: '0');
  final _elderlyController = TextEditingController(text: '0');
  final _eventTypeController = TextEditingController();

  PaymentProof? _proof;
  bool _isSubmitting = false;

  bool get _isFunctionHall => widget.package.name.startsWith('Function Hall');

  int get _totalPax {
    return (int.tryParse(_infantController.text) ?? 0) +
        (int.tryParse(_childController.text) ?? 0) +
        (int.tryParse(_teenController.text) ?? 0) +
        (int.tryParse(_adultController.text) ?? 0) +
        (int.tryParse(_elderlyController.text) ?? 0);
  }

  /// Pinakamaraming bisita para sa package na ito.
  int get _maxGuests => widget.package.maxPax ?? 999;

  double get _price => _datePrice ?? widget.package.price;

  /// ₱100 bawat guest (3 taong gulang pataas) na lampas sa kasama sa presyo.
  static const _extraPaxRate = 100.0;

  int get _countedPax => _totalPax - (int.tryParse(_infantController.text) ?? 0);

  int get _extraPax {
    final inc = widget.package.includedPax;
    if (inc == null || inc <= 0) return 0;
    return (_countedPax - inc).clamp(0, 9999);
  }

  double get _extraFee => _extraPax * _extraPaxRate;

  double get _total => _price + _extraFee;

  double get _downPayment => (_total * downpaymentRate).roundToDouble();

  // Opsyonal: para sa analytics ng resort
  String? _location;
  String? _foundUs;
  String? _occasion;
  static const _locations = ['Pagsanjan & nearby towns', 'Other Laguna towns', 'Metro Manila', 'Other provinces'];
  static const _sources = ['Facebook', 'Referral', 'Returning customer', 'Walk-by / signage'];
  static const _occasions = [
    'Birthday / Debut / Christening',
    'Family outing',
    'Barkada',
    'Reunion',
    'Company outing',
    'School / Organization',
    'Other',
  ];

  /// Ipakita ang bahagi ng petsa (at ang pulang abiso) sa screen.
  void _showDateSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _dateKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.1);
      }
    });
  }

  Future<void> _pickDate() async {
    // Alisin ang focus sa text field para hindi bumaba ang screen pagsara ng calendar.
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _checkingAvailability = true;
      });
      await _checkAvailability(picked);
      if (mounted && !_dateAvailable) _showDateSection();
    }
  }

  Future<void> _checkAvailability(DateTime date) async {
    final dateStr = dateKey(date);
    try {
      // Iisang check sa server: blocked date, may booking na, at presyo.
      final result = await supabase.rpc('check_availability', params: {
        'p_package_id': widget.package.id,
        'p_date': dateStr,
      });
      final r = Map<String, dynamic>.from(result as Map);
      if (!mounted) return;
      setState(() {
        _dateAvailable = r['available'] == true;
        _unavailableReason = r['reason'] as String?;
        _blockNote = r['note'] as String?;
        _datePrice = r['price'] == null ? null : asDouble(r['price']);
        _checkingAvailability = false;
      });
    } catch (_) {
      // Fallback kapag hindi pa naka-setup ang database function.
      try {
        final existing = await supabase
            .from('bookings')
            .select('id')
            .eq('package_id', widget.package.id)
            .eq('booking_date', dateStr)
            .neq('status', 'cancelled');
        if (!mounted) return;
        setState(() {
          _dateAvailable = (existing as List).isEmpty;
          _unavailableReason = _dateAvailable ? null : 'booked';
          _datePrice = null;
          _checkingAvailability = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _dateAvailable = true; // fail open, the database guard will catch it
          _checkingAvailability = false;
        });
      }
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitBooking() async {
    if (_selectedDate == null) {
      _show('Please select a date.');
      _showDateSection();
      return;
    }
    if (!_dateAvailable) {
      _show('That date is not available. Please choose another.');
      _showDateSection();
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final pax = _totalPax;
    final maxPax = widget.package.maxPax ?? 9999;
    if (pax == 0) {
      _show('Please enter at least one guest.');
      return;
    }
    if (pax > maxPax) {
      _show('Total guests cannot exceed $maxPax.');
      return;
    }
    final proof = _proof;
    if (proof == null) {
      _show('Please enter the reference number and upload your payment screenshot.');
      return;
    }

    // Walang internet: sabihin agad, bago pa ang Terms and Conditions.
    if (!await hasInternet()) {
      if (mounted) showOfflineSnack(context);
      return;
    }
    if (!mounted) return;

    // Lalabas ang Terms and Conditions; kailangang basahin at sumang-ayon bago ma-submit.
    if (!await showTermsAgreement(context) || !mounted) return;

    setState(() => _isSubmitting = true);

    String? bookingId;
    try {
      final userId = supabase.auth.currentUser!.id;

      final bookingResponse = await supabase
          .from('bookings')
          .insert({
            'client_id': userId,
            'package_id': widget.package.id,
            'booking_date': dateKey(_selectedDate!),
            'total_pax': pax,
            'infants': int.tryParse(_infantController.text) ?? 0,
            'children': int.tryParse(_childController.text) ?? 0,
            'teens': int.tryParse(_teenController.text) ?? 0,
            'adults': int.tryParse(_adultController.text) ?? 0,
            'elderly': int.tryParse(_elderlyController.text) ?? 0,
            // Ang server ang magtatakda ng huling presyo ayon sa petsa.
            'total_amount': _total,
            'status': 'reserved',
            'event_type': _isFunctionHall ? _eventTypeController.text : null,
            if (_location != null) 'customer_location': _location,
            if (_foundUs != null) 'referral_source': _foundUs,
            if (_occasion != null) 'occasion': _occasion,
          })
          .select()
          .single();
      bookingId = '${bookingResponse['id']}';

      // Ang server ang may huling presyo (seasonal pricing), kaya doon ibabatay ang downpayment.
      final serverTotal = (bookingResponse['total_amount'] as num?)?.toDouble();
      final downPayment =
          serverTotal == null ? _downPayment : (serverTotal * downpaymentRate).roundToDouble();

      await submitPaymentProof(
        bookingId: bookingId,
        amount: downPayment,
        kind: 'downpayment',
        proof: proof,
      );

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.hourglass_top, size: 40),
            title: const Text('Booking submitted!'),
            content: const Text(
              'We received your booking and payment proof. The resort will verify your payment '
              'and confirm your booking. You will get a notification once it is confirmed.',
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      final text = '$e';
      String message;
      if (text.contains('DATE_TAKEN')) {
        message = 'Sorry, someone just booked this date. Please choose another date.';
      } else if (text.contains('DATE_BLOCKED')) {
        message = 'This date is not available for booking.';
      } else if (bookingId != null) {
        message = 'Your booking was saved, but the payment proof failed to upload. '
            'Please upload it again from My Bookings.';
      } else {
        message = isOfflineError(e)
            ? 'No internet connection. Your booking was not sent. Please connect and try again.'
            : 'Booking failed: $e';
      }
      if (mounted) _show(message);
      if (bookingId != null && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _infantController.dispose();
    _childController.dispose();
    _teenController.dispose();
    _adultController.dispose();
    _elderlyController.dispose();
    _eventTypeController.dispose();
    super.dispose();
  }

  Widget _paxField(String label, String ages, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(ages, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            flex: 6,
            child: _GuestCounter(
              controller: controller,
              // Ilan pa ang pwede sa box na ito para hindi lumampas sa capacity.
              max: _maxGuests - (_totalPax - (int.tryParse(controller.text) ?? 0)),
              capacity: _maxGuests,
              onChanged: () => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  /// Card ng bawat hakbang (1 Date, 2 Guests, …).
  Widget _step(int n, String title, String? subtitle, Widget child, {Key? key}) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15.5, color: AppColors.ink)),
                    if (subtitle != null)
                      Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text, Color color) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, height: 1.35, fontSize: 13))),
          ],
        ),
      );

  Widget _heroChip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.inkRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.inkLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.inkText),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _choice(String label, IconData icon, String? value, List<String> options, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.subtle,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final seasonal = _datePrice != null && _datePrice != widget.package.price;
    final pkg = widget.package;
    final capacityShare = _maxGuests >= 999 ? 0.0 : (_totalPax / _maxGuests).clamp(0.0, 1.0);
    var step = 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Book a Package')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- Buod ng package ----
              Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pkg.name,
                        style: const TextStyle(
                            fontFamily: 'Poppins', color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _heroChip(Icons.schedule_rounded, pkg.formattedDuration),
                        _heroChip(Icons.groups_outlined, pkg.formattedCapacity),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('TOTAL',
                                  style: TextStyle(
                                      color: AppColors.inkText, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                              Text(peso(_total),
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${(downpaymentRate * 100).round()}% DOWNPAYMENT',
                                  style: const TextStyle(
                                      color: Color(0xFFD7F5EF), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                              Text(peso(_downPayment),
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_extraPax > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${peso(_price)} package + ${peso(_extraFee)} for $_extraPax extra '
                        '${_extraPax == 1 ? 'guest' : 'guests'} (${peso(_extraPaxRate)} each above ${widget.package.includedPax} pax)',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF99F6E4), fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (seasonal) ...[
                      const SizedBox(height: 10),
                      Text(
                        _datePrice! > pkg.price
                            ? 'Peak/weekend rate for this date (regular ${pkg.formattedPrice})'
                            : 'Discounted rate for this date (regular ${pkg.formattedPrice})',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFFBBF24), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),

              // ---- 1. Petsa ----
              _step(
                ++step,
                'Choose Your Date',
                'The resort is private, so only one group stays at a time',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: AppColors.subtle,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: _selectedDate == null
                              ? AppColors.border
                              : (_dateAvailable ? AppColors.primary : AppColors.danger),
                          width: _selectedDate == null ? 1 : 1.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _pickDate,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _selectedDate == null ? 'Tap to choose a date' : formatDate(_selectedDate),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: _selectedDate == null ? AppColors.muted : AppColors.text,
                                  ),
                                ),
                              ),
                              if (_checkingAvailability)
                                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              else
                                const Icon(Icons.edit_calendar_outlined, size: 20, color: AppColors.muted),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_checkingAvailability)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Checking availability…', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      ),
                    if (!_checkingAvailability && _selectedDate != null && !_dateAvailable)
                      _note(
                        Icons.event_busy_rounded,
                        _unavailableReason == 'blocked'
                            ? 'The resort is not accepting bookings on this date'
                                '${(_blockNote ?? '').isEmpty ? '' : ' ($_blockNote)'}.'
                            : 'This date is already booked at this time. Please choose another date.',
                        AppColors.danger,
                      ),
                    if (!_checkingAvailability && _selectedDate != null && _dateAvailable)
                      _note(Icons.check_circle_rounded, 'Great! This date is available.', AppColors.success),
                  ],
                ),
                key: _dateKey,
              ),

              // ---- 2. Bisita ----
              _step(
                ++step,
                'Number of Guests',
                'Capacity: ${pkg.formattedCapacity}',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _paxField('Infant/Toddler', '0–3 years', _infantController),
                    _paxField('Child', '4–12 years', _childController),
                    _paxField('Teen', '13–19 years', _teenController),
                    _paxField('Adult', '20–59 years', _adultController),
                    _paxField('Elderly', '60+ years', _elderlyController),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: AppColors.subtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Text('Total Guests', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                              const Spacer(),
                              Text('$_totalPax pax', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            ],
                          ),
                          if (_maxGuests < 999) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: capacityShare,
                                minHeight: 6,
                                backgroundColor: const Color(0xFFE6EBF0),
                                valueColor: AlwaysStoppedAnimation(
                                    _totalPax >= _maxGuests ? AppColors.danger : AppColors.primary),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_totalPax >= _maxGuests)
                      _note(Icons.info_outline_rounded, 'Maximum of $_maxGuests guests reached for this package.',
                          AppColors.danger),
                    if ((widget.package.includedPax ?? 0) > 0)
                      _note(
                        Icons.payments_outlined,
                        _extraPax > 0
                            ? '$_extraPax extra ${_extraPax == 1 ? 'guest' : 'guests'} × ${peso(_extraPaxRate)} = ${peso(_extraFee)} added to your total.'
                            : 'The price includes ${widget.package.includedPax} guests (3 years old and up). '
                                'Each extra guest is ${peso(_extraPaxRate)}.',
                        _extraPax > 0 ? AppColors.warning : AppColors.primary,
                      ),
                  ],
                ),
              ),

              // ---- 3. Event (Function Hall) ----
              if (_isFunctionHall)
                _step(
                  ++step,
                  'Type of Event',
                  'Tell us what you are celebrating',
                  TextFormField(
                    controller: _eventTypeController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'e.g. Wedding, Birthday, Reunion',
                      prefixIcon: const Icon(Icons.celebration_outlined),
                      filled: true,
                      fillColor: AppColors.subtle,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    validator: (value) {
                      if (_isFunctionHall && (value == null || value.trim().isEmpty)) {
                        return 'Please specify the type of event.';
                      }
                      return null;
                    },
                  ),
                ),

              // ---- Opsyonal: tungkol sa iyo (para sa analytics ng resort) ----
              _step(
                ++step,
                'About Your Stay (Optional)',
                'Helps the resort plan better. You can skip this.',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _choice('Where are you from?', Icons.place_outlined, _location, _locations,
                        (v) => setState(() => _location = v)),
                    const SizedBox(height: 12),
                    _choice('How did you find us?', Icons.campaign_outlined, _foundUs, _sources,
                        (v) => setState(() => _foundUs = v)),
                    const SizedBox(height: 12),
                    _choice('What is the occasion?', Icons.cake_outlined, _occasion, _occasions,
                        (v) => setState(() => _occasion = v)),
                  ],
                ),
              ),

              // ---- 4. Downpayment ----
              _step(
                ++step,
                'Pay the Downpayment',
                'Send ${peso(_downPayment)} and upload your payment screenshot',
                PaymentProofForm(
                  amount: _downPayment,
                  onChanged: (p) => setState(() => _proof = p),
                ),
              ),

              const SizedBox(height: 4),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSubmitting ? null : _submitBooking,
                  icon: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 19),
                  label: Text(_isSubmitting ? 'Submitting…' : 'Submit Booking',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                ),
              ),
              const SizedBox(height: 10),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.gavel_rounded, size: 15, color: AppColors.muted),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'You will be asked to read and agree to the Terms and Conditions before your booking is submitted.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bilang ng bisita: [−] [bilang] [+]. Laging nakikita ang − at +.
/// Pag tinap ang box, pwedeng i-type ang bilang; kusang nawawala ang "0",
/// at bumabalik ito kapag iniwang blangko.
class _GuestCounter extends StatefulWidget {
  const _GuestCounter({
    required this.controller,
    required this.onChanged,
    required this.max,
    required this.capacity,
  });

  /// Pinakamataas na bilang na pwede sa box na ito (ayon sa natitirang capacity).
  final int max;
  /// Kabuuang capacity ng package (para sa mensahe).
  final int capacity;

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  State<_GuestCounter> createState() => _GuestCounterState();
}

class _GuestCounterState extends State<_GuestCounter> {
  final _focus = FocusNode();

  int get _value => int.tryParse(widget.controller.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final c = widget.controller;
    if (_focus.hasFocus) {
      // Kusang tanggalin ang 0 para hindi na burahin.
      if (c.text == '0') c.clear();
    } else if (c.text.trim().isEmpty) {
      c.text = '0';
      widget.onChanged();
    }
    setState(() {});
  }

  int get _limit => widget.max < 0 ? 0 : widget.max;

  void _set(int v) {
    final value = v < 0 ? 0 : (v > _limit ? _limit : v);
    widget.controller.text = '$value';
    widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    Widget button(IconData icon, String tooltip, VoidCallback? onTap) => Tooltip(
          message: tooltip,
          child: Material(
            color: onTap == null ? const Color(0xFFEDF1F4) : primary.withValues(alpha: 0.12),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              canRequestFocus: false,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(icon, size: 20, color: onTap == null ? Colors.grey : primary),
              ),
            ),
          ),
        );

    return Row(
      children: [
        button(Icons.remove, 'Less', _value > 0 ? () => _set(_value - 1) : null),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '0',
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (_) {
              // Kapag lumampas sa capacity ang tinype, ibaba sa pinakamataas na pwede.
              if (_value > _limit) {
                _set(_limit);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(content: Text('This package allows up to ${widget.capacity} guests only.')),
                  );
                return;
              }
              widget.onChanged();
              setState(() {});
            },
            onTapOutside: (_) => _focus.unfocus(),
          ),
        ),
        const SizedBox(width: 6),
        button(Icons.add, 'More', _value < _limit ? () => _set(_value + 1) : null),
      ],
    );
  }
}

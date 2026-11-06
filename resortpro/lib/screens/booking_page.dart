import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/offline_cache.dart';
import '../services/payment_proof.dart';
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

  double get _downPayment => (_price * downpaymentRate).roundToDouble();

  Future<void> _pickDate() async {
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
      return;
    }
    if (!_dateAvailable) {
      _show('That date is not available. Please choose another.');
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
            'total_amount': _price,
            'status': 'reserved',
            'event_type': _isFunctionHall ? _eventTypeController.text : null,
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

  Widget _paxField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text(label)),
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

  @override
  Widget build(BuildContext context) {
    final seasonal = _datePrice != null && _datePrice != widget.package.price;

    return Scaffold(
      appBar: AppBar(title: Text('Book: ${widget.package.name}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.package.name,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('Total: ${peso(_price)}'),
              if (seasonal)
                Text(
                  _datePrice! > widget.package.price
                      ? 'Peak/weekend rate for this date (regular ${widget.package.formattedPrice})'
                      : 'Discounted rate for this date (regular ${widget.package.formattedPrice})',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFE08A00)),
                ),
              Text(
                '${(downpaymentRate * 100).round()}% Downpayment: ${peso(_downPayment)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              const Text('SELECT DATE', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(_selectedDate == null ? 'Choose a date' : formatDate(_selectedDate)),
              ),
              if (_checkingAvailability)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Checking availability...'),
                ),
              if (!_checkingAvailability && _selectedDate != null && !_dateAvailable)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _unavailableReason == 'blocked'
                        ? 'The resort is not accepting bookings on this date'
                            '${(_blockNote ?? '').isEmpty ? '' : ' ($_blockNote)'}.'
                        : 'This date is already booked for this package.',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (!_checkingAvailability && _selectedDate != null && _dateAvailable)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Date is available.',
                    style: TextStyle(color: Colors.green),
                  ),
                ),

              const SizedBox(height: 24),

              const Text('NUMBER OF GUESTS BY AGE', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _paxField('Infant/Toddler (0-3)', _infantController),
              _paxField('Child (4-12)', _childController),
              _paxField('Teen (13-19)', _teenController),
              _paxField('Adult (20-59)', _adultController),
              _paxField('Elderly (60+)', _elderlyController),

              const SizedBox(height: 8),
              Text(
                'Total: $_totalPax pax (Capacity: ${widget.package.formattedCapacity})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_totalPax >= _maxGuests)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Maximum of $_maxGuests guests reached for this package.',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFFC2410C), fontWeight: FontWeight.w600),
                  ),
                ),

              if (_isFunctionHall) ...[
                const SizedBox(height: 24),
                const Text('TYPE OF EVENT', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _eventTypeController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Wedding, Birthday, Reunion',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_isFunctionHall && (value == null || value.trim().isEmpty)) {
                      return 'Please specify the type of event.';
                    }
                    return null;
                  },
                ),
              ],

              const SizedBox(height: 24),

              const Text('DOWNPAYMENT', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              PaymentProofForm(
                amount: _downPayment,
                onChanged: (p) => setState(() => _proof = p),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitBooking,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('SUBMIT BOOKING'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You will be asked to read and agree to the Terms and Conditions before your booking is submitted.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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

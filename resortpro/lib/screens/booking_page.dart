import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/payment_proof.dart';
import '../utils/format.dart';
import 'home_page.dart';

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
            'infants': int.parse(_infantController.text),
            'children': int.parse(_childController.text),
            'teens': int.parse(_teenController.text),
            'adults': int.parse(_adultController.text),
            'elderly': int.parse(_elderlyController.text),
            // Ang server ang magtatakda ng huling presyo ayon sa petsa.
            'total_amount': _price,
            'status': 'reserved',
            'event_type': _isFunctionHall ? _eventTypeController.text : null,
          })
          .select()
          .single();
      bookingId = '${bookingResponse['id']}';

      await submitPaymentProof(
        bookingId: bookingId,
        amount: _downPayment,
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
            'Please upload it again from My Bookings. ($e)';
      } else {
        message = 'Booking failed: $e';
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
          Expanded(flex: 2, child: Text(label)),
          Expanded(
            flex: 1,
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
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
                'Your date is held while the resort verifies your payment.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

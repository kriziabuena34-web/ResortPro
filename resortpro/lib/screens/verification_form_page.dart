import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Forces typed text to appear in uppercase, regardless of how it's typed.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class VerificationFormPage extends StatefulWidget {
  const VerificationFormPage({super.key});

  @override
  State<VerificationFormPage> createState() => _VerificationFormPageState();
}

class _VerificationFormPageState extends State<VerificationFormPage> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _suffixController = TextEditingController();
  final _contactController = TextEditingController();

  DateTime? _birthDate;
  String? _idType;
  Uint8List? _idImageBytes;
  bool _isSubmitting = false;

  final List<String> _idTypes = const [
    'Philippine Passport',
    "Driver's License",
    'National ID (PhilSys)',
    'National ID (Digital)',
    'UMID',
    "Voter's ID",
    'Postal ID',
    'PRC ID',
    'Senior Citizen ID',
    'Other',
  ];

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() => _idImageBytes = bytes);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your birth date.')),
      );
      return;
    }
    if (_idType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a government ID type.')),
      );
      return;
    }
    if (_idImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a photo of your ID.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final userId = supabase.auth.currentUser!.id;
      final path = '$userId/id_front.jpg';

      await supabase.storage.from('government-ids').uploadBinary(
        path,
        _idImageBytes!,
        fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
      );

      final birthDateStr =
          '${_birthDate!.year}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}';

      final middleName = _middleNameController.text.trim();
      final suffix = _suffixController.text.trim();

      await supabase.from('profiles').update({
        'last_name': _lastNameController.text.trim(),
        'first_name': _firstNameController.text.trim(),
        'middle_name': middleName.isEmpty ? 'N/A' : middleName,
        'suffix': suffix.isEmpty ? 'N/A' : suffix,
        'birth_date': birthDateStr,
        'phone': '+63${_contactController.text.trim()}',
        'government_id_type': _idType,
        'id_image_path': path,
        'verification_status': 'pending',
      }).eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification submitted! Please wait for admin review.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _lastNameController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _suffixController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Account Verification')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('GOOGLE ACCOUNT', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                email,
                style: const TextStyle(color: Colors.lightGreen, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),

              const Text('LAST NAME', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _lastNameController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              const Text('FIRST NAME', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _firstNameController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              const Text('MIDDLE NAME', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _middleNameController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'N/A if not applicable',
                ),
              ),
              const SizedBox(height: 16),

              const Text('SUFFIX', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _suffixController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Jr., Sr., III — N/A if none',
                ),
              ),
              const SizedBox(height: 20),

              const Text('BIRTH DATE', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(
                  _birthDate == null
                      ? 'Select date'
                      : '${_birthDate!.month}/${_birthDate!.day}/${_birthDate!.year}',
                ),
              ),
              const SizedBox(height: 20),

              const Text('CONTACT NUMBER', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  prefixText: '+63 ',
                  border: OutlineInputBorder(),
                  hintText: '9XXXXXXXXX',
                  counterText: '',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v.trim().length != 10) return 'Must be exactly 10 digits';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              const Text('GOVERNMENT ID TYPE', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _idType,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _idTypes
                    .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (value) => setState(() => _idType = value),
              ),
              const SizedBox(height: 20),

              const Text('UPLOAD ID (FRONT)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (_idImageBytes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_idImageBytes!, height: 180, fit: BoxFit.cover),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.upload_file),
                label: Text(_idImageBytes == null ? 'Choose Photo' : 'Change Photo'),
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Submit for Verification'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

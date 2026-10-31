import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:typed_data';

import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';

class ReportItemScreen extends StatefulWidget {
  final ReportType initialType;
  final VoidCallback? onSubmitted;

  const ReportItemScreen({
    super.key,
    this.initialType = ReportType.lost,
    this.onSubmitted,
  });

  @override
  State<ReportItemScreen> createState() => _ReportItemScreenState();
}

class _ReportItemScreenState extends State<ReportItemScreen> {
  final _formKey = GlobalKey<FormState>();
  late ReportType _type;
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _descController = TextEditingController();
  String _category = 'ID cards';
  XFile? _selectedImage;
  Uint8List? _selectedBytes;
  String? _imageError;
  bool _submitting = false;

  final _categories = [
    'ID cards',
    'Wallets and purses',
    'Phones and electronics',
    'Keys',
    'Bags',
    'Books',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    final extension = image.name.toLowerCase().split('.').last;
    final isJpeg = extension == 'jpg' || extension == 'jpeg';
    if (!isJpeg || (image.mimeType != null && image.mimeType != 'image/jpeg')) {
      setState(() => _imageError = 'Please select a JPEG image only.');
      return;
    }
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      setState(
        () => _imageError = 'Image must be non-empty and no larger than 5 MB.',
      );
      return;
    }
    setState(() {
      _selectedImage = image;
      _selectedBytes = bytes;
      _imageError = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      String? imagePath;
      if (_selectedImage != null && _selectedBytes != null) {
        imagePath = await appState.uploadImage(
          fileName: _selectedImage!.name.toLowerCase().endsWith('.jpeg')
              ? 'image.jpeg'
              : 'image.jpg',
          bytes: _selectedBytes!,
        );
      }
      final matches = await appState.addItemReport(
        reportType: _type,
        itemName: _nameController.text.trim(),
        category: _category,
        description: _descController.text.trim(),
        incidentDate: DateTime.now(),
        generalLocation: _locationController.text.trim(),
        imagePath: imagePath,
      );
      await appState.loadReports();
      if (!mounted) return;
      final message = _type == ReportType.found && matches.isNotEmpty
          ? 'Report submitted. ${matches.length} possible match${matches.length == 1 ? '' : 'es'} found for lost-item owners.'
          : 'Report submitted successfully!';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      if (widget.onSubmitted != null) {
        widget.onSubmitted!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit report: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _type == ReportType.lost ? 'Report Lost Item' : 'Report Found Item',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<ReportType>(
                segments: const [
                  ButtonSegment(
                    value: ReportType.lost,
                    label: Text('Lost Item'),
                  ),
                  ButtonSegment(
                    value: ReportType.found,
                    label: Text('Found Item'),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (set) => setState(() => _type = set.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Item Name *'),
                validator: (v) => v!.isEmpty ? 'Name required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category *'),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Campus Location *',
                ),
                validator: (v) => v!.isEmpty ? 'Location required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description *'),
                validator: (v) => v!.isEmpty ? 'Description required' : null,
              ),
              const SizedBox(height: 16),
              if (_selectedBytes == null)
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickImage,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Add Picture'),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 260,
                        width: double.infinity,
                        color: const Color(0xFFF1F3F5),
                        child: Image.memory(
                          _selectedBytes!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _submitting ? null : _pickImage,
                          icon: const Icon(Icons.edit),
                          label: const Text('Change Picture'),
                        ),
                        TextButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => setState(() {
                                  _selectedImage = null;
                                  _selectedBytes = null;
                                }),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove Picture'),
                        ),
                      ],
                    ),
                  ],
                ),
              if (_imageError != null)
                Text(
                  _imageError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: Text(
                  _submitting ? 'Submitting...' : 'Submit Campus Report',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

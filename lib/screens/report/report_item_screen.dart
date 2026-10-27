import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';

class ReportItemScreen extends StatefulWidget {
  final ReportType initialType;
  const ReportItemScreen({super.key, this.initialType = ReportType.lost});

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

  final _categories = ['ID cards', 'Wallets and purses', 'Phones and electronics', 'Keys', 'Bags', 'Books', 'Other'];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Provider.of<AppState>(context, listen: false).addItemReport(
      reportType: _type,
      itemName: _nameController.text.trim(),
      category: _category,
      description: _descController.text.trim(),
      incidentDate: DateTime.now(),
      generalLocation: _locationController.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted successfully!')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_type == ReportType.lost ? 'Report Lost Item' : 'Report Found Item')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<ReportType>(
                segments: const [
                  ButtonSegment(value: ReportType.lost, label: Text('Lost Item')),
                  ButtonSegment(value: ReportType.found, label: Text('Found Item')),
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
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Campus Location *'),
                validator: (v) => v!.isEmpty ? 'Location required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description *'),
                validator: (v) => v!.isEmpty ? 'Description required' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _submit, child: const Text('Submit Campus Report')),
            ],
          ),
        ),
      ),
    );
  }
}

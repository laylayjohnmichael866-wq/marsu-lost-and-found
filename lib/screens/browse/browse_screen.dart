import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/item_report_model.dart';
import '../../providers/app_state.dart';
import '../item_details/item_details_screen.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  String _searchQuery = '';
  ReportType? _selectedType;

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final filtered = appState.items.where((i) {
      final matchesSearch = i.itemName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          i.generalLocation.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesType = _selectedType == null || i.reportType == _selectedType;
      return matchesSearch && matchesType;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Browse Campus Items')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: const InputDecoration(hintText: 'Search items or locations...', prefixIcon: Icon(Icons.search)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(label: const Text('All'), selected: _selectedType == null, onSelected: (_) => setState(() => _selectedType = null)),
                    const SizedBox(width: 8),
                    FilterChip(label: const Text('Lost'), selected: _selectedType == ReportType.lost, onSelected: (_) => setState(() => _selectedType = ReportType.lost)),
                    const SizedBox(width: 8),
                    FilterChip(label: const Text('Found'), selected: _selectedType == ReportType.found, onSelected: (_) => setState(() => _selectedType = ReportType.found)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filtered.length,
              itemBuilder: (ctx, idx) {
                final item = filtered[idx];
                return Card(
                  child: ListTile(
                    title: Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${item.generalLocation} • ${item.status.name.toUpperCase()}'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailsScreen(item: item))),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

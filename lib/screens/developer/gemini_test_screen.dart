import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/gemini_ai_service.dart';

class GeminiTestScreen extends StatefulWidget {
  const GeminiTestScreen({super.key});

  @override
  State<GeminiTestScreen> createState() => _GeminiTestScreenState();
}

class _GeminiTestScreenState extends State<GeminiTestScreen> {
  final _promptController = TextEditingController();
  final _systemController = TextEditingController();
  final _service = GeminiAiService();
  GeminiModel _model = GeminiModel.flash;
  GeminiModel _fallbackModel = GeminiModel.pro;
  GeminiServiceResult? _result;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _promptController.dispose();
    _systemController.dispose();
    super.dispose();
  }

  Future<void> _sendPrompt() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _service.testPrompt(
        _promptController.text,
        model: _model,
        fallbackModel: _fallbackModel,
        systemInstruction: _systemController.text,
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      final message = error is GeminiApiException && error.httpStatus == 504
          ? 'The Gemini Edge Function timed out while contacting both the primary and fallback models. Try again or use a shorter prompt.'
          : error.toString();
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gemini Service Test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Developer-only screen. Requests use your existing authenticated Supabase session.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<GeminiModel>(
            initialValue: _model,
            decoration: const InputDecoration(labelText: 'Model'),
            items: GeminiModel.values
                .map(
                  (model) => DropdownMenuItem(
                    value: model,
                    child: Text(model.modelName),
                  ),
                )
                .toList(),
            onChanged: _loading
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _model = value;
                      if (_fallbackModel == value) {
                        _fallbackModel = GeminiModel.values.firstWhere(
                          (model) => model != value,
                        );
                      }
                    });
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<GeminiModel>(
            initialValue: _fallbackModel,
            decoration: const InputDecoration(labelText: 'Fallback model'),
            items: GeminiModel.values
                .where((model) => model != _model)
                .map(
                  (model) => DropdownMenuItem(
                    value: model,
                    child: Text(model.modelName),
                  ),
                )
                .toList(),
            onChanged: _loading
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _fallbackModel = value);
                    }
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptController,
            maxLines: 5,
            maxLength: 4000,
            decoration: const InputDecoration(
              labelText: 'Prompt',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _systemController,
            maxLines: 3,
            maxLength: 4000,
            decoration: const InputDecoration(
              labelText: 'System instruction (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _loading ? null : _sendPrompt,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(_loading ? 'Sending…' : 'Send to gemini-service'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 20),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Response',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(_result!.text ?? '(No text returned)'),
                    const Divider(height: 24),
                    Text('Model: ${_result!.modelUsed}'),
                    Text('Latency: ${_result!.latencyMs} ms'),
                    Text('Tokens: ${_result!.usage.totalTokens}'),
                    Text(
                      'Fallback: ${_result!.fallbackTriggered ? 'yes' : 'no'}',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

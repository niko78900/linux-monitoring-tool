import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';

class BenchmarkSettingsDialog extends StatefulWidget {
  const BenchmarkSettingsDialog({
    super.key,
    required this.title,
    required this.durationLabel,
    required this.durationDefault,
    required this.durationMin,
    required this.durationMax,
    required this.secondaryLabel,
    required this.secondaryDefault,
    required this.secondaryMin,
    required this.secondaryMax,
  });

  final String title;
  final String durationLabel;
  final int durationDefault;
  final int durationMin;
  final int durationMax;
  final String? secondaryLabel;
  final int? secondaryDefault;
  final int? secondaryMin;
  final int? secondaryMax;

  @override
  State<BenchmarkSettingsDialog> createState() =>
      _BenchmarkSettingsDialogState();
}

class _BenchmarkSettingsDialogState extends State<BenchmarkSettingsDialog> {
  late final TextEditingController _durationController;
  late final TextEditingController? _secondaryController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController(
      text: widget.durationDefault.toString(),
    );
    _secondaryController = widget.secondaryDefault == null
        ? null
        : TextEditingController(text: widget.secondaryDefault.toString());
  }

  @override
  void dispose() {
    _durationController.dispose();
    _secondaryController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: widget.durationLabel,
                helperText:
                    'Min ${widget.durationMin}, max ${widget.durationMax}',
              ),
            ),
            if (_secondaryController != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _secondaryController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: widget.secondaryLabel,
                  helperText:
                      'Min ${widget.secondaryMin}, max ${widget.secondaryMax}',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: TextStyle(color: Colors.red.shade300)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Start')),
      ],
    );
  }

  void _submit() {
    final duration = _readClamped(
      _durationController.text,
      widget.durationMin,
      widget.durationMax,
    );
    final secondary = _secondaryController == null
        ? null
        : _readClamped(
            _secondaryController.text,
            widget.secondaryMin!,
            widget.secondaryMax!,
          );
    if (duration == null ||
        (_secondaryController != null && secondary == null)) {
      setState(() => _error = 'Enter numeric values in the allowed range.');
      return;
    }
    Navigator.of(context).pop(
      BenchmarkSettingsResult(
        durationSeconds: duration,
        secondaryValue: secondary,
      ),
    );
  }

  int? _readClamped(String rawValue, int min, int max) {
    final value = int.tryParse(rawValue.trim());
    if (value == null) {
      return null;
    }
    return value.clamp(min, max).toInt();
  }
}

class BenchmarkSettingsResult {
  const BenchmarkSettingsResult({
    required this.durationSeconds,
    required this.secondaryValue,
  });

  final int durationSeconds;
  final int? secondaryValue;
}

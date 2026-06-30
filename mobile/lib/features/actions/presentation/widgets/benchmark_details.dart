import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/benchmark_models.dart';

class BenchmarkDetails extends StatelessWidget {
  const BenchmarkDetails({
    super.key,
    required this.status,
    required this.rawDetail,
  });

  final BenchmarkStatus? status;
  final String? rawDetail;

  @override
  Widget build(BuildContext context) {
    final outputText = formatBenchmarkOutputTail(status);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Details'),
      subtitle: const Text('Command output and raw diagnostics'),
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
      children: [
        if (status?.returnCode != null)
          _DiagnosticBlock(
            title: 'Return code',
            body: status!.returnCode.toString(),
          ),
        if (status?.command.isNotEmpty ?? false)
          _DiagnosticBlock(title: 'Command', body: status!.command.join(' ')),
        if (rawDetail != null && rawDetail!.trim().isNotEmpty)
          _DiagnosticBlock(title: 'Raw detail', body: rawDetail!.trim()),
        if (outputText.isNotEmpty)
          _DiagnosticBlock(title: 'Output tail', body: outputText),
      ],
    );
  }
}

String formatBenchmarkOutputTail(BenchmarkStatus? status) {
  return [
    if (status?.stdoutTail.isNotEmpty ?? false) ...[
      'stdout',
      ...status!.stdoutTail,
    ],
    if (status?.stderrTail.isNotEmpty ?? false) ...[
      if (status?.stdoutTail.isNotEmpty ?? false) '',
      'stderr',
      ...status!.stderrTail,
    ],
  ].join('\n');
}

class _DiagnosticBlock extends StatelessWidget {
  const _DiagnosticBlock({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              body,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:homelab_tablet/features/files/domain/models/remote_file_entry.dart';
import 'package:homelab_tablet/features/files/presentation/widgets/file_preview_dialogs.dart';
import 'package:homelab_tablet/features/files/presentation/widgets/files_view_models.dart';
import 'package:homelab_tablet/features/files/presentation/widgets/remote_file_list.dart';

void main() {
  testWidgets('remote file list exposes distinct external open action', (
    tester,
  ) async {
    FileEntryAction? selectedAction;
    const entry = RemoteFileEntry(
      name: 'runbook.pdf',
      path: '/warm/runbook.pdf',
      isDirectory: false,
      isSymbolicLink: false,
      sizeBytes: 1024,
      modifiedAt: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteFileList(
            entries: const [entry],
            currentPath: '/warm',
            dateFormat: DateFormat.yMd(),
            onOpenDirectory: (_) {},
            onPreview: (_) {},
            onDownload: (_) {},
            onCopyPath: (_) {},
            onEntryAction: (_, action) {
              selectedAction = action;
            },
          ),
        ),
      ),
    );

    expect(find.byTooltip('Preview'), findsOneWidget);
    expect(find.byTooltip('Open externally'), findsOneWidget);
    expect(find.byTooltip('Download file'), findsOneWidget);

    await tester.tap(find.byTooltip('Open externally'));
    await tester.pump();

    expect(selectedAction, FileEntryAction.openExternal);
  });

  testWidgets('unsupported preview dialog can try external open', (
    tester,
  ) async {
    var openedExternally = false;
    const entry = RemoteFileEntry(
      name: 'archive.bin',
      path: '/warm/archive.bin',
      isDirectory: false,
      isSymbolicLink: false,
      sizeBytes: 1024,
      modifiedAt: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showUnsupportedPreviewDialog(
                context,
                entry: entry,
                onCopyPath: () {},
                onDownload: () {},
                onOpenExternally: () {
                  openedExternally = true;
                },
              ),
              child: const Text('Open dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Try open externally'), findsOneWidget);

    await tester.tap(find.text('Try open externally'));
    await tester.pumpAndSettle();

    expect(openedExternally, isTrue);
  });
}

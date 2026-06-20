import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xterm/xterm.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../data/ssh_connection_service.dart';
import '../widgets/terminal_accessory_bar.dart';
import '../widgets/terminal_connection_dialogs.dart';

class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({super.key});

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage>
    with WidgetsBindingObserver {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  late final FocusNode _terminalFocusNode;
  final _terminalViewKey = GlobalKey<TerminalViewState>();

  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  SshShellConnection? _connection;
  _TerminalStatus _status = _TerminalStatus.disconnected;
  String? _message;
  DateTime? _connectedAt;
  bool _ctrlEnabled = false;
  bool _altEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _terminal = Terminal(maxLines: 5000);
    _terminalController = TerminalController();
    _terminalFocusNode = FocusNode();
    _terminal.write('SSH profile ready.\r\n');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _terminal.onOutput = null;
    _terminal.onResize = null;
    unawaited(_stdoutSubscription?.cancel() ?? Future<void>.value());
    unawaited(_stderrSubscription?.cancel() ?? Future<void>.value());
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      unawaited(connection.close());
    }
    _terminalController.dispose();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(
        _disconnect(
          message: 'Session closed after the app moved to background.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(settingsControllerProvider).sshProfile;
    if (!profile.isConfigured) {
      return _TerminalSetupState(
        title: 'SSH setup required',
        activeStep: 1,
        onOpenSettings: () => context.go('/settings'),
      );
    }
    if (!profile.hasImportedKey) {
      return _TerminalSetupState(
        title: 'Private key required',
        activeStep: 2,
        onOpenSettings: () => context.go('/settings'),
      );
    }

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
          final compact = keyboardOpen || constraints.maxHeight < 560;
          final padding = EdgeInsets.fromLTRB(
            AppSpacing.lg,
            compact ? AppSpacing.sm : AppSpacing.lg,
            AppSpacing.lg,
            compact ? AppSpacing.xs : AppSpacing.lg,
          );
          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TerminalHeaderAndActions(
                  profile: profile,
                  status: _status,
                  message: _message,
                  connectedAt: _connectedAt,
                  compact: compact,
                  connected: _connection != null,
                  connecting: _status == _TerminalStatus.connecting,
                  onConnect: _connect,
                  onDisconnect: _disconnect,
                  onCopySelection: _copySelection,
                  onCopyBuffer: _copyBuffer,
                  onPaste: _pasteClipboard,
                  onClear: _clearTerminal,
                ),
                SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                if (!compact) ...[
                  _QuickCommandBar(
                    enabled: _connection != null,
                    onCommand: _sendQuickCommand,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: TerminalView(
                        _terminal,
                        key: _terminalViewKey,
                        controller: _terminalController,
                        focusNode: _terminalFocusNode,
                        autofocus: true,
                        deleteDetection: true,
                        keyboardType: TextInputType.visiblePassword,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
                TerminalAccessoryBar(
                  compact: compact,
                  ctrlEnabled: _ctrlEnabled,
                  altEnabled: _altEnabled,
                  onCtrlToggle: (value) => setState(() => _ctrlEnabled = value),
                  onAltToggle: (value) => setState(() => _altEnabled = value),
                  onKeyPressed: _sendAccessoryKey,
                  onShortcutPressed: _sendShortcut,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _connect() async {
    final profile = ref.read(settingsControllerProvider).sshProfile;
    await _disconnect(clearMessage: true);
    setState(() {
      _status = _TerminalStatus.connecting;
      _message = 'Connecting to ${profile.host}:${profile.port}';
    });

    try {
      final service = ref.read(sshConnectionServiceProvider);
      final connection = await service.openShell(
        profile: profile,
        width: _terminal.viewWidth,
        height: _terminal.viewHeight,
        onTrustHost: (hostKey) => showHostTrustDialog(context, hostKey),
        onPassphraseRequired: () => showPassphrasePromptDialog(
          context,
          title: 'Enter the SSH key passphrase',
        ),
      );

      _connection = connection;
      _terminal.buffer.clear();
      _terminal.buffer.setCursor(0, 0);
      _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        connection.session.resizeTerminal(
          width,
          height,
          pixelWidth,
          pixelHeight,
        );
      };
      _terminal.onOutput = (data) {
        connection.session.write(Uint8List.fromList(utf8.encode(data)));
      };

      _stdoutSubscription = connection.session.stdout
          .map((chunk) => utf8.decode(chunk, allowMalformed: true))
          .listen(_terminal.write);
      _stderrSubscription = connection.session.stderr
          .map((chunk) => utf8.decode(chunk, allowMalformed: true))
          .listen(_terminal.write);
      unawaited(
        connection.session.done.whenComplete(() {
          if (mounted) {
            setState(() {
              if (identical(_connection, connection)) {
                _connection = null;
              }
              _status = _TerminalStatus.disconnected;
              _message = 'Session disconnected.';
              _connectedAt = null;
            });
          }
        }),
      );

      setState(() {
        _status = _TerminalStatus.connected;
        _connectedAt = DateTime.now();
        _message =
            'Connected to ${profile.displayName.isEmpty ? profile.host : profile.displayName}';
      });
    } catch (error) {
      setState(() {
        _status = _TerminalStatus.error;
        _message = _describeError(error);
        _connectedAt = null;
      });
    }
  }

  Future<void> _disconnect({String? message, bool clearMessage = false}) async {
    _terminal.onOutput = null;
    _terminal.onResize = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    final connection = _connection;
    _connection = null;
    if (connection != null) {
      await connection.close();
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _status = _TerminalStatus.disconnected;
      _connectedAt = null;
      if (clearMessage) {
        _message = null;
      } else if (message != null) {
        _message = message;
      }
    });
  }

  Future<void> _copySelection() async {
    final selection = _terminalController.selection;
    if (selection == null) {
      _showSnackBar('Select terminal text first.');
      return;
    }
    final text = _terminal.buffer.getText(selection);
    if (text.trim().isEmpty) {
      _showSnackBar('Selection is empty.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _terminalController.clearSelection();
    _showSnackBar('Selection copied.');
    _focusTerminal();
  }

  Future<void> _copyBuffer() async {
    final text = _terminal.buffer.getText().trimRight();
    if (text.trim().isEmpty) {
      _showSnackBar('Terminal buffer is empty.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('Terminal buffer copied.');
    _focusTerminal();
  }

  Future<void> _pasteClipboard() async {
    if (_connection == null) {
      _showSnackBar('Connect before pasting.');
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      _showSnackBar('Clipboard is empty.');
      return;
    }
    _terminal.paste(text);
    _focusTerminal();
  }

  Future<void> _clearTerminal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear terminal?'),
        content: const Text('This clears the local terminal buffer only.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    _terminal.buffer.clear();
    _terminal.buffer.setCursor(0, 0);
    _focusTerminal();
  }

  void _sendQuickCommand(String command) {
    if (_connection == null) {
      _showSnackBar('Connect before sending quick commands.');
      return;
    }
    _terminal.textInput(command);
    _terminal.keyInput(TerminalKey.enter);
    _focusTerminal();
  }

  void _sendAccessoryKey(String key) {
    if (_connection == null) {
      _showSnackBar('Connect before sending terminal keys.');
      return;
    }

    switch (key) {
      case 'Esc':
        _terminal.keyInput(
          TerminalKey.escape,
          alt: _altEnabled,
          ctrl: _ctrlEnabled,
        );
        break;
      case 'Tab':
        _terminal.keyInput(
          TerminalKey.tab,
          alt: _altEnabled,
          ctrl: _ctrlEnabled,
        );
        break;
      case 'Up':
        _terminal.keyInput(
          TerminalKey.arrowUp,
          alt: _altEnabled,
          ctrl: _ctrlEnabled,
        );
        break;
      case 'Down':
        _terminal.keyInput(
          TerminalKey.arrowDown,
          alt: _altEnabled,
          ctrl: _ctrlEnabled,
        );
        break;
      case 'Left':
        _terminal.keyInput(
          TerminalKey.arrowLeft,
          alt: _altEnabled,
          ctrl: _ctrlEnabled,
        );
        break;
      case 'Right':
        _terminal.keyInput(
          TerminalKey.arrowRight,
          alt: _altEnabled,
          ctrl: _ctrlEnabled,
        );
        break;
      default:
        if (_ctrlEnabled || _altEnabled) {
          _terminal.charInput(
            key.codeUnitAt(0),
            alt: _altEnabled,
            ctrl: _ctrlEnabled,
          );
        } else {
          _terminal.textInput(key);
        }
    }
    _clearModifiers();
    _focusTerminal();
  }

  void _sendShortcut(String shortcut) {
    if (_connection == null) {
      _showSnackBar('Connect before sending shortcuts.');
      return;
    }
    switch (shortcut) {
      case 'Ctrl+C':
        _terminal.charInput('c'.codeUnitAt(0), ctrl: true);
        break;
      case 'Ctrl+D':
        _terminal.charInput('d'.codeUnitAt(0), ctrl: true);
        break;
      case 'Ctrl+L':
        _terminal.charInput('l'.codeUnitAt(0), ctrl: true);
        break;
    }
    _clearModifiers();
    _focusTerminal();
  }

  void _clearModifiers() {
    if (_ctrlEnabled || _altEnabled) {
      setState(() {
        _ctrlEnabled = false;
        _altEnabled = false;
      });
    }
  }

  void _focusTerminal() {
    if (!mounted) {
      return;
    }
    _terminalFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _terminalViewKey.currentState?.requestKeyboard();
      }
    });
  }

  String _describeError(Object error) {
    if (error is AppException) {
      return error.message;
    }
    return error.toString();
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TerminalHeaderAndActions extends StatelessWidget {
  const _TerminalHeaderAndActions({
    required this.profile,
    required this.status,
    required this.message,
    required this.connectedAt,
    required this.compact,
    required this.connected,
    required this.connecting,
    required this.onConnect,
    required this.onDisconnect,
    required this.onCopySelection,
    required this.onCopyBuffer,
    required this.onPaste,
    required this.onClear,
  });

  final ConnectionProfile profile;
  final _TerminalStatus status;
  final String? message;
  final DateTime? connectedAt;
  final bool compact;
  final bool connected;
  final bool connecting;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onCopySelection;
  final VoidCallback onCopyBuffer;
  final VoidCallback onPaste;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final header = _TerminalHeader(
      profile: profile,
      status: status,
      message: message,
      connectedAt: connectedAt,
      compact: compact,
    );
    final actions = _TerminalActions(
      connected: connected,
      connecting: connecting,
      compact: compact,
      onConnect: onConnect,
      onDisconnect: onDisconnect,
      onCopySelection: onCopySelection,
      onCopyBuffer: onCopyBuffer,
      onPaste: onPaste,
      onClear: onClear,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (compact || constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: AppSpacing.sm),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: header),
            const SizedBox(width: AppSpacing.md),
            actions,
          ],
        );
      },
    );
  }
}

class _TerminalHeader extends StatelessWidget {
  const _TerminalHeader({
    required this.profile,
    required this.status,
    required this.message,
    required this.connectedAt,
    required this.compact,
  });

  final ConnectionProfile profile;
  final _TerminalStatus status;
  final String? message;
  final DateTime? connectedAt;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = profile.displayName.trim().isEmpty
        ? profile.host
        : profile.displayName.trim();
    final connectedSince = connectedAt == null
        ? null
        : 'Connected since ${_formatClock(connectedAt!)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.terminal, size: 20),
                Text(displayName, style: theme.textTheme.titleMedium),
                StatusBadge(label: status.label, tone: status.tone),
              ],
            ),
            SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                _HeaderDetail(
                  icon: Icons.dns,
                  label: '${profile.host}:${profile.port}',
                ),
                _HeaderDetail(
                  icon: Icons.person_outline,
                  label: profile.username,
                ),
                if (connectedSince != null)
                  _HeaderDetail(icon: Icons.schedule, label: connectedSince),
              ],
            ),
            if (message != null && message!.trim().isNotEmpty) ...[
              SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
              Text(
                message!,
                maxLines: compact ? 1 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderDetail extends StatelessWidget {
  const _HeaderDetail({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _TerminalActions extends StatelessWidget {
  const _TerminalActions({
    required this.connected,
    required this.connecting,
    required this.compact,
    required this.onConnect,
    required this.onDisconnect,
    required this.onCopySelection,
    required this.onCopyBuffer,
    required this.onPaste,
    required this.onClear,
  });

  final bool connected;
  final bool connecting;
  final bool compact;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onCopySelection;
  final VoidCallback onCopyBuffer;
  final VoidCallback onPaste;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.end,
      children: [
        FilledButton.icon(
          onPressed: connecting ? null : onConnect,
          icon: const Icon(Icons.link),
          label: Text(connected ? 'Reconnect' : 'Connect'),
        ),
        OutlinedButton.icon(
          onPressed: connected ? onDisconnect : null,
          icon: const Icon(Icons.link_off),
          label: Text(compact ? 'Close' : 'Disconnect'),
        ),
        IconButton(
          tooltip: 'Copy selected text',
          onPressed: onCopySelection,
          icon: const Icon(Icons.copy_all),
        ),
        IconButton(
          tooltip: 'Copy terminal buffer',
          onPressed: onCopyBuffer,
          icon: const Icon(Icons.library_books),
        ),
        IconButton(
          tooltip: 'Paste clipboard',
          onPressed: onPaste,
          icon: const Icon(Icons.content_paste),
        ),
        IconButton(
          tooltip: 'Clear terminal',
          onPressed: onClear,
          icon: const Icon(Icons.cleaning_services),
        ),
      ],
    );
  }
}

class _QuickCommandBar extends StatelessWidget {
  const _QuickCommandBar({required this.enabled, required this.onCommand});

  final bool enabled;
  final ValueChanged<String> onCommand;

  static const _commands = [
    _QuickCommand('clear', 'clear'),
    _QuickCommand('uptime', 'uptime'),
    _QuickCommand('htop', 'htop'),
    _QuickCommand('docker ps', 'docker ps'),
    _QuickCommand('df -h', 'df -h'),
    _QuickCommand('free -h', 'free -h'),
    _QuickCommand('failed units', 'systemctl --failed'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Center(
            child: Text(
              'Quick input',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          for (final command in _commands) ...[
            ActionChip(
              avatar: const Icon(Icons.keyboard_return, size: 16),
              label: Text(command.label),
              onPressed: enabled ? () => onCommand(command.command) : null,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _QuickCommand {
  const _QuickCommand(this.label, this.command);

  final String label;
  final String command;
}

class _TerminalSetupState extends StatelessWidget {
  const _TerminalSetupState({
    required this.title,
    required this.activeStep,
    required this.onOpenSettings,
  });

  final String title;
  final int activeStep;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    const steps = [
      'Configure SSH host and user',
      'Import private key',
      'Trust host fingerprint',
      'Connect',
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.terminal),
                    const SizedBox(width: AppSpacing.sm),
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                for (var index = 0; index < steps.length; index += 1)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      index < activeStep
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(steps[index]),
                  ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.icon(
                      onPressed: onOpenSettings,
                      icon: const Icon(Icons.settings),
                      label: const Text('Open SSH Settings'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpenSettings,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import Key'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _TerminalStatus {
  disconnected('Disconnected', StatusTone.offline),
  connecting('Connecting', StatusTone.warning),
  connected('Connected', StatusTone.healthy),
  error('Connection blocked', StatusTone.critical);

  const _TerminalStatus(this.label, this.tone);

  final String label;
  final StatusTone tone;
}

String _formatClock(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

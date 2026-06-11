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
import '../../../../core/widgets/empty_state.dart';
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

  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  SshShellConnection? _connection;
  _TerminalStatus _status = _TerminalStatus.disconnected;
  String? _message;
  bool _ctrlEnabled = false;
  bool _altEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _terminal = Terminal(maxLines: 5000);
    _terminalController = TerminalController();
    _terminal.write('SSH profile ready.\r\n');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disconnect(clearMessage: false));
    _terminalController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(
        _disconnect(message: 'Session closed after the app moved to background.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(settingsControllerProvider).sshProfile;
    if (!profile.isConfigured) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          icon: Icons.terminal,
          title: 'Configure the SSH profile first',
          message:
              'Set the SSH host, port, and username in Settings before opening the terminal.',
          action: FilledButton(
            onPressed: () => context.go('/settings'),
            child: const Text('Open Settings'),
          ),
        ),
      );
    }
    if (!profile.hasImportedKey) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          icon: Icons.key,
          title: 'Import a private key',
          message:
              'The terminal uses a direct SSH key over Tailscale. Import the key in Settings before connecting.',
          action: FilledButton(
            onPressed: () => context.go('/settings'),
            child: const Text('Open Settings'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(
                label: _status.label,
                tone: _status.tone,
              ),
              if (_message != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Text(_message!),
                ),
              FilledButton.icon(
                onPressed: _status == _TerminalStatus.connecting
                    ? null
                    : _connect,
                icon: const Icon(Icons.link),
                label: Text(
                  _status == _TerminalStatus.connected ? 'Reconnect' : 'Connect',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _connection == null ? null : _disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
              IconButton(
                tooltip: 'Copy selected text',
                onPressed: _copySelection,
                icon: const Icon(Icons.copy_all),
              ),
              IconButton(
                tooltip: 'Paste clipboard',
                onPressed: _pasteClipboard,
                icon: const Icon(Icons.content_paste),
              ),
              IconButton(
                tooltip: 'Clear terminal',
                onPressed: _clearTerminal,
                icon: const Icon(Icons.cleaning_services),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
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
                  controller: _terminalController,
                  autofocus: true,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TerminalAccessoryBar(
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
        connection.session.resizeTerminal(width, height, pixelWidth, pixelHeight);
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
              _status = _TerminalStatus.disconnected;
              _message = 'Session disconnected.';
            });
          }
        }),
      );

      setState(() {
        _status = _TerminalStatus.connected;
        _message = 'Connected to ${profile.displayName.isEmpty ? profile.host : profile.displayName}';
      });
    } catch (error) {
      setState(() {
        _status = _TerminalStatus.error;
        _message = _describeError(error);
      });
    }
  }

  Future<void> _disconnect({
    String? message,
    bool clearMessage = false,
  }) async {
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
  }

  void _clearTerminal() {
    _terminal.buffer.clear();
    _terminal.buffer.setCursor(0, 0);
  }

  void _sendAccessoryKey(String key) {
    if (_connection == null) {
      _showSnackBar('Connect before sending terminal keys.');
      return;
    }

    switch (key) {
      case 'Esc':
        _terminal.keyInput(TerminalKey.escape, alt: _altEnabled, ctrl: _ctrlEnabled);
        break;
      case 'Tab':
        _terminal.keyInput(TerminalKey.tab, alt: _altEnabled, ctrl: _ctrlEnabled);
        break;
      case 'Up':
        _terminal.keyInput(TerminalKey.arrowUp, alt: _altEnabled, ctrl: _ctrlEnabled);
        break;
      case 'Down':
        _terminal.keyInput(TerminalKey.arrowDown, alt: _altEnabled, ctrl: _ctrlEnabled);
        break;
      case 'Left':
        _terminal.keyInput(TerminalKey.arrowLeft, alt: _altEnabled, ctrl: _ctrlEnabled);
        break;
      case 'Right':
        _terminal.keyInput(TerminalKey.arrowRight, alt: _altEnabled, ctrl: _ctrlEnabled);
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
  }

  void _clearModifiers() {
    if (_ctrlEnabled || _altEnabled) {
      setState(() {
        _ctrlEnabled = false;
        _altEnabled = false;
      });
    }
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

enum _TerminalStatus {
  disconnected('Disconnected', StatusTone.offline),
  connecting('Connecting', StatusTone.warning),
  connected('Connected', StatusTone.healthy),
  error('Connection blocked', StatusTone.critical);

  const _TerminalStatus(this.label, this.tone);

  final String label;
  final StatusTone tone;
}

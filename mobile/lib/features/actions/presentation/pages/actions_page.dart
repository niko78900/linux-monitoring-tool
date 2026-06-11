import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/security/secure_storage_service.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../../network/data/control_api_client.dart';

class ActionsPage extends ConsumerStatefulWidget {
  const ActionsPage({super.key});

  @override
  ConsumerState<ActionsPage> createState() => _ActionsPageState();
}

class _ActionsPageState extends ConsumerState<ActionsPage> {
  bool _loadingToken = true;
  bool _testing = false;
  bool _waking = false;
  String? _token;
  String? _statusMessage;
  _ControlStatus _status = _ControlStatus.disconnected;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controlUrl = settings.controlApiUrl.trim();
    if (controlUrl.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          icon: Icons.power_settings_new,
          title: 'Configure the control agent first',
          message:
              'Set the Control API URL in Settings before using Wake Main PC.',
          action: FilledButton(
            onPressed: () => context.go('/settings'),
            child: const Text('Open Settings'),
          ),
        ),
      );
    }

    if (_loadingToken) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_token == null || _token!.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          icon: Icons.key,
          title: 'Control token required',
          message:
              'Store the Control API bearer token in Settings before sending privileged actions.',
          action: FilledButton(
            onPressed: () => context.go('/settings'),
            child: const Text('Open Settings'),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        SectionCard(
          title: 'Wake Main PC',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(label: _status.label, tone: _status.tone),
                  if (_statusMessage != null) Text(_statusMessage!),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'This action is fixed server-side. The mobile app does not send a MAC address.',
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: _testing ? null : () => _testControl(settings),
                    icon: const Icon(Icons.network_check),
                    label: Text(_testing ? 'Testing...' : 'Test control agent'),
                  ),
                  FilledButton.icon(
                    onPressed: _waking ? null : () => _confirmWake(settings),
                    icon: const Icon(Icons.power_settings_new),
                    label: Text(_waking ? 'Sending...' : 'Wake Main PC'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _loadToken() async {
    final token = await ref.read(secureStorageServiceProvider).readControlToken();
    if (!mounted) {
      return;
    }
    setState(() {
      _token = token;
      _loadingToken = false;
    });
  }

  Future<void> _testControl(AppSettings settings) async {
    setState(() {
      _testing = true;
      _statusMessage = null;
    });
    try {
      final client = ControlApiClient(
        baseUrl: settings.controlApiUrl,
        token: _token,
      );
      final health = await client.getHealth();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _ControlStatus.connected;
        _statusMessage = 'Connected to ${health.appName} ${health.version}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _ControlStatus.error;
        _statusMessage = _describeError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _confirmWake(AppSettings settings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Wake Main PC?'),
          content: const Text(
            'Send the allowlisted Wake-on-LAN action through the control agent.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Wake'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await _wakeMainPc(settings);
  }

  Future<void> _wakeMainPc(AppSettings settings) async {
    setState(() {
      _waking = true;
      _statusMessage = null;
    });
    try {
      final client = ControlApiClient(
        baseUrl: settings.controlApiUrl,
        token: _token,
      );
      final response = await client.wakeMainPc();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _ControlStatus.connected;
        _statusMessage =
            'Wake accepted for ${response.target}. Rate limit: ${response.rateLimitSeconds}s.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _ControlStatus.error;
        _statusMessage = _describeError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _waking = false);
      }
    }
  }

  String _describeError(Object error) {
    if (error is AppException) {
      return error.message;
    }
    return error.toString();
  }
}

enum _ControlStatus {
  disconnected('Not tested', StatusTone.unknown),
  connected('Reachable', StatusTone.healthy),
  error('Blocked', StatusTone.critical);

  const _ControlStatus(this.label, this.tone);

  final String label;
  final StatusTone tone;
}

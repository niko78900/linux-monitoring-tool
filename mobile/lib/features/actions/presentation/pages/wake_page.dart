import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/security/app_lock_service.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../data/wake_repository.dart';

class WakePage extends ConsumerStatefulWidget {
  const WakePage({super.key});

  @override
  ConsumerState<WakePage> createState() => _WakePageState();
}

class _WakePageState extends ConsumerState<WakePage> {
  bool _testing = false;
  bool _waking = false;
  String? _message;
  StatusTone _tone = StatusTone.unknown;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    if (settings.controlApiUrl.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: EmptyState(
          icon: Icons.power_settings_new,
          title: 'Configure Wake-on-LAN',
          message: 'Add the Control API URL and WOL-only token in Settings.',
          action: FilledButton(
            onPressed: () => context.go('/settings'),
            child: const Text('Open Settings'),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        SectionCard(
          title: 'Wake Main PC',
          trailing: StatusBadge(label: _statusLabel, tone: _tone),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Send the fixed, server-allowlisted Wake-on-LAN action. '
                'The phone never receives or supplies the target MAC address.',
              ),
              if (_message != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_message!),
              ],
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: _testing || _waking ? null : _testConnection,
                    icon: const Icon(Icons.network_check),
                    label: Text(_testing ? 'Testing...' : 'Test connection'),
                  ),
                  FilledButton.icon(
                    onPressed: _testing || _waking ? null : _requestWake,
                    icon: const Icon(Icons.power_settings_new),
                    label: Text(_waking ? 'Sending...' : 'Wake Main PC'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const SectionCard(
          title: 'Safety',
          child: Text(
            'Wake requests require device authentication when enabled, a '
            'second confirmation, a scoped server token, and the server rate limit.',
          ),
        ),
      ],
    );
  }

  String get _statusLabel => switch (_tone) {
    StatusTone.healthy => 'Ready',
    StatusTone.critical => 'Blocked',
    _ => 'Not tested',
  };

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _message = null;
    });
    try {
      final health = await ref.read(wakeRepositoryProvider).getHealth();
      if (!mounted) return;
      setState(() {
        _tone = StatusTone.healthy;
        _message = 'Connected to ${health.appName} ${health.version}.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _tone = StatusTone.critical;
        _message = mapError(error);
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _requestWake() async {
    final settings = ref.read(settingsControllerProvider);
    final unlocked = await ref
        .read(appLockControllerProvider.notifier)
        .ensureUnlocked(
          settings,
          localizedReason: 'Authenticate to Wake Main PC',
        );
    if (!unlocked || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wake Main PC?'),
        content: const Text(
          'Send the allowlisted Wake-on-LAN request through the control agent?',
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
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _waking = true;
      _message = null;
    });
    try {
      final result = await ref.read(wakeRepositoryProvider).wakeMainPc();
      if (!mounted) return;
      setState(() {
        _tone = StatusTone.healthy;
        _message =
            'Wake accepted for ${result.target}. '
            'Server rate limit: ${result.rateLimitSeconds}s.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _tone = StatusTone.critical;
        _message = mapError(error);
      });
    } finally {
      if (mounted) setState(() => _waking = false);
    }
  }
}

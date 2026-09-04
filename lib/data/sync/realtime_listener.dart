import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../remote/supabase_client_provider.dart';
import 'pull_service.dart';

part 'realtime_listener.g.dart';

/// Realtime is an optimisation, never a correctness requirement (spec §9.6
/// T-4.8) — the poll-based [SyncEngine] trigger points are what actually
/// guarantee eventual consistency. This just notices a change sooner: on
/// any Postgres change to `expenses`/`incomes`/`budgets` for this household,
/// debounce 2s then pull *only* that entity, guarded by
/// [AppConfig.realtimeEnabled] so the whole thing can be switched off
/// (a future Settings toggle) without changing app behaviour.
class RealtimeListener {
  RealtimeListener({required this.client, required this.pullService});

  final SupabaseClient client;
  final PullService pullService;

  RealtimeChannel? _channel;
  final Map<String, Timer> _debounceTimers = {};

  static const _watchedTables = {
    'expenses': 'expense',
    'incomes': 'income',
    'budgets': 'budget',
  };

  void start(String householdId) {
    stop();
    if (!AppConfig.realtimeEnabled) return;

    final channel = client.channel('household-changes-$householdId');
    for (final entry in _watchedTables.entries) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: entry.key,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'household_id',
          value: householdId,
        ),
        callback: (_) => _debouncedPull(entry.value, householdId),
      );
    }
    channel.subscribe();
    _channel = channel;
  }

  void _debouncedPull(String entityKey, String householdId) {
    _debounceTimers[entityKey]?.cancel();
    _debounceTimers[entityKey] = Timer(const Duration(seconds: 2), () {
      unawaited(pullService.pullEntity(entityKey, householdId));
    });
  }

  void stop() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    final channel = _channel;
    if (channel != null) {
      client.removeChannel(channel);
      _channel = null;
    }
  }
}

@Riverpod(keepAlive: true)
RealtimeListener realtimeListener(Ref ref) {
  final listener = RealtimeListener(
    client: ref.watch(supabaseClientProvider),
    pullService: ref.watch(pullServiceProvider),
  );
  ref.onDispose(listener.stop);
  return listener;
}

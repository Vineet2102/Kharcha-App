import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity_service.g.dart';

/// Thin wrapper over `connectivity_plus` (spec §9.6 trigger 3 / T-4.1). Only
/// cares about "is there a network path at all" — it does not prove internet
/// reachability, but that's an acceptable trade-off for a 5-person app: a
/// false "online" just means the next sync attempt fails and retries with
/// backoff, same as any other transient network error.
class ConnectivityService {
  ConnectivityService([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> get isOnline async =>
      _isOnline(await _connectivity.checkConnectivity());

  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(_isOnline);

  bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}

@Riverpod(keepAlive: true)
ConnectivityService connectivityService(Ref ref) => ConnectivityService();

/// Reactive online/offline flag, with an initial value from a one-off check
/// so the UI doesn't flash "offline" before the first stream event arrives.
@Riverpod(keepAlive: true)
Stream<bool> isOnline(Ref ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  yield await service.isOnline;
  yield* service.onStatusChange;
}

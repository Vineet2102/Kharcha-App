import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'supabase_client_provider.g.dart';

/// The single [SupabaseClient] instance, initialised in `main()` (T-3.1)
/// before `runApp`. Kept behind a provider — rather than reaching for
/// `Supabase.instance.client` throughout the app — so tests can override it
/// with a mock and never need a real `Supabase.initialize()` call.
@Riverpod(keepAlive: true)
SupabaseClient supabaseClient(Ref ref) => Supabase.instance.client;

/// Every sign-in/sign-out/token-refresh event, straight from the SDK.
@Riverpod(keepAlive: true)
Stream<AuthState> authStateChanges(Ref ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange;

/// The current session, reactive to [authStateChangesProvider]. Falls back
/// to the client's synchronous `currentSession` for the instant before the
/// first stream event arrives (Supabase does emit an initial event on
/// subscribe, but this avoids a null flash if that ever changes upstream).
@Riverpod(keepAlive: true)
Session? currentSession(Ref ref) {
  final fromStream = ref.watch(authStateChangesProvider).value?.session;
  return fromStream ?? ref.watch(supabaseClientProvider).auth.currentSession;
}

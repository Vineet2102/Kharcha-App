import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';
import 'table_remote_data_source.dart';

part 'payment_method_remote_ds.g.dart';

class PaymentMethodRemoteDataSource extends TableRemoteDataSource {
  PaymentMethodRemoteDataSource(SupabaseClient client)
    : super(client, 'payment_methods');
}

@Riverpod(keepAlive: true)
PaymentMethodRemoteDataSource paymentMethodRemoteDataSource(Ref ref) =>
    PaymentMethodRemoteDataSource(ref.watch(supabaseClientProvider));

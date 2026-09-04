import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';
import 'table_remote_data_source.dart';

part 'income_remote_ds.g.dart';

class IncomeRemoteDataSource extends TableRemoteDataSource {
  IncomeRemoteDataSource(SupabaseClient client) : super(client, 'incomes');
}

@Riverpod(keepAlive: true)
IncomeRemoteDataSource incomeRemoteDataSource(Ref ref) =>
    IncomeRemoteDataSource(ref.watch(supabaseClientProvider));

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';
import 'table_remote_data_source.dart';

part 'budget_remote_ds.g.dart';

class BudgetRemoteDataSource extends TableRemoteDataSource {
  BudgetRemoteDataSource(SupabaseClient client) : super(client, 'budgets');
}

@Riverpod(keepAlive: true)
BudgetRemoteDataSource budgetRemoteDataSource(Ref ref) =>
    BudgetRemoteDataSource(ref.watch(supabaseClientProvider));

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';
import 'table_remote_data_source.dart';

part 'expense_remote_ds.g.dart';

class ExpenseRemoteDataSource extends TableRemoteDataSource {
  ExpenseRemoteDataSource(SupabaseClient client) : super(client, 'expenses');
}

@Riverpod(keepAlive: true)
ExpenseRemoteDataSource expenseRemoteDataSource(Ref ref) =>
    ExpenseRemoteDataSource(ref.watch(supabaseClientProvider));

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';
import 'table_remote_data_source.dart';

part 'recurring_rule_remote_ds.g.dart';

class RecurringRuleRemoteDataSource extends TableRemoteDataSource {
  RecurringRuleRemoteDataSource(SupabaseClient client)
    : super(client, 'recurring_rules');
}

@Riverpod(keepAlive: true)
RecurringRuleRemoteDataSource recurringRuleRemoteDataSource(Ref ref) =>
    RecurringRuleRemoteDataSource(ref.watch(supabaseClientProvider));

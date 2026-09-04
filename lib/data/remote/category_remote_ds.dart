import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';
import 'table_remote_data_source.dart';

part 'category_remote_ds.g.dart';

class CategoryRemoteDataSource extends TableRemoteDataSource {
  CategoryRemoteDataSource(SupabaseClient client) : super(client, 'categories');
}

@Riverpod(keepAlive: true)
CategoryRemoteDataSource categoryRemoteDataSource(Ref ref) =>
    CategoryRemoteDataSource(ref.watch(supabaseClientProvider));

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';
import 'table_remote_data_source.dart';

part 'attachment_remote_ds.g.dart';

class AttachmentRemoteDataSource extends TableRemoteDataSource {
  AttachmentRemoteDataSource(SupabaseClient client)
    : super(client, 'attachments');
}

@Riverpod(keepAlive: true)
AttachmentRemoteDataSource attachmentRemoteDataSource(Ref ref) =>
    AttachmentRemoteDataSource(ref.watch(supabaseClientProvider));

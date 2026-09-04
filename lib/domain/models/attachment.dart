import 'package:freezed_annotation/freezed_annotation.dart';

part 'attachment.freezed.dart';
part 'attachment.g.dart';

@freezed
abstract class Attachment with _$Attachment {
  const factory Attachment({
    required String id,
    @JsonKey(name: 'household_id') required String householdId,
    @JsonKey(name: 'expense_id') required String expenseId,
    @JsonKey(name: 'storage_path') required String storagePath,
    @JsonKey(name: 'mime_type') @Default('image/jpeg') String mimeType,
    @JsonKey(name: 'size_bytes') @Default(0) int sizeBytes,
    @JsonKey(name: 'width_px') int? widthPx,
    @JsonKey(name: 'height_px') int? heightPx,
    @JsonKey(name: 'uploaded_by') required String uploadedBy,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Attachment;

  factory Attachment.fromJson(Map<String, Object?> json) =>
      _$AttachmentFromJson(json);
}

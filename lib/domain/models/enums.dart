import 'package:json_annotation/json_annotation.dart';

/// Mirrors the Postgres enums in `0001_extensions.sql` exactly.

enum MemberRole { admin, member }

enum CategoryKind { expense, income }

enum PayMethodType { cash, upi, card, bank, wallet, other }

enum BudgetScope {
  household,
  user,
  category,
  @JsonValue('user_category')
  userCategory,
}

enum RecurFrequency { daily, weekly, monthly, yearly }

enum TxnKind { expense, income }

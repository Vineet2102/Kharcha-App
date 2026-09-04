/// One grouping key (a member/category/payment-method id) paired with its
/// summed `amount_paise` for a period — the Dashboard's per-member and
/// top-categories breakdowns (spec §11.4, T-6.1). Not a synced entity, so
/// (unlike the other domain models) this has no JSON codec.
class GroupedTotal {
  const GroupedTotal({required this.key, required this.amountPaise});

  final String key;
  final int amountPaise;
}

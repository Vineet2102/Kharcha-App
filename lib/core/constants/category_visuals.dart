import 'package:flutter/material.dart';

import '../../domain/models/enums.dart';

/// Fixed 16-swatch colour palette for category `colour_hex` (spec §11.5) —
/// deliberately small and closed so every device renders the same set of
/// choices, and so hex values stay predictable for the icon/colour picker.
const List<String> categoryColourPalette = [
  '#F44336', // red
  '#E91E63', // pink
  '#9C27B0', // purple
  '#673AB7', // deep purple
  '#3F51B5', // indigo
  '#2196F3', // blue
  '#03A9F4', // light blue
  '#00BCD4', // cyan
  '#009688', // teal
  '#4CAF50', // green
  '#8BC34A', // light green
  '#CDDC39', // lime
  '#FFC107', // amber
  '#FF9800', // orange
  '#795548', // brown
  '#607D8B', // blue grey (default)
];

Color colourFromHex(String hex) {
  final value = hex.replaceFirst('#', '');
  return Color(int.parse('FF$value', radix: 16));
}

/// Fixed set of ~40 Material icon keys for category `icon_key` (spec §11.5).
/// The key (not the [IconData]) is what's persisted, so this map is the only
/// place allowed to change which icon a key renders as.
const Map<String, IconData> categoryIconOptions = {
  'category': Icons.category,
  'restaurant': Icons.restaurant,
  'local_cafe': Icons.local_cafe,
  'local_grocery_store': Icons.local_grocery_store,
  'shopping_cart': Icons.shopping_cart,
  'shopping_bag': Icons.shopping_bag,
  'directions_car': Icons.directions_car,
  'local_gas_station': Icons.local_gas_station,
  'directions_bus': Icons.directions_bus,
  'flight': Icons.flight,
  'home': Icons.home,
  'bolt': Icons.bolt,
  'water_drop': Icons.water_drop,
  'wifi': Icons.wifi,
  'phone_android': Icons.phone_android,
  'local_hospital': Icons.local_hospital,
  'medication': Icons.medication,
  'fitness_center': Icons.fitness_center,
  'school': Icons.school,
  'menu_book': Icons.menu_book,
  'movie': Icons.movie,
  'sports_esports': Icons.sports_esports,
  'music_note': Icons.music_note,
  'checkroom': Icons.checkroom,
  'spa': Icons.spa,
  'pets': Icons.pets,
  'child_care': Icons.child_care,
  'card_giftcard': Icons.card_giftcard,
  'celebration': Icons.celebration,
  'favorite': Icons.favorite,
  'volunteer_activism': Icons.volunteer_activism,
  'build': Icons.build,
  'cleaning_services': Icons.cleaning_services,
  'local_laundry_service': Icons.local_laundry_service,
  'savings': Icons.savings,
  'account_balance': Icons.account_balance,
  'receipt_long': Icons.receipt_long,
  'work': Icons.work,
  'laptop': Icons.laptop,
  'more_horiz': Icons.more_horiz,
};

IconData iconForKey(String key) =>
    categoryIconOptions[key] ?? categoryIconOptions['category']!;

/// Payment methods have no user-chosen icon — their `type` enum maps to a
/// fixed icon (spec §11.5 only describes icon/colour pickers for
/// categories; `payment_method` has no `icon_key`/`colour_hex` column).
IconData iconForPaymentMethodType(PayMethodType type) => switch (type) {
  PayMethodType.cash => Icons.payments_outlined,
  PayMethodType.upi => Icons.qr_code_scanner,
  PayMethodType.card => Icons.credit_card,
  PayMethodType.bank => Icons.account_balance_outlined,
  PayMethodType.wallet => Icons.account_balance_wallet_outlined,
  PayMethodType.other => Icons.more_horiz,
};

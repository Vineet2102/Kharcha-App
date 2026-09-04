import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/app.dart';

void main() {
  testWidgets('App boots to the placeholder dashboard (Gate 2)', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KharchaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsWidgets);
  });
}

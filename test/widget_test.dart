import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LoveApp());
    expect(find.text('로그인'), findsWidgets);
  });
}

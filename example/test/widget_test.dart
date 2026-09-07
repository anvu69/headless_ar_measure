import 'package:flutter_test/flutter_test.dart';
import 'package:headless_ar_measure_example/main.dart';

void main() {
  testWidgets('thiếu plugin thì báo không hỗ trợ chứ không treo màn', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('not supported'), findsOneWidget);
  });
}

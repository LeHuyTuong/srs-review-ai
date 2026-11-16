import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/widgets/app_text_input.dart';

void main() {
  testWidgets('AppTextInput forwards controller updates and change events', (
    t,
  ) async {
    final controller = TextEditingController(text: 'initial');
    String? changed;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTextInput(
            controller: controller,
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );

    await t.enterText(find.byType(TextField), 'typed');
    expect(changed, 'typed');
    expect(controller.text, 'typed');
    await t.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('Text entry dialog returns text on save and null on cancel', (
    t,
  ) async {
    String? result = 'pending';
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showAppTextEntryDialog(
                  context,
                  title: 'Lưu chế độ xem',
                  fieldLabel: 'Tên chế độ xem',
                  cancelLabel: 'Hủy',
                  confirmLabel: 'Lưu',
                );
              },
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    );

    await t.tap(find.text('Mở'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '  Lịch thi  ');
    await t.tap(find.text('Lưu'));
    await t.pumpAndSettle();
    expect(result, '  Lịch thi  ');

    await t.tap(find.text('Mở'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hủy'));
    await t.pumpAndSettle();
    expect(result, isNull);
  });
}

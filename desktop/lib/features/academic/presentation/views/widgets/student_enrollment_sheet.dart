import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_presentation_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/student_enrollment_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/academic_page.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_academic_layout.dart';
import 'package:srs_review_ai/widgets/app_badge.dart';
import 'package:srs_review_ai/widgets/app_button.dart';

// Ba cách thêm sinh viên trong cùng bảng nhập; QR chứa mã tham gia của lớp đang xem.
class StudentEnrollmentSheet extends ConsumerWidget {
  const StudentEnrollmentSheet({required this.classId, super.key});
  final String classId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(academicViewModelProvider).requireValue;
    final c = data.classRoom(classId)!;
    final state = ref.watch(studentEnrollmentProvider(classId));
    final vm = ref.read(studentEnrollmentProvider(classId).notifier);
    final valid = vm.validRowCount;
    return AppSheetLayout(
      title: 'Thêm sinh viên',
      description: 'Chọn cách thêm sinh viên vào lớp.',
      footer: state.tab == 0
          ? null
          : AppButton(
              label: state.tab == 1
                  ? 'Thêm $valid sinh viên hợp lệ'
                  : 'Thêm ${state.selected.length} sinh viên',
              loading: state.busy,
              onPressed:
                  c.archived ||
                      (state.tab == 1 ? valid == 0 : state.selected.isEmpty)
                  ? null
                  : () async {
                      if (await vm.save() && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
            ),
      children: [
        AppTabs(
          segmented: true,
          expanded: true,
          labels: const ['Mã QR', 'Import danh sách', 'Nhập thủ công'],
          selected: state.tab,
          onChanged: vm.tab,
        ),
        if (c.archived)
          const AppNotice(
            'Lớp đã lưu trữ. Khôi phục lớp trước khi thêm sinh viên.',
          ),
        if (state.tab == 0) ...[
          Center(
            child: QrImageView(
              data: c.text('joinCode'),
              size: AppMetrics.qrSize,
            ),
          ),
          Text(
            c.code,
            textAlign: TextAlign.center,
            style: AppTypography.header,
          ),
          Text(
            c.text('joinCode'),
            textAlign: TextAlign.center,
            style: AppTypography.courseCode,
          ),
          Row(
            spacing: AppSpacing.s,
            children: [
              Expanded(
                child: AppButton(
                  label: 'Sao chép mã',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => academicAction(
                    context,
                    () => vm.copy(c.text('joinCode')),
                  ),
                ),
              ),
              Expanded(
                child: AppButton(
                  label: 'Sao chép link',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => academicAction(
                    context,
                    () => vm.copy(
                      'https://review.university.edu.vn/join/${c.text('joinCode')}',
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(
            'Hết hạn: ${c.text('qrExpiresAt')}${AcademicPresentationViewModel(data).qrExpired(c) ? ' · Đã hết hạn' : ''}',
            style: AppTypography.muted,
          ),
          AppButton(
            label: 'Tạo lại mã QR',
            variant: AppButtonVariant.secondary,
            onPressed: c.archived
                ? null
                : () => academicAction(context, vm.regenerate),
          ),
          const AppNotice(
            'Tạo lại mã sẽ vô hiệu mã cũ. Sinh viên dùng mã mới để tham gia lớp.',
          ),
        ],
        if (state.tab == 1) ...[
          AppButton(
            label: 'Chọn tệp danh sách',
            variant: AppButtonVariant.secondary,
            onPressed: vm.pick,
          ),
          const Text('CSV hoặc XLSX · tối đa 500 dòng'),
          TextButton(
            onPressed: vm.sample,
            child: const Text('Dùng tệp mẫu để xem trước'),
          ),
          if (state.fileName.isNotEmpty)
            Text(state.fileName, style: AppTypography.strong),
          if (state.fileName.toLowerCase().endsWith('.xlsx'))
            const AppNotice(
              'XLSX hiện dùng dữ liệu mẫu như Lab 2. Chọn CSV để đọc danh sách thực từ tệp.',
            ),
          if (state.rows.isNotEmpty) ...[
            Text(
              '$valid hợp lệ · ${vm.existingRowCount} đã tồn tại · ${vm.invalidRowCount} lỗi',
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final label in [
                    'Mã SV',
                    'Họ tên',
                    'Email',
                    'Trạng thái',
                  ])
                    DataColumn(label: Text(label)),
                ],
                rows: [
                  for (final r in state.rows)
                    DataRow(
                      cells: [
                        DataCell(Text(r['studentCode'] as String)),
                        DataCell(Text(r['name'] as String)),
                        DataCell(Text(r['email'] as String)),
                        DataCell(
                          AppBadge(
                            const {
                                  'valid': 'Hợp lệ',
                                  'exists': 'Đã tồn tại',
                                  'format': 'Sai định dạng',
                                  'missing': 'Thiếu thông tin',
                                }[r['status']] ??
                                '',
                            tone: r['status'] == 'valid' ? 'brand' : 'amber',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
        if (state.tab == 2) ...[
          TextField(
            decoration: const InputDecoration(
              hintText: 'Tìm theo tên, mã sinh viên hoặc email',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: vm.query,
          ),
          for (final s in vm.candidates)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: state.selected.contains(
                s.id.isEmpty ? s.text('studentCode') : s.id,
              ),
              onChanged: (_) =>
                  vm.select(s.id.isEmpty ? s.text('studentCode') : s.id),
              title: Text(s.name, style: AppTypography.strong),
              subtitle: Text('${s.text('studentCode')} · ${s.text('email')}'),
            ),
          if (vm.candidates.isEmpty)
            const Text('Không tìm thấy sinh viên phù hợp.'),
        ],
        if (state.error.isNotEmpty) AppNotice(state.error, error: true),
      ],
    );
  }
}

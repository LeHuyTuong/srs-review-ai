import 'package:srs_review_ai_mobile/theme/app_feature_metrics.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/document_reader_view_model.dart';

// Đọc nội dung mẫu từ React; chưa đọc dữ liệu PDF hoặc DOCX thật của sinh viên.
class SampleDocumentReader extends ConsumerWidget {
  const SampleDocumentReader({
    required this.review,
    required this.snapshot,
    this.fullscreen = false,
    super.key,
  });
  final AcademicRecord review;
  final AcademicSnapshot snapshot;
  final bool fullscreen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = review;
    // Tách trạng thái đọc theo yêu cầu và phiên bản để mở bản nộp khác không dùng nhầm trang đang xem.
    final key = 'reader:${r.id}:${r.text('version')}';
    final reading = ref.watch(documentReaderProvider(key));
    final page = reading.page;
    final vm = ref.read(documentReaderProvider(key).notifier);
    final total = r.integer('pageCount', 1).clamp(1, 10000);
    final controls = IconButton.styleFrom(
      minimumSize: const Size.square(AppSpacing.tapMin),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.s),
      ),
      side: const BorderSide(color: AppColors.line),
    );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.s,
              children: [
                Row(
                  spacing: AppSpacing.s,
                  children: [
                    Expanded(
                      child: Text(
                        'Nội dung tài liệu',
                        style: AppTypography.blockTitle,
                      ),
                    ),
                    if (fullscreen)
                      IconButton(
                        tooltip: 'Đóng toàn màn hình',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      )
                    else
                      const AppBadge('Nội dung mẫu'),
                  ],
                ),
                if (!fullscreen)
                  Text(
                    '${r.text('fileName')} · ${r.text('version')}',
                    style: AppTypography.muted,
                  ),
              ],
            ),
          ),
          if (!fullscreen) ...[
            const Divider(height: AppMetrics.border, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Row(
                spacing: AppSpacing.s,
                children: [
                  IconButton.outlined(
                    style: controls,
                    tooltip: 'Trang trước',
                    onPressed: page <= 0
                        ? null
                        : () => vm.selectPage(page - 1, total),
                    icon: const AppIcon('chevron-left'),
                  ),
                  Expanded(
                    child: Text(
                      'Trang ${page + 1} / $total',
                      textAlign: TextAlign.center,
                      style: AppTypography.strong,
                    ),
                  ),
                  IconButton.outlined(
                    style: controls,
                    tooltip: 'Trang sau',
                    onPressed: page >= total - 1
                        ? null
                        : () => vm.selectPage(page + 1, total),
                    icon: const AppIcon('chevron-right'),
                  ),
                  IconButton.outlined(
                    style: controls,
                    tooltip: 'Phóng to tài liệu',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) => Scaffold(
                          body: SafeArea(
                            child: _FullscreenReader(
                              review: r,
                              snapshot: snapshot,
                              startPage: page,
                              offset: reading.offset,
                              onOffsetChanged: vm.rememberOffset,
                            ),
                          ),
                        ),
                      ),
                    ),
                    icon: const AppIcon('maximize'),
                  ),
                ],
              ),
            ),
          ],
          Container(
            color: AppColors.subtle,
            padding: const EdgeInsets.all(AppSpacing.m),
            child: DocumentSamplePage(
              review: r,
              snapshot: snapshot,
              page: page,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenReader extends StatefulWidget {
  const _FullscreenReader({
    required this.review,
    required this.snapshot,
    required this.startPage,
    required this.offset,
    required this.onOffsetChanged,
  });
  final AcademicRecord review;
  final AcademicSnapshot snapshot;
  final int startPage;
  final double? offset;
  final ValueChanged<double> onOffsetChanged;
  @override
  State<_FullscreenReader> createState() => _FullscreenReaderState();
}

class _FullscreenReaderState extends State<_FullscreenReader> {
  final selected = GlobalKey();
  late final controller = ScrollController(
    initialScrollOffset: widget.offset ?? 0,
  );
  @override
  void initState() {
    super.initState();
    // Theo dõi cuộn để nhớ vị trí; lần đầu chưa có vị trí thì cuộn tới trang đã chọn sau khi dựng xong.
    controller.addListener(_remember);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.offset == null && selected.currentContext != null) {
        Scrollable.ensureVisible(selected.currentContext!, alignment: 0);
      }
    });
  }

  void _remember() => widget.onOffsetChanged(controller.offset);
  @override
  void dispose() {
    // Gỡ listener trước khi hủy bộ điều khiển để không giữ liên kết tới màn đọc đã đóng.
    controller.removeListener(_remember);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Row(
          children: [
            Expanded(
              child: Text('Nội dung tài liệu', style: AppTypography.blockTitle),
            ),
            IconButton(
              tooltip: 'Đóng toàn màn hình',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          controller: controller,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              spacing: AppSpacing.l,
              children: [
                for (
                  var page = 0;
                  page < widget.review.integer('pageCount', 1);
                  page++
                )
                  DocumentSamplePage(
                    key: page == widget.startPage ? selected : null,
                    review: widget.review,
                    snapshot: widget.snapshot,
                    page: page,
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

// Trang mẫu phân chia nội dung theo số mục đối chiếu và pageCount của bản nộp.
class DocumentSamplePage extends StatelessWidget {
  const DocumentSamplePage({
    required this.review,
    required this.snapshot,
    required this.page,
    super.key,
  });
  final AcademicRecord review;
  final AcademicSnapshot snapshot;
  final int page;
  @override
  Widget build(BuildContext context) {
    final r = review;
    final title = r.text('documentTitle');
    final pageChecks = DocumentSampleData(snapshot, r, page).pageChecks;
    final content = page == 0
        ? <Widget>[
            Text(
              '${r.text('classCode')} · ${r.text('groupName').toUpperCase()}',
              textAlign: TextAlign.center,
              style: AppTypography.strong.copyWith(color: AppColors.muted),
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.ruleHeading,
            ),
            Text(r.text('projectName'), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s),
            Text(
              'Phiên bản ${r.text('version')} · Người nộp: ${r.text('submitter')}',
              textAlign: TextAlign.center,
              style: AppTypography.muted,
            ),
            Text(
              r.text('submittedAt'),
              textAlign: TextAlign.center,
              style: AppTypography.muted,
            ),
          ]
        : <Widget>[
            if (title.toLowerCase().contains('use case') && page == 1) ...[
              const _SampleDiagram(),
              Text('Use Case tổng quan', style: AppTypography.muted),
            ],
            if (pageChecks.isEmpty) ...[
              Text('Phụ lục · $title', style: AppTypography.strong),
              const Text(
                'Tham chiếu các mục nội dung ở đầu tài liệu. Không có ghi chú bổ sung cho trang này.',
              ),
            ] else
              for (final c in pageChecks) ...[
                Text(c.name, style: AppTypography.strong),
                Text(
                  c.text('text'),
                  style: AppTypography.body.copyWith(
                    height: AppFeatureMetrics.sampleBodyLineHeight,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
              ],
          ];
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppMetrics.documentReadingWidth,
          minHeight: AppMetrics.documentPageMinHeight,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.l),
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppSpacing.xs),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (page == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Column(spacing: AppSpacing.s, children: content),
                )
              else
                ...content,
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.l),
                child: Text(
                  '$title · ${r.text('version')} — ${page + 1}',
                  textAlign: TextAlign.center,
                  style: AppTypography.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Hình học lấy từ StaticDiagram của React; Canvas giữ cả chữ SVG mà flutter_svg không dựng.
class _SampleDiagram extends StatelessWidget {
  const _SampleDiagram();
  @override
  Widget build(BuildContext context) => const AspectRatio(
    aspectRatio: AppFeatureMetrics.sampleDiagramAspectRatio,
    child: CustomPaint(painter: _DiagramPainter()),
  );
}

class _DiagramPainter extends CustomPainter {
  const _DiagramPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 320, size.height / 200);
    final paint = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    void line(double x, double y, double xx, double yy) =>
        canvas.drawLine(Offset(x, y), Offset(xx, yy), paint);
    void label(String value, double x, double y) {
      final text = TextPainter(
        text: TextSpan(
          text: value,
          style: AppTypography.body.copyWith(
            fontSize: AppFeatureMetrics.sampleDiagramLabelSize,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(x - text.width / 2, y));
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(80, 8, 160, 184),
        const Radius.circular(6),
      ),
      paint,
    );
    label('Hệ thống review tài liệu', 160, 14);
    for (final actor in [
      ('Student', 36.0, 70.0),
      ('Supervisor', 284.0, 120.0),
    ]) {
      final x = actor.$2, y = actor.$3;
      canvas.drawCircle(Offset(x, y - 18), 6, paint);
      line(x, y - 12, x, y + 6);
      line(x - 9, y - 6, x + 9, y - 6);
      line(x, y + 6, x - 7, y + 18);
      line(x, y + 6, x + 7, y + 18);
      label(actor.$1, x, y + 24);
    }
    final cases = [
      'Login',
      'Manage Project',
      'Upload Document',
      'Submit Document',
      'Review Document',
    ];
    for (var i = 0; i < cases.length; i++) {
      final y = 42.0 + i * 33;
      line(i < 4 ? 46 : 274, i < 4 ? 64 : 112, i < 4 ? 100 : 220, y);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(160, y), width: 120, height: 24),
        Paint()..color = AppColors.subtle,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(160, y), width: 120, height: 24),
        paint,
      );
      label(cases[i], 160, y - 4);
    }
  }

  @override
  bool shouldRepaint(covariant _DiagramPainter oldDelegate) => false;
}

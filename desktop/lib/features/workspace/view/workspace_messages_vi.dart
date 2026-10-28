/// Vietnamese presentation of application-owned runtime messages.
/// Call only at UI boundaries, never on source text, quotes, IDs or payloads.
/// Unknown provider diagnostics remain intact so useful evidence is not lost.
String workspaceMessage(String message) {
  final exact = _messages[message];
  if (exact != null) return exact;
  for (final entry in _prefixes.entries) {
    if (message.startsWith(entry.key)) {
      return entry.value +
          workspaceMessage(message.substring(entry.key.length));
    }
  }
  var text = message;
  for (final (pattern, replacement) in _patterns) {
    text = text.replaceAllMapped(pattern, replacement);
  }
  for (final entry in _fragments.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text;
}

const _prefixes = <String, String>{
  'Unable to read this document: ': 'Không thể đọc tài liệu: ',
  'Could not open the PDF (it may be corrupted, empty or password protected): ':
      'Không thể mở PDF (tệp có thể hỏng, trống hoặc có mật khẩu): ',
  'Could not read the DOCX archive: ': 'Không thể đọc tệp DOCX: ',
  'Could not create the share link: ': 'Không thể tạo liên kết chia sẻ: ',
  'Could not load history: ': 'Không thể tải lịch sử: ',
  'Could not open review: ': 'Không thể mở phiên đánh giá: ',
  'Diagram audit stopped: ': 'Kiểm tra sơ đồ đã dừng: ',
};

const _messages = <String, String>{
  'Reading file…': 'Đang đọc tệp…',
  'Opening DOCX archive…': 'Đang mở tệp DOCX…',
  'Extracting text…': 'Đang trích xuất văn bản…',
  'Detecting requirements…': 'Đang nhận diện yêu cầu…',
  'Not found in the document.': 'Không tìm thấy trong tài liệu.',
  'Saved review restored.': 'Đã khôi phục phiên đánh giá.',
  'Could not open review.': 'Không thể mở phiên đánh giá.',
  'Share link created — anyone with the URL can read it.':
      'Đã tạo liên kết chia sẻ; bất kỳ ai có liên kết đều có thể đọc báo cáo.',
  'No units selected. Adjust your selection; nothing will be silently skipped.':
      'Chưa chọn mục nào. Hãy chọn các yêu cầu cần chấm.',
  'Restored sessions hold no file bytes. Import a document before running a new review.':
      'Phiên khôi phục không lưu tệp gốc. Hãy tải lại tài liệu trước khi chấm lượt mới.',
  'Review failed. Your selection is preserved.':
      'Chấm điểm thất bại. Các mục đã chọn vẫn được giữ nguyên.',
  'Review cancelled · nothing had been reviewed yet.':
      'Đã hủy lượt chấm; chưa có mục nào được đánh giá.',
  'The vision audit needs the original file in memory — restored sessions keep findings but not bytes. Re-import to audit.':
      'Kiểm tra sơ đồ cần tệp gốc trong bộ nhớ. Hãy tải lại tài liệu; phiên khôi phục chỉ lưu kết quả.',
  'Legacy .doc files are not supported. Save the file as .docx or PDF and try again.':
      'Chưa hỗ trợ tệp .doc cũ. Hãy lưu thành DOCX hoặc PDF rồi thử lại.',
  'This PDF has no text layer — it looks like a scan. OCR is out of scope; please upload the original PDF exported from Word.':
      'PDF không có lớp văn bản, có thể là bản quét. Ứng dụng chưa hỗ trợ OCR; hãy tải PDF gốc được xuất từ Word.',
  'The DOCX body is empty.': 'Nội dung DOCX trống.',
  'No text found in the DOCX file.': 'Không tìm thấy văn bản trong DOCX.',
  'The proxy returned an empty body.': 'Máy chủ trả về nội dung trống.',
  'The proxy rejected the app token.': 'Máy chủ từ chối mã truy cập ứng dụng.',
  'The proxy rejected the request payload — the app and proxy contracts disagree.':
      'Máy chủ từ chối dữ liệu: phiên bản ứng dụng và máy chủ không tương thích.',
  'The AI provider is unavailable right now. Retry, or run in mock mode for the demo.':
      'Nhà cung cấp AI hiện không khả dụng. Hãy thử lại hoặc dùng chế độ mô phỏng.',
  'Daily review quota reached. Reuse a cached review or try again tomorrow.':
      'Đã hết lượt chấm trong ngày. Dùng lại kết quả đã lưu hoặc thử lại vào ngày mai.',
  'Daily review quota reached. Reuse a cached result or try again tomorrow.':
      'Đã hết lượt chấm trong ngày. Dùng lại kết quả đã lưu hoặc thử lại vào ngày mai.',
  'All requirement statements look like English.':
      'Các phát biểu yêu cầu đều có dấu hiệu viết bằng tiếng Anh.',
  'No TBD/placeholder text found.':
      'Không tìm thấy nội dung TBD hoặc chỗ giữ chỗ.',
  'No unmeasurable wording flagged by the conservative phrase scan ("all"/"some" deliberately not scanned).':
      'Bộ quét chưa phát hiện diễn đạt không đo được (không quét “all” và “some” để hạn chế báo sai).',
  'At least one requirement names a priority field (srs-writer quality criterion 7, Prioritized).':
      'Ít nhất một yêu cầu có trường mức ưu tiên (tiêu chí chất lượng 7).',
  'No requirement in this document names a priority (priority / do uu tien / muc do uu tien). A reviewer cannot sequence fixes without it (srs-writer quality criterion 7, Prioritized).':
      'Chưa có yêu cầu nào nêu mức ưu tiên; cần bổ sung để sắp xếp thứ tự thực hiện và sửa lỗi (tiêu chí chất lượng 7).',
  'State the requirement with "shall" plus a verifiable acceptance criterion.':
      'Viết yêu cầu bằng cấu trúc bắt buộc (“shall”) kèm tiêu chí nghiệm thu có thể kiểm chứng.',
};

final _patterns = <(RegExp, String Function(Match))>[
  (
    RegExp(
      r'(\d+) item\(s\) unreadable at render resolution — tiny-text verdicts understate risk\.',
    ),
    (m) =>
        '${m[1]} chi tiết không đọc được ở độ phân giải hiện tại; kết luận có thể chưa phản ánh đủ rủi ro từ chữ nhỏ.',
  ),
  (
    RegExp(r'^Not a valid DOCX file: (.+) is missing\.$'),
    (m) => 'DOCX không hợp lệ: thiếu ${m[1]}.',
  ),
  (
    RegExp(r'Daily review quota reached\. Retry in about (\d+) h\.'),
    (m) => 'Đã hết lượt chấm trong ngày. Thử lại sau khoảng ${m[1]} giờ.',
  ),
  (
    RegExp(
      r'^Entity "(.+)" appears as (.+) across (\d+) sections \((.+)\)\. Same concept, different labels — pick one name\.$',
    ),
    (m) =>
        'Thực thể “${m[1]}” có các tên ${m[2]} ở ${m[3]} phần (${m[4]}). Cần thống nhất một tên cho cùng khái niệm.',
  ),
  (
    RegExp(
      r'^Vision audit of page (\d+) \((.+?)\): no notation issues found in (\d+) element\(s\), (\d+) relation\(s\)\.',
    ),
    (m) =>
        'Kiểm tra trang ${m[1]} (${m[2]}): chưa phát hiện lỗi ký pháp trong ${m[3]} phần tử và ${m[4]} quan hệ.',
  ),
  (
    RegExp(
      r'^Vision audit of page (\d+) \((.+?)\): no drawn diagram found on this page \(0 elements, 0 relations\) — nothing to grade\.',
    ),
    (m) =>
        'Kiểm tra trang ${m[1]} (${m[2]}): không thấy sơ đồ (0 phần tử, 0 quan hệ), chưa có nội dung để chấm.',
  ),
  (
    RegExp(r'^Page (\d+) \((.+?)\): (\d+) issue\(s\) — '),
    (m) => 'Trang ${m[1]} (${m[2]}): ${m[3]} lỗi — ',
  ),
  (RegExp(r'^Reading (.+)…$'), (m) => 'Đang đọc ${m[1]}…'),
  (RegExp(r'^Parsing (.+)…$'), (m) => 'Đang phân tích ${m[1]}…'),
  (
    RegExp(r'^Extracting text \(page (\d+)/(\d+)\)…$'),
    (m) => 'Đang trích xuất văn bản (trang ${m[1]}/${m[2]})…',
  ),
  (
    RegExp(r'^(\d+) units extracted\. All detected IDs have been preserved\.$'),
    (m) => 'Đã trích xuất ${m[1]} mục. Tất cả mã ID đều được giữ lại.',
  ),
  (
    RegExp(r'(\d+) units reviewed · (\d+) verified findings'),
    (m) => 'Đã chấm ${m[1]} mục · ${m[2]} lỗi đã đối chiếu',
  ),
  (
    RegExp(r'(\d+) failed and were NOT reviewed'),
    (m) => '${m[1]} mục thất bại, chưa được chấm',
  ),
  (
    RegExp(r'(\d+) left out by the (\d+)-unit per-run cap'),
    (m) => '${m[1]} mục chưa chấm do giới hạn ${m[2]} mục/lượt',
  ),
  (
    RegExp(r'(\d+) unit\(s\) (?:were )?reviewed and saved on this device\.'),
    (m) => 'Đã chấm và lưu ${m[1]} mục trên thiết bị.',
  ),
  (
    RegExp(r'^This file is ([\d.]+) MB\. The limit is (\d+) MB\.$'),
    (m) => 'Tệp có dung lượng ${m[1]} MB, vượt giới hạn ${m[2]} MB.',
  ),
  (
    RegExp(r'^This PDF has (\d+) pages\. The limit is (\d+) pages\.$'),
    (m) => 'PDF có ${m[1]} trang, vượt giới hạn ${m[2]} trang.',
  ),
  (
    RegExp(r'^Only PDF and DOCX files are supported(?: \(got (.+)\))?\.$'),
    (m) => 'Chỉ hỗ trợ PDF và DOCX${m[1] == null ? '' : ' (đã chọn ${m[1]})'}.',
  ),
  (
    RegExp(r'^Unsupported file type "(.+)"\. Choose a PDF or DOCX file\.$'),
    (m) => 'Không hỗ trợ định dạng ${m[1]}. Hãy chọn PDF hoặc DOCX.',
  ),
  (
    RegExp(r'Cannot reach the review proxy at (.+)\. Start it with .+'),
    (m) =>
        'Không kết nối được máy chủ tại ${m[1]}. Kiểm tra địa chỉ và kết nối hoặc bật chế độ mô phỏng.',
  ),
  (
    RegExp(r'The review took longer than (\d+)s and timed out\.'),
    (m) => 'Lượt chấm vượt quá ${m[1]} giây và đã hết thời gian chờ.',
  ),
  (
    RegExp(r'Daily review quota reached\. Retry in about (\d+) min\.'),
    (m) => 'Đã hết lượt chấm trong ngày. Thử lại sau khoảng ${m[1]} phút.',
  ),
  (
    RegExp(r'Unexpected proxy error( \(HTTP \d+\))?\.'),
    (m) => 'Lỗi máy chủ ngoài dự kiến${m[1] ?? ''}.',
  ),
  (
    RegExp(
      r'^Found (\d+) use cases, below the (\d+) required to defend in round 1\.$',
    ),
    (m) => 'Có ${m[1]} Use Case, thấp hơn ngưỡng ${m[2]} để bảo vệ vòng 1.',
  ),
  (
    RegExp(r'^Found (\d+) use cases, at or above the (\d+) required\.$'),
    (m) => 'Có ${m[1]} Use Case, đạt ngưỡng tối thiểu ${m[2]}.',
  ),
  (
    RegExp(
      r'^Found (\d+) use cases, inside the recommended (\d+)–(\d+) range\.$',
    ),
    (m) => 'Có ${m[1]} Use Case, nằm trong khoảng khuyến nghị ${m[2]}–${m[3]}.',
  ),
  (
    RegExp(
      r'^Found (\d+) use cases, above the (\d+) this rubric recommends\..*$',
    ),
    (m) =>
        'Có ${m[1]} Use Case, cao hơn mức khuyến nghị ${m[2]}. Đây chưa hẳn là lỗi; hãy kiểm tra quy mô ở F9.',
  ),
  (
    RegExp(
      r'^(.+) is not written in English\. The syllabus requires all documents in English\.$',
    ),
    (m) =>
        '${m[1]} có dấu hiệu không viết bằng tiếng Anh. Syllabus yêu cầu tài liệu bằng tiếng Anh.',
  ),
  (
    RegExp(
      r'^(.+) looks thin: ~(\d+) transactions detected, a medium use case needs (\d+)–(\d+)\.$',
    ),
    (m) =>
        '${m[1]} có khoảng ${m[2]} bước xử lý, ít hơn mức ${m[3]}–${m[4]} của Use Case cỡ vừa.',
  ),
  (
    RegExp(
      r'^(.+) looks oversized: ~(\d+) transactions detected\. Consider splitting it\.$',
    ),
    (m) =>
        '${m[1]} có khoảng ${m[2]} bước xử lý, có dấu hiệu quá lớn. Cân nhắc tách Use Case.',
  ),
  (
    RegExp(r'^Id "(.+)" is used by (\d+) requirements\..*$'),
    (m) =>
        'Mã “${m[1]}” được dùng cho ${m[2]} yêu cầu. Cần xác nhận việc dùng lại mã có chủ ý hay không.',
  ),
  (
    RegExp(r'^Use case "(.+)" has no Postcondition section\..*$'),
    (m) =>
        'Use Case “${m[1]}” thiếu hậu điều kiện. Người kiểm thử chưa có trạng thái kết thúc đo được để xác nhận luồng hoàn tất.',
  ),
  (
    RegExp(r'^Use case "(.+)" has no Actor label\..*$'),
    (m) =>
        'Use Case “${m[1]}” thiếu tác nhân, chưa rõ ai hoặc hệ thống nào thực hiện luồng.',
  ),
  (
    RegExp(r'^(.+) uses unmeasurable wording: (.+)\. Replace with.*$'),
    (m) =>
        '${m[1]} dùng diễn đạt không đo được: ${m[2]}. Thay bằng số, ngưỡng hoặc bước kiểm thử (tiêu chí 2 và 3).',
  ),
  (
    RegExp(r'^(.+) still carries placeholder text: (.+)\. A submitted.*$'),
    (m) =>
        '${m[1]} còn nội dung giữ chỗ: ${m[2]}. Cần hoàn thiện trước khi nộp (tiêu chí 4).',
  ),
  (
    RegExp(r'^(.+) states a figure and the condition it is measured under\.$'),
    (m) => '${m[1]} đã nêu chỉ số và điều kiện đo.',
  ),
  (
    RegExp(
      r'^(.+) has neither a measurable figure nor a measurement condition\..*$',
    ),
    (m) =>
        '${m[1]} thiếu cả chỉ số và điều kiện đo, chưa thể kiểm thử (quy tắc 6, mục 1.5).',
  ),
  (
    RegExp(
      r'^(.+) names a measurement condition but no figure to measure against.*$',
    ),
    (m) =>
        '${m[1]} có điều kiện đo nhưng thiếu chỉ số đối chiếu (quy tắc 6, mục 1.5).',
  ),
  (
    RegExp(r'^(.+) gives a figure but not the condition it holds under.*$'),
    (m) =>
        '${m[1]} có chỉ số nhưng thiếu điều kiện đo: tải, phân vị hoặc phần cứng (quy tắc 6, mục 1.5).',
  ),
  (
    RegExp(
      r'^"(.+)" is not measurable\. Replace it with a threshold a tester can verify, e\.g\. "within 2s for 95% of requests"\.$',
    ),
    (m) =>
        '“${m[1]}” không đo được. Thay bằng ngưỡng có thể kiểm thử, ví dụ: trong 2 giây với 95% yêu cầu.',
  ),
  (
    RegExp(
      r'Saved (?:review|workspace) was written by parser (.+?); re-import the document to (?:review it|start fresh)\.',
    ),
    (m) =>
        'Phiên đã lưu dùng bộ trích xuất ${m[1]}. Hãy tải lại tài liệu để bắt đầu phiên mới.',
  ),
];

const _fragments = <String, String>{
  'Unable to read this document: ': 'Không thể đọc tài liệu: ',
  'Could not open the PDF (it may be corrupted, empty or password protected): ':
      'Không thể mở PDF (tệp có thể hỏng, trống hoặc có mật khẩu): ',
  'Could not read the DOCX archive: ': 'Không thể đọc tệp DOCX: ',
  'Could not create the share link: ': 'Không thể tạo liên kết chia sẻ: ',
  'Could not load history: ': 'Không thể tải lịch sử: ',
  'Could not open review: ': 'Không thể mở phiên đánh giá: ',
  'Review cancelled': 'Đã hủy lượt chấm',
  'Review failed.': 'Chấm điểm thất bại.',
  'Your selection is preserved.': 'Các mục đã chọn vẫn được giữ nguyên.',
  'saved on this device': 'đã lưu trên thiết bị',
  'Diagram audit stopped: ': 'Kiểm tra sơ đồ đã dừng: ',
  'Vision audit: ': 'Kiểm tra sơ đồ: ',
  ' page(s)': ' trang',
  ' skipped (quota cap)': ' bỏ qua do giới hạn lượt',
  ' failed': ' thất bại',
  'Every diagram audit failed (first: ':
      'Tất cả trang sơ đồ đều kiểm tra thất bại (lỗi đầu tiên: ',
  ') — the pages were not seen; no verdict was written.':
      ') — chưa xem được ảnh trang; chưa có kết luận.',
  // The two shapes of the missing-renderer notice: the standalone line the
  // Findings tab shows, and the tail the run summary appends to its sentence.
  'This platform has no PDF renderer — the diagrams were reviewed from '
          'text only, not from their images.':
      'Thiết bị này không có bộ vẽ PDF; sơ đồ chỉ được chấm từ văn bản, không chấm từ ảnh trang.',
  ' · this platform has no PDF renderer — the diagrams were reviewed from '
          'text only, not from their images':
      ' · thiết bị này không có bộ vẽ PDF nên sơ đồ chỉ được chấm từ văn bản',
  'The proxy could not answer (': 'Máy chủ không thể trả lời (',
  '). These are the matching passages from your document instead — no model was ':
      '). Dưới đây là đoạn văn phù hợp trong tài liệu; không có mô hình nào được ',
  'called.': 'gọi.',
  'involved.': 'sử dụng.',
};

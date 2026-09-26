// The normalization defence line. The real OTES mixes precomposed letters
// and raw combining marks in one document (proven by
// tool/probe_vague_otes.dart); these fixtures encode both forms of the
// same words so NFC-only or NFD-only matching can never regress silently.
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/text_fold.dart';

void main() {
  group('foldVietnamese', () {
    test('NFC and NFD forms of the same word fold identically', () {
      const nfc = 'nhanh chóng'; // ố precomposed
      const nfd = 'nhanh ch\u006F\u0301\u0302ng'; // o + acute + circumflex
      expect(foldVietnamese(nfc), 'nhanh chong');
      expect(foldVietnamese(nfd), 'nhanh chong');
    });

    test('the full tone stack folds to ASCII bases', () {
      expect(
        foldVietnamese('Hệ thống người dùng cập nhật dễ sử dụng'),
        'he thong nguoi dung cap nhat de su dung',
      );
    });

    test('đ folds to d', () {
      expect(foldVietnamese('Địa điểm đăng ký'), 'dia diem dang ky');
    });

    test('English passes through, lowercased', () {
      expect(foldVietnamese('The System shall'), 'the system shall');
    });

    test('fold is idempotent', () {
      final once = foldVietnamese('Trường hợp sử dụng');
      expect(foldVietnamese(once), once);
    });

    test('punctuation and digits survive untouched', () {
      expect(
        foldVietnamese('Bước 3: nhập mã (≤ 10 ký tự)'),
        'Buoc 3: nhap ma (≤ 10 ky tu)'.toLowerCase(),
      );
    });

    test('whitespace runs (newlines, NBSP) collapse to one space', () {
      // PDF extraction breaks phrases across lines; a phrase pattern
      // must still match "he\nthong" the same as "he thong".
      expect(foldVietnamese('hệ\nthống'), 'he thong');
      expect(foldVietnamese('nhanh\u00A0\u00A0chóng'), 'nhanh chong');
      // The real OTES hides U+2028 LINE SEPARATOR inside table cells —
      // found by probing, not by reading the spec.
      expect(foldVietnamese('h\u1EC7\u2028th\u1ED1ng'), 'he thong');
    });
  });
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// Injection seam for pdfx so the screen can be rendered without native PDF
/// channels in widget tests.
typedef SubmissionPdfDocumentOpener = Future<PdfDocument> Function(
  Uint8List bytes,
);
typedef SubmissionPdfSupportProbe = Future<bool> Function();

class SubmissionPdfPreview extends StatefulWidget {
  const SubmissionPdfPreview({
    required this.bytes,
    required this.fileName,
    this.openDocument,
    this.pdfSupport,
    super.key,
  });

  final Uint8List bytes;
  final String fileName;
  final SubmissionPdfDocumentOpener? openDocument;
  final SubmissionPdfSupportProbe? pdfSupport;

  @override
  State<SubmissionPdfPreview> createState() => _SubmissionPdfPreviewState();
}

class _SubmissionPdfPreviewState extends State<SubmissionPdfPreview> {
  PdfControllerPinch? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final supported = await (widget.pdfSupport ?? hasPdfSupport)();
      if (!supported) throw StateError('Thiết bị này chưa hỗ trợ xem PDF.');
      final document = await (widget.openDocument ?? PdfDocument.openData)(
        widget.bytes,
      );
      if (!mounted) {
        await document.close();
        return;
      }
      setState(
        () =>
            _controller = PdfControllerPinch(document: Future.value(document)),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Không xem được PDF. $_error'),
            ),
          )
        : _controller == null
        ? const Center(child: CircularProgressIndicator())
        : PdfViewPinch(
            controller: _controller!,
            builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
              options: const DefaultBuilderOptions(),
              documentLoaderBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
              pageLoaderBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, error) =>
                  Center(child: Text('Lỗi đọc PDF: $error')),
            ),
          ),
  );
}

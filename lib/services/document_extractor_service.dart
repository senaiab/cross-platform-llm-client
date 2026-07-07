// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Extracts plain text from document files (PDF, DOCX) so they can be
/// fed into local or cloud LLMs as context.
class DocumentExtractorService {
  /// Extract text from a file based on its extension.
  static Future<String> extractText(String path, String extension) async {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return _extractPdf(path);
      case 'docx':
        return _extractDocx(path);
      case 'xlsx':
      case 'xls':
        return _extractXlsx(path);
      case 'pptx':
        return _extractPptx(path);
      case 'txt':
      case 'md':
      case 'json':
      case 'csv':
      case 'log':
      case 'yaml':
      case 'yml':
      case 'xml':
      case 'dart':
      case 'kt':
      case 'java':
      case 'js':
      case 'ts':
      case 'py':
        final bytes = await File(path).readAsBytes();
        return utf8.decode(bytes, allowMalformed: true);
      default:
        throw UnsupportedError(
          'Document extraction not supported for .$extension files',
        );
    }
  }

  /// Extract text from a PDF file using Syncfusion PDF.
  static Future<String> _extractPdf(String path) async {
    final bytes = await File(path).readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      return extractor.extractText();
    } finally {
      document.dispose();
    }
  }

  /// Extract text from a DOCX file using pure Dart (archive + xml).
  static Future<String> _extractDocx(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final documentFile = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw Exception('Invalid DOCX: word/document.xml not found'),
    );

    final xmlString = utf8.decode(documentFile.content as List<int>);
    final document = XmlDocument.parse(xmlString);

    // Preserve paragraph breaks: <w:p> elements separate paragraphs.
    final paragraphs = <String>[];
    for (final p in document.findAllElements('w:p')) {
      final pTexts = p.findAllElements('w:t').map((e) => e.value).join();
      if (pTexts.isNotEmpty) paragraphs.add(pTexts);
    }

    return paragraphs.isNotEmpty
        ? paragraphs.join('\n\n')
        : document.findAllElements('w:t').map((e) => e.value).join();
  }

  static Future<String> _extractXlsx(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Load shared strings table
    final sharedStringsFile = archive.files
        .where((f) => f.name == 'xl/sharedStrings.xml')
        .firstOrNull;
    final sharedStrings = <String>[];
    if (sharedStringsFile != null) {
      final xml = XmlDocument.parse(utf8.decode(sharedStringsFile.content as List<int>));
      for (final si in xml.findAllElements('si')) {
        sharedStrings.add(si.findAllElements('t').map((e) => e.innerText).join());
      }
    }

    // Find all sheet files
    final sheetFiles = archive.files
        .where((f) => f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final buffer = StringBuffer();
    for (final sheet in sheetFiles) {
      final xml = XmlDocument.parse(utf8.decode(sheet.content as List<int>));
      for (final row in xml.findAllElements('row')) {
        final cells = <String>[];
        for (final cell in row.findAllElements('c')) {
          final t = cell.getAttribute('t');
          final v = cell.findAllElements('v').firstOrNull?.innerText ?? '';
          if (t == 's') {
            final idx = int.tryParse(v) ?? -1;
            cells.add(idx >= 0 && idx < sharedStrings.length ? sharedStrings[idx] : '');
          } else {
            cells.add(v);
          }
        }
        if (cells.any((c) => c.isNotEmpty)) buffer.writeln(cells.join('\t'));
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  static Future<String> _extractPptx(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final slideFiles = archive.files
        .where((f) => f.name.startsWith('ppt/slides/slide') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final buffer = StringBuffer();
    for (final slide in slideFiles) {
      final xml = XmlDocument.parse(utf8.decode(slide.content as List<int>));
      final texts = xml.findAllElements('a:t').map((e) => e.innerText.trim()).where((t) => t.isNotEmpty);
      if (texts.isNotEmpty) buffer.writeln(texts.join(' '));
    }
    return buffer.toString().trim();
  }
}

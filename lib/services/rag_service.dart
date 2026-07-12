import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class RagService extends GetxService {
  static const _embedChannel = MethodChannel('com.write4me.llama_flutter_android/embeddings');
  Database? _db;
  String? _embedModelPath;

  bool get _supportsLocalRag => Platform.isAndroid || Platform.isIOS;

  Future<RagService> init() async {
    if (!_supportsLocalRag) return this;
    final dbPath = p.join(await getDatabasesPath(), 'rag_store.db');
    _db = await openDatabase(dbPath, version: 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE chunks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source TEXT NOT NULL,
          title TEXT NOT NULL,
          ord INTEGER NOT NULL,
          text TEXT NOT NULL,
          embedding BLOB NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_source ON chunks(source)');
    });
    return this;
  }

  void setEmbedModel(String path) => _embedModelPath = path;

  bool get isConfigured => _embedModelPath != null;

  Future<bool> initEmbedModel(String path) async {
    if (!_supportsLocalRag) return false;
    final ok = await _embedChannel.invokeMethod<bool>('initEmbedModel', {'path': path}) ?? false;
    if (ok) _embedModelPath = path;
    return ok;
  }

  Future<List<double>?> _embed(String text) async {
    if (_embedModelPath == null) return null;
    final vec = await _embedChannel.invokeMethod<List>('embed', {'text': text});
    return vec?.cast<double>();
  }

  List<String> _chunkText(String text, {int maxChars = 800, int overlap = 100}) {
    final clean = text.replaceAll('\r\n', '\n').trim();
    if (clean.isEmpty) return [];
    if (clean.length <= maxChars) return [clean];
    final chunks = <String>[];
    final paras = clean.split(RegExp(r'\n{2,}'));
    final buf = StringBuffer();
    for (final para in paras) {
      final candidate = buf.isEmpty ? para : '${buf.toString()}\n\n$para';
      if (candidate.length <= maxChars) {
        buf.clear(); buf.write(candidate);
      } else {
        if (buf.isNotEmpty) {
          chunks.add(buf.toString());
          final tail = buf.toString();
          buf.clear();
          if (tail.length > overlap) buf.write(tail.substring(tail.length - overlap));
          buf.write('\n\n$para');
        } else {
          var i = 0;
          while (i < para.length) {
            final end = min(i + maxChars, para.length);
            chunks.add(para.substring(i, end));
            if (end >= para.length) break;
            i = max(end - overlap, i + 1);
            if (chunks.length >= 256) break;
          }
        }
      }
      if (chunks.length >= 256) break;
    }
    if (buf.isNotEmpty && chunks.length < 256) chunks.add(buf.toString());
    return chunks;
  }

  Future<int> indexText(String source, String title, String text) async {
    if (_db == null) throw StateError('RAG not initialized');
    if (_embedModelPath == null) throw StateError('Embed model not configured');
    final chunks = _chunkText(text);
    if (chunks.isEmpty) return 0;
    await _db!.delete('chunks', where: 'source = ?', whereArgs: [source]);
    for (var i = 0; i < chunks.length; i++) {
      final vec = await _embed(chunks[i]);
      if (vec == null) throw StateError('Embedding failed for chunk $i');
      // Store as raw bytes (4 bytes per float, little-endian)
      final byteData = ByteData(vec.length * 4);
      for (var j = 0; j < vec.length; j++) {
        byteData.setFloat32(j * 4, vec[j].toDouble(), Endian.little);
      }
      final blob = byteData.buffer.asUint8List();
      await _db!.insert('chunks', {'source': source, 'title': title, 'ord': i, 'text': chunks[i], 'embedding': blob});
    }
    return chunks.length;
  }

  Future<List<Map<String, dynamic>>> search(String query, {int k = 5}) async {
    if (_db == null || _embedModelPath == null) return [];
    final qVec = await _embed(query);
    if (qVec == null) return [];
    final rows = await _db!.query('chunks', columns: ['source', 'title', 'text', 'embedding']);
    final scored = <Map<String, dynamic>>[];
    for (final row in rows) {
      final blob = row['embedding'] as Uint8List;
      // Safe float32 extraction using ByteData to avoid alignment issues
      final byteData = ByteData.view(Uint8List.fromList(blob).buffer);
      final n = blob.length ~/ 4;
      double dot = 0;
      for (var i = 0; i < min(n, qVec.length); i++) {
        dot += byteData.getFloat32(i * 4, Endian.little) * qVec[i];
      }
      scored.add({...row, 'score': dot, 'embedding': null});
    }
    scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return scored.take(k).map((r) => {'source': r['source'], 'title': r['title'], 'text': r['text'], 'score': r['score']}).toList();
  }

  Future<List<Map<String, dynamic>>> listSources() async {
    if (_db == null) return [];
    return _db!.rawQuery('SELECT source, title, COUNT(*) as chunks FROM chunks GROUP BY source, title');
  }

  Future<int> clearSource(String source) async {
    if (_db == null) return 0;
    return _db!.delete('chunks', where: 'source = ?', whereArgs: [source]);
  }

  Future<int> clearAll() async {
    if (_db == null) return 0;
    return _db!.delete('chunks');
  }

  Future<int> count() async {
    if (_db == null) return 0;
    final result = await _db!.rawQuery('SELECT COUNT(*) as n FROM chunks');
    return result.first['n'] as int? ?? 0;
  }
}

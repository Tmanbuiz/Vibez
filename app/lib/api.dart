import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiError implements Exception {
  final String message;
  final int status;
  ApiError(this.message, this.status);
  @override
  String toString() => message;
}

String errText(Object e) => e is ApiError ? e.message : e.toString();

class ModelInfo {
  final String id;
  final String name;
  ModelInfo(this.id, this.name);
}

/// Talks to your TmanVibez Cloudflare Worker (which holds the Venice key).
class Api {
  static String base = '';
  static String token = '';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    base = p.getString('base') ?? '';
    token = p.getString('token') ?? '';
  }

  static Future<void> save(String b, String t) async {
    final p = await SharedPreferences.getInstance();
    base = b.trim().replaceAll(RegExp(r'/+$'), '');
    token = t.trim();
    await p.setString('base', base);
    await p.setString('token', token);
  }

  static bool get ready => base.isNotEmpty && token.isNotEmpty;

  static Map<String, String> get _h => {'authorization': 'Bearer $token'};
  static Map<String, String> get _hj => {..._h, 'content-type': 'application/json'};
  static Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$base$path').replace(queryParameters: q);

  static String mediaUrl(String id) => '$base/api/media/$id?token=${Uri.encodeQueryComponent(token)}';

  static dynamic _decode(http.Response r) {
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      body = r.body;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    String msg;
    if (body is Map && body['error'] != null) {
      msg = body['error'] is String ? body['error'] as String : jsonEncode(body['error']);
    } else {
      msg = 'HTTP ${r.statusCode}';
    }
    throw ApiError(msg, r.statusCode);
  }

  static Future<dynamic> _get(String path, [Map<String, String>? q]) async =>
      _decode(await http.get(_u(path, q), headers: _h));

  static Future<dynamic> _post(String path, Map<String, dynamic> body) async =>
      _decode(await http.post(_u(path), headers: _hj, body: jsonEncode(body)));

  static Future<List<ModelInfo>> models(String type) async {
    final j = await _get('/api/models', {'type': type});
    final list = (j is Map ? j['data'] : j) as List? ?? [];
    return list.map((m) {
      final spec = m['model_spec'];
      final name = spec is Map && spec['name'] != null ? spec['name'].toString() : m['id'].toString();
      return ModelInfo(m['id'].toString(), name);
    }).toList();
  }

  static Future<Map<String, dynamic>> quote(String kind, Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(await _post('/api/quote', {'kind': kind, ...body}) as Map);

  static Future<Map<String, dynamic>> queue(String kind, Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(await _post('/api/$kind', body) as Map);

  static Future<Map<String, dynamic>> image(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(await _post('/api/image', body) as Map);

  static Future<Map<String, dynamic>> speak(String voice, String text) async =>
      Map<String, dynamic>.from(await _post('/api/speak', {'voice': voice, 'text': text}) as Map);

  static Future<Map<String, dynamic>> job(String id) async =>
      Map<String, dynamic>.from(await _get('/api/jobs/$id') as Map);

  static Future<List<Map<String, dynamic>>> library() async {
    final j = await _get('/api/library');
    return (j as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> deleteItem(String id) async {
    _decode(await http.delete(_u('/api/library/$id'), headers: _h));
  }

  static Future<List<Map<String, dynamic>>> voices() async {
    final j = await _get('/api/voices');
    return (j as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> deleteVoice(String id) async {
    _decode(await http.delete(_u('/api/voices/${Uri.encodeComponent(id)}'), headers: _h));
  }

  static MediaType _mime(String filename) {
    final e = filename.toLowerCase().split('.').last;
    switch (e) {
      case 'wav':
        return MediaType('audio', 'wav');
      case 'mp3':
        return MediaType('audio', 'mpeg');
      case 'm4a':
        return MediaType('audio', 'mp4');
      case 'flac':
        return MediaType('audio', 'flac');
      case 'mp4':
        return MediaType('video', 'mp4');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  static Future<void> createVoice(String name, List<int> bytes, String filename) async {
    final req = http.MultipartRequest('POST', _u('/api/voices'))
      ..headers.addAll(_h)
      ..fields['name'] = name
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _mime(filename)));
    _decode(await http.Response.fromStream(await req.send()));
  }

  static Future<List<Map<String, dynamic>>> singers() async {
    final j = await _get('/api/singers');
    return (j as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> revoice(String songId, String singerId) async =>
      Map<String, dynamic>.from(await _post('/api/revoice', {'song_id': songId, 'singer_id': singerId}) as Map);

  static Future<void> deleteSinger(String id) async {
    _decode(await http.delete(_u('/api/singers/${Uri.encodeComponent(id)}'), headers: _h));
  }

  static Future<void> createSinger(String name, List<int> bytes, String filename) async {
    final req = http.MultipartRequest('POST', _u('/api/singers'))
      ..headers.addAll(_h)
      ..fields['name'] = name
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _mime(filename)));
    _decode(await http.Response.fromStream(await req.send()));
  }
}

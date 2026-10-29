import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'i18n.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  final String code;
  final Map<String, dynamic> details;

  ApiException(this.message, {this.status = 0, this.code = '', this.details = const {}});

  /// أول رسالة خطأ لحقل معيّن (من تحقق السيرفر)
  String? field(String name) => details[name]?.toString();

  @override
  String toString() => message;
}

class ApiResponse {
  final dynamic data;
  final Map<String, dynamic> meta;
  ApiResponse(this.data, this.meta);

  List<Map<String, dynamic>> get list =>
      (data as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Map<String, dynamic> get map => Map<String, dynamic>.from((data as Map?) ?? const {});
}

/// عميل الـ API: يتعامل مع التوكن (مخزن في Keychain / Keystore) وصيغة الاستجابة الموحدة
class ApiClient {
  static const _tokenKey = 'gg_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final http.Client _http = http.Client();
  String? _token;
  void Function()? onUnauthorized;

  bool get hasToken => _token != null && _token!.isNotEmpty;

  Future<void> init() async {
    try {
      _token = await _storage.read(key: _tokenKey);
    } catch (_) {
      _token = null;
    }
  }

  Future<void> setToken(String? token) async {
    _token = token;
    try {
      if (token == null) {
        await _storage.delete(key: _tokenKey);
      } else {
        await _storage.write(key: _tokenKey, value: token);
      }
    } catch (_) {
      // التخزين الآمن غير متاح: نكمل بالتوكن في الذاكرة فقط
    }
  }

  Future<ApiResponse> get(String path, [Map<String, dynamic>? query]) => _send('GET', path, query: query);
  Future<ApiResponse> post(String path, [Object? body]) => _send('POST', path, body: body);
  Future<ApiResponse> patch(String path, [Object? body]) => _send('PATCH', path, body: body);
  Future<ApiResponse> delete(String path, [Object? body]) => _send('DELETE', path, body: body);

  Future<ApiResponse> _send(String method, String path, {Map<String, dynamic>? query, Object? body}) async {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && '$v'.isNotEmpty) q[k] = '$v';
    });
    final uri = Uri.parse(AppConfig.apiBase + path).replace(queryParameters: q.isEmpty ? null : q);
    final req = http.Request(method, uri);
    req.headers['Accept'] = 'application/json';
    req.headers['X-Client'] = 'app';
    req.headers['Accept-Language'] = L.code;
    req.headers['User-Agent'] = 'GhaniGroupApp/1.0 (${Platform.operatingSystem})';
    if (hasToken) req.headers['Authorization'] = 'Bearer $_token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    http.Response res;
    try {
      final streamed = await _http.send(req).timeout(const Duration(seconds: 20));
      res = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException(tr('انتهت مهلة الاتصال، حاول مرة أخرى', 'Connection timed out, please try again'));
    } on SocketException {
      throw ApiException(tr('لا يوجد اتصال بالإنترنت', 'No internet connection'));
    } on http.ClientException {
      throw ApiException(tr('تعذر الاتصال بالسيرفر', "Couldn't reach the server"));
    } on HandshakeException {
      throw ApiException(tr('تعذر إنشاء اتصال آمن بالسيرفر', "Couldn't create a secure connection to the server"));
    }

    Map<String, dynamic> json;
    try {
      json = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {
      throw ApiException(tr('استجابة غير متوقعة من السيرفر (${res.statusCode})', 'Unexpected server response (${res.statusCode})'), status: res.statusCode);
    }

    if (json['ok'] != true) {
      final err = Map<String, dynamic>.from((json['error'] as Map?) ?? const {});
      if (res.statusCode == 401 && hasToken) {
        await setToken(null);
        onUnauthorized?.call();
      }
      final details = err['details'];
      throw ApiException(
        err['message']?.toString() ?? tr('حدث خطأ', 'Something went wrong'),
        status: res.statusCode,
        code: err['code']?.toString() ?? '',
        details: details is Map ? Map<String, dynamic>.from(details) : const {},
      );
    }
    final meta = json['meta'];
    return ApiResponse(json['data'], meta is Map ? Map<String, dynamic>.from(meta) : const {});
  }
}

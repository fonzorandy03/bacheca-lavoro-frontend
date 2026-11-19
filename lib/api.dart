import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Client verso il back-end. Singleton con sessione persistente.
class Api {
  Api._();
  static final Api i = Api._();

  // 10.0.2.2 = il computer host visto dall'emulatore Android.
  // Su telefono reale va impostato l'IP del PC (dalle impostazioni dell'app).
  static const defaultBaseUrl = 'http://10.0.2.2:8090';

  late SharedPreferences _prefs;
  String baseUrl = defaultBaseUrl;
  String? token;
  String? companyName;

  bool get loggedIn => token != null;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs.getString('baseUrl') ?? defaultBaseUrl;
    token = _prefs.getString('token');
    companyName = _prefs.getString('companyName');
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _prefs.setString('baseUrl', baseUrl);
  }

  Map<String, String> get _auth =>
      token == null ? {} : {'authorization': 'Bearer $token'};

  Uri _u(String path) => Uri.parse('$baseUrl/api$path');

  dynamic _decode(http.Response r) {
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (r.statusCode >= 400) {
      throw ApiException(
          (body is Map ? body['error'] : null) ?? 'Errore ${r.statusCode}');
    }
    return body;
  }

  Future<T> _wrap<T>(Future<T> Function() f) async {
    try {
      return await f().timeout(const Duration(seconds: 15));
    } on SocketException {
      throw ApiException('Server non raggiungibile ($baseUrl)');
    } on http.ClientException {
      throw ApiException('Server non raggiungibile ($baseUrl)');
    } on Exception catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Errore di rete: server non raggiungibile');
    }
  }

  Future<dynamic> _get(String p) =>
      _wrap(() async => _decode(await http.get(_u(p), headers: _auth)));

  Future<dynamic> _post(String p, Map<String, dynamic> body) =>
      _wrap(() async => _decode(await http.post(_u(p),
          headers: {..._auth, 'content-type': 'application/json'},
          body: jsonEncode(body))));

  // --- Azienda ---
  Future<void> register(String name, String email, String password) =>
      _post('/register', {'name': name, 'email': email, 'password': password});

  Future<void> login(String email, String password) async {
    final r = await _post('/login', {'email': email, 'password': password});
    token = r['token'];
    companyName = r['company']['name'];
    await _prefs.setString('token', token!);
    await _prefs.setString('companyName', companyName!);
  }

  Future<void> logout() async {
    try {
      await _post('/logout', {});
    } catch (_) {
      // anche se il server è irraggiungibile, la sessione locale viene chiusa
    }
    token = null;
    companyName = null;
    await _prefs.remove('token');
    await _prefs.remove('companyName');
  }

  // --- Bacheca ---
  Future<List<Map<String, dynamic>>> jobs() async =>
      List<Map<String, dynamic>>.from(await _get('/jobs'));

  Future<void> createJob(String title, String description, String location) =>
      _post('/jobs',
          {'title': title, 'description': description, 'location': location});

  Future<List<Map<String, dynamic>>> myJobs() async =>
      List<Map<String, dynamic>>.from(await _get('/my/jobs'));

  Future<List<Map<String, dynamic>>> applications(String jobId) async =>
      List<Map<String, dynamic>>.from(
          await _get('/my/jobs/$jobId/applications'));

  // --- Candidatura ---
  Future<void> apply(String jobId, Map<String, String> fields,
      PlatformFile cv) {
    return _wrap(() async {
      final req = http.MultipartRequest('POST', _u('/jobs/$jobId/applications'))
        ..fields.addAll(fields);
      if (cv.path != null) {
        req.files.add(await http.MultipartFile.fromPath('cv', cv.path!,
            filename: cv.name));
      } else if (cv.bytes != null) {
        req.files.add(http.MultipartFile.fromBytes('cv', cv.bytes!,
            filename: cv.name));
      }
      final res = await http.Response.fromStream(await req.send());
      _decode(res);
    });
  }

  /// Scarica il curriculum in una cartella temporanea e ne restituisce il percorso.
  Future<String> downloadCv(String applicationId, String name) {
    return _wrap(() async {
      final r = await http.get(_u('/applications/$applicationId/cv'),
          headers: _auth);
      if (r.statusCode >= 400) _decode(r);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${applicationId}_$name');
      await file.writeAsBytes(r.bodyBytes);
      return file.path;
    });
  }
}

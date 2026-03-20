import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/database/storage_service.dart';

class SyncState {
  final bool found;
  final String? boardData;
  final int? score;
  final int? novelIndex;
  final int? currentNovelId;
  final String? novelTitle;

  const SyncState({
    required this.found,
    this.boardData,
    this.score,
    this.novelIndex,
    this.currentNovelId,
    this.novelTitle,
  });

  factory SyncState.fromJson(Map<String, dynamic> json) {
    return SyncState(
      found: json['found'] == true,
      boardData: json['board_data'] as String?,
      score: (json['score'] as num?)?.toInt(),
      novelIndex: (json['novel_index'] as num?)?.toInt(),
      currentNovelId: (json['current_novel_id'] as num?)?.toInt(),
      novelTitle: json['novel_title'] as String?,
    );
  }
}

class SyncResult {
  final bool ok;
  final String message;
  final SyncState? state;

  const SyncResult({required this.ok, required this.message, this.state});

  factory SyncResult.success({String message = 'ok', SyncState? state}) {
    return SyncResult(ok: true, message: message, state: state);
  }

  factory SyncResult.fail(String message) {
    return SyncResult(ok: false, message: message);
  }
}

/// 云同步服务（星图）
/// 对应后端：/api/state/save, /api/state/load
class SyncService {
  static const String _prodServer = 'http://8.218.177.149:8080';
  static const String _devServer = 'http://localhost:8080';
  static const bool _useDevServer =
      bool.fromEnvironment('USE_DEV_SERVER', defaultValue: false);

  static String? _authToken;

  static String get _baseUrl => _useDevServer ? _devServer : _prodServer;
  static String get _apiUrl => '$_baseUrl/api';

  static void setAuthToken(String? token) {
    _authToken = token;
  }

  static Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final token = _authToken ?? StorageService.getAuthToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// 推送本地状态到云端
  static Future<SyncResult> pushState({
    required String boardData,
    required int score,
    required int novelIndex,
    required int currentNovelId,
  }) async {
    try {
      final uri = Uri.parse('$_apiUrl/state/save');
      final response = await http
          .post(
            uri,
            headers: _headers(),
            body: jsonEncode({
              'board_data': boardData,
              'score': score,
              'novel_index': novelIndex,
              'current_novel_id': currentNovelId,
            }),
          )
          .timeout(const Duration(seconds: 8));

      final Map<String, dynamic> payload = response.body.isNotEmpty
          ? (jsonDecode(response.body) as Map<String, dynamic>)
          : {};

      if (response.statusCode == 200) {
        final message = payload['message']?.toString() ?? '云端同步成功';
        return SyncResult.success(message: message);
      }

      final error = payload['error']?.toString() ?? '云端同步失败';
      return SyncResult.fail(error);
    } catch (e) {
      return SyncResult.fail('云同步异常: $e');
    }
  }

  /// 拉取云端状态
  static Future<SyncResult> pullState() async {
    try {
      final uri = Uri.parse('$_apiUrl/state/load');
      final response = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 8));

      final Map<String, dynamic> payload = response.body.isNotEmpty
          ? (jsonDecode(response.body) as Map<String, dynamic>)
          : {};

      if (response.statusCode == 200) {
        final state = SyncState.fromJson(payload);
        return SyncResult.success(
          message: state.found ? '云端存档已拉取' : '未找到云端存档',
          state: state,
        );
      }

      final error = payload['error']?.toString() ?? '拉取云端存档失败';
      return SyncResult.fail(error);
    } catch (e) {
      return SyncResult.fail('云同步异常: $e');
    }
  }
}

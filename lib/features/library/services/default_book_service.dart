import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:yueyou/core/config/tts_config.dart';
import 'package:yueyou/core/constants/book_constants.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/library/domain/book_model.dart';

/// 内置默认书籍服务（分章懒加载版）
///
/// 职责：纯网络 + 缓存服务。
/// - 目录：本地缓存 → 网络拉取 → 降级内置常量
/// - 章节文本：本地缓存 → POST 获取 CDN URL → GET 下载 → 写本地缓存
///
/// 严禁引入 UI 库，不持有任何 Provider 引用。
class DefaultBookService {
  /// 书籍服务 API 基础地址（通过 TtsConfig.bookApiBase 编译时注入）
  static String get _apiBase => TtsConfig.bookApiBase;

  /// 当前书籍标识
  final String bookKey;

  /// 并发去重：in-flight 章节下载请求缓存，防止同一章节同时发起两次网络请求。
  final Map<int, Completer<String?>> _inFlight = {};

  /// HTTP 客户端：默认走 [http.Client()]（dart:io），测试可注入 [MockClient]。
  final http.Client _httpClient;

  DefaultBookService({
    this.bookKey = BookConstants.defaultBookKey,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  // ── 目录获取：缓存 → 网络 → 内置常量 ───────────────────────────────────

  /// 获取书目（章节标题列表）
  ///
  /// 优先级：本地文件缓存 → GET 网络拉取 → 内置 Dart 常量（离线兜底）
  Future<List<ChapterModel>> getCatalog() async {
    // 1. 本地缓存
    final cached = await StorageService.loadBookCatalog(bookKey);
    if (cached != null && cached.isNotEmpty) {
      return cached.map(ChapterModel.fromJson).toList();
    }

    // 2. 网络拉取
    try {
      final uri = Uri.parse('$_apiBase/book/catalog?bookId=$bookKey');
      final resp = await _httpClient.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(TtsConfig.bookApiTimeout);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (body['status'] == 'success') {
          final chapters =
              (body['chapters'] as List).cast<Map<String, dynamic>>();
          final models = chapters
              .map(
                (e) => ChapterModel(
                  title: e['title'] as String,
                  lineIndex: 0,
                ),
              )
              .toList();
          // 异步写缓存，不阻塞返回
          StorageService.saveBookCatalog(
            bookKey,
            models.map((c) => c.toJson()).toList(),
          ).catchError(
            (Object e, StackTrace stack) => CyberLogger.captureWarning(
              e,
              stack: stack,
              tag: 'library',
              extra: {'context': '默认书籍目录缓存写入失败'},
            ),
          );
          return models;
        }
      }
    } catch (e, stack) {
      CyberLogger.captureWarning(
        e,
        stack: stack,
        tag: 'library',
        extra: {'context': '默认书籍目录拉取失败，降级内置常量'},
      );
    }

    // 3. 降级：内置常量
    return BookConstants.xiyoujiChapterTitles
        .asMap()
        .entries
        .map((e) => ChapterModel(title: e.value, lineIndex: 0))
        .toList();
  }

  // ── 章节文本：本地缓存 → 分离下载（POST→CDN GET）───────────────────────

  /// 下载指定章节纯文本
  ///
  /// - 命中本地缓存直接返回，不发任何网络请求。
  /// - 未命中：POST 获取 CDN URL → GET 下载文本（与 TTS 分离下载完全对齐）。
  /// - 并发防护：同一 [chapterIndex] 的第二次调用复用同一个 [Completer]。
  Future<String?> fetchChapter(int chapterIndex) async {
    // 越界检查
    if (chapterIndex < 0 ||
        chapterIndex >= BookConstants.defaultTotalChapters) {
      return null;
    }

    // 1. 本地缓存命中
    final cached = await StorageService.loadChapterCache(bookKey, chapterIndex);
    if (cached != null) return cached;

    // 2. 并发去重：如果该章节正在下载，等待同一个 Completer
    if (_inFlight.containsKey(chapterIndex)) {
      return _inFlight[chapterIndex]!.future;
    }
    final completer = Completer<String?>();
    _inFlight[chapterIndex] = completer;

    try {
      final text = await _downloadChapter(chapterIndex);
      if (text != null) {
        // 写缓存后触发 LRU 清理（fire-and-forget）
        StorageService.saveChapterCache(bookKey, chapterIndex, text)
            .then(
              (_) => StorageService.pruneChapterCache(
                bookKey,
                chapterIndex,
                keepAround: 3,
              ),
            )
            .catchError(
              (Object e, StackTrace stack) => CyberLogger.captureWarning(
                e,
                stack: stack,
                tag: 'library',
                extra: {'context': '默认书籍章节缓存写入失败'},
              ),
            );
      }
      completer.complete(text);
      return text;
    } catch (e, stack) {
      CyberLogger.captureWarning(
        e,
        stack: stack,
        tag: 'library',
        extra: {
          'context': '默认书籍章节下载失败',
          'chapterIndex': chapterIndex.toString(),
        },
      );
      completer.complete(null);
      return null;
    } finally {
      _inFlight.remove(chapterIndex);
    }
  }

  /// 影子预读：fire-and-forget，不阻塞调用方。
  void prefetchNextChapter(int currentChapterIndex) {
    final next = currentChapterIndex + 1;
    if (next >= BookConstants.defaultTotalChapters) return;
    fetchChapter(next).then(
      (_) {},
      onError: (Object e, StackTrace stack) => CyberLogger.captureWarning(
        e,
        stack: stack,
        tag: 'library',
        extra: {
          'context': '默认书籍影子预读失败',
          'chapterIndex': next.toString(),
        },
      ),
    );
  }

  /// 检查某章是否已有本地缓存（无需网络）。
  Future<bool> isChapterCached(int chapterIndex) async {
    final text = await StorageService.loadChapterCache(bookKey, chapterIndex);
    return text != null;
  }

  // ── 内部：分离下载实现 ─────────────────────────────────────────────────

  /// 遵循分离下载原则：POST 获取 CDN URL → GET 下载纯文本。
  Future<String?> _downloadChapter(int chapterIndex) async {
    // 步骤一：POST 获取 CDN URL
    final postUri = Uri.parse('$_apiBase/book/chapter');
    final postResp = await _httpClient
        .post(
          postUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'bookId': bookKey, 'chapterIndex': chapterIndex}),
        )
        .timeout(
          TtsConfig.bookApiTimeout,
        );

    if (postResp.statusCode != 200) {
      CyberLogger.captureWarning(
        StateError('默认书籍章节 POST 请求失败'),
        tag: 'library',
        extra: {
          'context': 'POST /book/chapter',
          'statusCode': postResp.statusCode.toString(),
        },
      );
      return null;
    }

    final postBody = jsonDecode(postResp.body) as Map<String, dynamic>;
    if (postBody['status'] != 'success') {
      CyberLogger.captureWarning(
        StateError('默认书籍章节服务端返回错误'),
        tag: 'library',
        extra: {
          'context': '解析章节 POST 响应',
          'message': postBody['message']?.toString() ?? '',
        },
      );
      return null;
    }

    final cdnUrl = postBody['url'] as String?;
    if (cdnUrl == null || cdnUrl.isEmpty) return null;

    // 步骤二：GET 从 CDN 下载章节纯文本
    final getResp = await _httpClient
        .get(Uri.parse(cdnUrl))
        .timeout(TtsConfig.bookCdnDownloadTimeout);

    if (getResp.statusCode != 200) {
      CyberLogger.captureWarning(
        StateError('默认书籍章节 CDN GET 失败'),
        tag: 'library',
        extra: {
          'context': 'GET 章节纯文本',
          'statusCode': getResp.statusCode.toString(),
        },
      );
      return null;
    }

    // 强制 UTF-8 解码，避免 http.body 按 Latin-1 解析中文导致 sentences=0
    return utf8.decode(getResp.bodyBytes, allowMalformed: true);
  }
}

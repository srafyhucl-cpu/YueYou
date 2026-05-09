import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// 进程内目录缓存（P3 优化）。
  ///
  /// 在网络成功或本地磁盘命中后填充，规避「磁盘写入失败但同会话仍需复用」的
  /// 重复网络拉取。**降级到内置常量时不写入**，以保留下次重试网络的机会。
  List<ChapterModel>? _catalogMemCache;

  /// 进程内章节正文缓存（P3 优化）。
  ///
  /// 同上：磁盘 fire-and-forget 写入失败时确保同一会话再次请求该章无需走网络。
  /// 章节总数上限 100，全量驻留约几百 KB，可接受。
  final Map<int, String> _chapterMemCache = {};

  DefaultBookService({
    this.bookKey = BookConstants.defaultBookKey,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// 测试钩子：清空进程内缓存。
  @visibleForTesting
  void clearMemoryCacheForTesting() {
    _catalogMemCache = null;
    _chapterMemCache.clear();
  }

  // ── 目录获取：缓存 → 网络 → 内置常量 ───────────────────────────────────

  /// 获取书目（章节标题列表）
  ///
  /// 优先级：进程内内存缓存 → 本地文件缓存 → GET 网络拉取 → 内置 Dart 常量
  Future<List<ChapterModel>> getCatalog() async {
    // 0. 进程内缓存（P3 优化：规避磁盘写入失败导致同会话重复网络拉取）
    if (_catalogMemCache != null && _catalogMemCache!.isNotEmpty) {
      return _catalogMemCache!;
    }

    // 1. 本地缓存
    final cached = await StorageService.loadBookCatalog(bookKey);
    if (cached != null && cached.isNotEmpty) {
      final models = cached.map(ChapterModel.fromJson).toList();
      _catalogMemCache = models;
      return models;
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
          // P3 修复：显式校验 `chapters` 字段，缺失时记录协议错误并降级，
          // 避免 `(null as List)` 抛出 `_TypeError` 被外层 catch 误判为网络异常。
          final rawChapters = body['chapters'];
          if (rawChapters is! List) {
            CyberLogger.captureWarning(
              StateError('默认书籍目录协议字段缺失 chapters'),
              tag: 'library',
              extra: {
                'context': '协议字段缺失 chapters',
                'bodyType': rawChapters.runtimeType.toString(),
              },
            );
            return _fallbackBuiltinCatalog();
          }
          final chapters = rawChapters.cast<Map<String, dynamic>>();
          final models = chapters
              .map(
                (e) => ChapterModel(
                  title: e['title'] as String,
                  lineIndex: 0,
                ),
              )
              .toList();
          // P3 优化：先写内存缓存，确保即使磁盘写入失败本会话也能复用
          _catalogMemCache = models;
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
    return _fallbackBuiltinCatalog();
  }

  /// 降级兜底：返回内置西游记章节标题列表。
  ///
  /// 抽出为独立辅助以便网络成功但协议字段缺失时也能复用同一份降级逻辑。
  List<ChapterModel> _fallbackBuiltinCatalog() {
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

    // 0. 进程内缓存命中（P3 优化）
    final memCached = _chapterMemCache[chapterIndex];
    if (memCached != null) return memCached;

    // 1. 本地缓存命中
    final cached = await StorageService.loadChapterCache(bookKey, chapterIndex);
    if (cached != null) {
      _chapterMemCache[chapterIndex] = cached;
      return cached;
    }

    // 2. 并发去重：如果该章节正在下载，等待同一个 Completer
    if (_inFlight.containsKey(chapterIndex)) {
      return _inFlight[chapterIndex]!.future;
    }
    final completer = Completer<String?>();
    _inFlight[chapterIndex] = completer;

    try {
      final text = await _downloadChapter(chapterIndex);
      if (text != null) {
        // P3 优化：先写内存缓存，确保磁盘写入失败时同会话仍可复用
        _chapterMemCache[chapterIndex] = text;
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

  /// 检查某章是否已有缓存（无需网络）。同时覆盖进程内缓存与本地磁盘缓存。
  ///
  /// **副作用警告**：返回 `true` **不代表磁盘上已持久化**。
  /// - 进程内 `_chapterMemCache` 命中也会返回 `true`，但**重启 App 后失效**。
  /// - 若调用方需要"是否磁盘持久化"语义（如冷启动预读决策），请直接调用
  ///   [StorageService.loadChapterCache] 而非本方法。
  Future<bool> isChapterCached(int chapterIndex) async {
    if (_chapterMemCache.containsKey(chapterIndex)) return true;
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

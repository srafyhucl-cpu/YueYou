// Reader 句子游标算法。
//
// 从 `reader_provider.dart` 抽出（PR-E）。本文件属 domain 层：
// - 暴露顶层纯函数与简单结果对象，零状态、零副作用；
// - 不依赖 Flutter / Riverpod / Storage 等 IO 设施；
// - 输入纯文本数组、当前 fetchIndex、章节标题，输出下一段可朗读请求与
//   推进后的 fetchIndex。
//
// 单元测试可独立喂任意 sentences/edge case 而不需构造 ReaderProvider。

import 'package:yueyou/core/utils/text_processing.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';

/// 一次取句的结果：`request` 为 null 表示已耗尽。
class SentenceFetchResult {
  final TtsAudioRequest? request;
  final int nextFetchIndex;

  const SentenceFetchResult(this.request, this.nextFetchIndex);
}

/// 从 [sentences] 的 [fetchIndex] 起向后扫描，跳过噪音/空行，遇到章节
/// 标题则清洗，必要时向后合并短句直到达到 TTS 最低 5 字符要求。
///
/// 返回新构造的 [TtsAudioRequest] 与推进后的 fetchIndex。若扫描到末尾
/// 仍无可朗读内容，则 `request` 为 null、`nextFetchIndex` 等于
/// `sentences.length`，调用方应据此终止预取。
///
/// 该函数严格 1:1 复刻 `ReaderProvider.nextTtsSentence` 中的合并算法：
/// 取消取模回卷、合并不跨章、章节标题清洗后过滤空串。
SentenceFetchResult fetchNextSentenceRequest({
  required List<String> sentences,
  required int fetchIndex,
  required String chapterTitle,
}) {
  if (sentences.isEmpty) {
    return const SentenceFetchResult(null, 0);
  }
  if (fetchIndex >= sentences.length) {
    return SentenceFetchResult(null, sentences.length);
  }

  int cursor = fetchIndex;

  // P0-5：彻底取消 `(cursor + 1) % sentences.length` 取模回卷。
  // 章末若干噪音行会让旧实现把游标绕回章首，触发 TTS "鬼畜重读章首"，
  // 与默认书的"章末自动推进下一章"逻辑直接互斥。
  // 统一在到达 sentences.length 时把 fetchIndex 推进到末尾并返回 null。
  while (cursor < sentences.length) {
    final int lineIndex = cursor;
    String text = sentences[lineIndex].trim();

    // 跳过噪音词和空行（始终不读）
    if (TextProcessing.isNoiseLine(text)) {
      cursor++;
      continue;
    }

    // 章节标题 → 清洗后朗读
    if (TextProcessing.isChapterTitle(text)) {
      text = TextProcessing.cleanChapterTitle(text);
      if (text.isEmpty) {
        cursor++;
        continue;
      }
    }

    // TTS API 要求至少 5 字符，向后合并短句
    int consumed = cursor + 1; // consumed 指向「下一个未消耗行」
    int endLine = lineIndex; // 合并消耗到的最后一行（含）
    while (text.length < 5 && consumed < sentences.length) {
      final mergeIdx = consumed;
      final nextText = sentences[mergeIdx].trim();
      consumed++;
      if (TextProcessing.isNoiseLine(nextText)) continue;
      // 合并时遇到下一个章节标题则停止，不跨章合并
      if (TextProcessing.isChapterTitle(nextText)) break;
      text = text + nextText;
      endLine = mergeIdx;
      if (text.length >= 5) break;
    }

    // 合并后仍然太短 → 跳过整段，cursor 直接前移到 consumed（不取模）
    if (text.length < 5) {
      cursor = consumed;
      continue;
    }

    // 立即推进 fetchIndex 到所有已消耗行之后，杜绝重复
    final int newFetchIndex =
        consumed >= sentences.length ? sentences.length : consumed;

    return SentenceFetchResult(
      TtsAudioRequest(
        lineIndex: lineIndex,
        endLineIndex: endLine,
        text: text,
        title: chapterTitle,
      ),
      newFetchIndex,
    );
  }

  // 扫到末尾仍未找到可读内容：标记已耗尽，避免下次重复扫描。
  return SentenceFetchResult(null, sentences.length);
}

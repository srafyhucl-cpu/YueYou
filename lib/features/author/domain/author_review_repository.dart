import 'author_review_session.dart';

/// 作者听校会话的本地持久化边界。
abstract interface class AuthorReviewRepository {
  /// 读取指定书籍的会话；不存在或无法恢复时返回 null。
  Future<AuthorReviewSession?> load(String bookId);

  /// 保存指定书籍的完整会话。
  Future<void> save(AuthorReviewSession session);

  /// 删除指定书籍的听校会话及其本地备份。
  Future<void> delete(String bookId);
}

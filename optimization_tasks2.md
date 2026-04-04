# 任务描述
请修改 lib/features/audio/services/tts_engine_service.dart 文件，解决因为音频文件下载和 I/O 读写导致的 Flutter 主线程阻塞（UI 卡死）问题。

# 具体修改要求

1. **引入依赖**：请确保在文件顶部引入了 Isolate 核心库：
   import 'dart:isolate'; 

2. **定位目标方法**：找到 _RealHttpClient 类中的 download(Uri url, String savePath) 方法，并**完全重写**它。

3. **使用后台线程 (Isolate)**：要求使用 Dart 3 的 Isolate.run 将“网络下载”和“磁盘写入”操作移入后台线程执行，彻底释放 UI 线程。

4. **Isolate 内部逻辑规范**：
   - 因为 Dio 实例无法跨 Isolate 传递，必须在 Isolate.run 的回调内部创建一个**全新的 Dio 实例**。
   - 为防止底层 Socket 假死，请通过 BaseOptions 为这个局部 Dio 设置超时参数：connectTimeout 为 5 秒，receiveTimeout 为 10 秒。
   - 在 Isolate 内部执行 download 操作，完成后返回 response.statusCode。
   - 如果 Isolate 内部发生异常（如网络异常、I/O 异常），请捕获它并返回 500 状态码。最后在 finally 块中调用 dio.close() 清理资源。

5. **主线程回调处理**：
   - 主线程等待 Isolate.run 返回状态码。
   - 如果状态码 >= 400，请在主线程中抛出异常：throw HttpException('下载音频失败: HTTP $statusCode');。

请直接输出修改后的 _RealHttpClient 的完整代码。
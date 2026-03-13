/**
 * 阅游应用 - 全局配置文件
 *
 * ⚠️ 注意：此文件管理所有后端地址和环境配置。
 *          切换服务器地址时只需修改这一个文件，禁止在业务代码中硬编码 URL。
 *
 * 使用方式：在 index.html 中最先引入此文件（必须在 main.js 之前）
 *   <script src="config.js"></script>
 */

const AppConfig = (() => {
  // ─────────────────────────────────────────
  // 环境判断：
  //   - capacitor:// → APK 内嵌模式（生产）
  //   - localhost     → 本地开发模式（调试）
  // ─────────────────────────────────────────
  const isNative = window.location.protocol === "capacitor:";
  const isLocalDev =
    window.location.hostname === "localhost" ||
    window.location.hostname === "127.0.0.1";

  // ─────────────────────────────────────────
  // 后端服务器地址（切换环境时只修改这里）
  // ─────────────────────────────────────────
  const PROD_SERVER = "http://8.218.177.149:3000"; // 生产服务器
  const DEV_SERVER  = "http://localhost:3000";      // 本地开发服务器

  const BASE_URL = isNative || !isLocalDev ? PROD_SERVER : DEV_SERVER;

  return {
    // 基础地址
    baseURL: BASE_URL,

    // TTS 语音合成接口
    ttsURL: `${BASE_URL}/api/v1/tts/createStream`,

    // 游戏后端 API 前缀
    apiURL: `${BASE_URL}/api`,

    // 当前运行环境
    isNative,
    isLocalDev,
    env: isNative ? "native" : isLocalDev ? "development" : "production",
  };
})();

// 开发模式下在控制台打印当前配置，方便调试
if (AppConfig.isLocalDev) {
  console.log("[AppConfig] 当前配置：", AppConfig);
}

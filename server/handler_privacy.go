package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

const privacyPolicyHTML = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>阅游隐私政策</title>
  <style>
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.8; color: #e5faff; background: #080912; }
    main { max-width: 880px; margin: 0 auto; padding: 32px 18px 64px; }
    h1, h2 { color: #22d3ee; }
    h1 { border-bottom: 1px solid rgba(34,211,238,.35); padding-bottom: 12px; }
    section { margin-top: 28px; padding: 18px; border: 1px solid rgba(34,211,238,.18); border-radius: 14px; background: rgba(255,255,255,.035); }
    a { color: #67e8f9; }
    .muted { color: rgba(229,250,255,.72); }
  </style>
</head>
<body>
<main>
  <h1>阅游隐私政策</h1>
  <p class="muted">更新日期：2026年7月12日｜生效日期：2026年7月12日</p>

  <section>
    <h2>一、开发者信息</h2>
    <p>开发者/运营主体：胡传龙</p>
    <p>联系邮箱：<a href="mailto:hucloong@163.com">hucloong@163.com</a></p>
  </section>

  <section>
    <h2>二、我们如何收集和使用信息</h2>
    <p>阅游是一款本地小说阅读、听读与 2048 益智游戏应用。我们不会收集通讯录、短信、通话记录、定位、相机、麦克风等敏感个人信息。</p>
    <p>当您使用云端 TTS 朗读功能时，应用会将当前需要朗读的文本片段发送至 TTS 服务，仅用于生成本次朗读音频。除当前朗读文本外，我们不会上传您的书架、阅读进度、游戏存档或个人设置。</p>
    <p>服务端日志不会记录朗读原文，仅记录不可逆请求 ID、字符数、音色、耗时、状态码和错误分类等排障所需信息。</p>
  </section>

  <section>
    <h2>三、本地数据存储</h2>
    <p>阅读进度、书架、设置、游戏存档和 TTS 缓存文件仅保存在您的设备本地。您可以通过卸载应用或清除应用数据删除这些本地数据。</p>
    <p>云端 TTS 生成的临时音频保存于对象存储私有路径，应用仅获取短效签名下载链接；链接有效期不超过 10 分钟，临时音频按服务端生命周期策略自动清理，目标保留时间不超过 24 小时。</p>
  </section>

  <section>
    <h2>四、文件访问说明</h2>
    <p>导入 TXT 小说时，阅游通过 Android 系统文件选择器访问您主动选择的文件。应用不会扫描您的其他目录，也不会在未经您选择的情况下读取其他文件。</p>
  </section>

  <section>
    <h2>五、第三方服务</h2>
    <p>阅游可能使用云端 TTS 服务、对象存储/CDN 服务提供音频合成、默认书籍目录与章节下载能力。这些服务仅用于实现应用功能，不用于个人画像或广告追踪。</p>
    <p>对象存储中的 TTS 音频对象使用服务端密钥生成的不可逆对象键，避免通过文件名反推出朗读文本。</p>
  </section>

  <section>
    <h2>六、权限使用说明</h2>
    <p>网络权限用于访问 TTS 与书籍服务。文件导入通过系统文件选择器完成授权，不申请读取全部存储空间权限。</p>
  </section>

  <section>
    <h2>七、未成年人保护</h2>
    <p>阅游不面向低龄儿童提供定向服务。如未成年人使用本应用，应在监护人指导下使用。</p>
  </section>

  <section>
    <h2>八、您的权利</h2>
    <p>如您需要咨询隐私问题、反馈问题或请求删除相关数据，可通过邮箱 <a href="mailto:hucloong@163.com">hucloong@163.com</a> 与我们联系。由于主要数据保存在本地设备，您也可以通过清除应用数据或卸载应用自行删除。</p>
  </section>

  <section>
    <h2>九、政策更新</h2>
    <p>我们可能根据功能变化更新本隐私政策。更新后将通过页面日期或应用内提示展示。</p>
  </section>
</main>
</body>
</html>`

// privacyHandler 返回阅游隐私政策静态页面。
func privacyHandler(c *gin.Context) {
	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(privacyPolicyHTML))
}

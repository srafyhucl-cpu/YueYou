package main

import (
	"os"
	"strconv"
	"time"
)

// Config 持有所有运行时配置，优先从环境变量读取，回退到内置默认值。
// 生产部署：通过 systemd EnvironmentFile 或 Docker --env-file 注入。
type Config struct {
	AKID        string // 阿里云 AccessKey ID。
	AKSecret    string // 阿里云 AccessKey Secret。
	OSSEndpoint string // OSS 上传端点，生产建议使用内网端点省流量。
	OSSSignEP   string // OSS 签名下载端点，必须是客户端可访问的公网端点。
	OSSBucket   string // OSS Bucket 名称。
	OSSPub      string // 默认书籍 OSS / CDN 公网访问前缀（无尾斜线）。

	TTSObjectKeySecret string        // TTS 临时对象键 HMAC 密钥。
	TTSSignedURLTTL    time.Duration // TTS 签名下载 URL 有效期。
	TTSMaxBodyBytes    int64         // TTS 请求体字节上限。
	TTSIPLimitPerMin   int           // 单 IP 每分钟请求上限。
	TTSIDLimitPerHour  int           // 单安装 ID 每小时请求上限。
}

// cfg 为全局单例配置，在 main() 启动前由 init() 初始化。
var cfg Config

func init() {
	cfg = Config{
		AKID:        getenv("YUEYOU_AKID", ""),
		AKSecret:    getenv("YUEYOU_AKSEC", ""),
		OSSEndpoint: getenv("YUEYOU_OSS_EP", "oss-cn-beijing-internal.aliyuncs.com"),
		OSSSignEP:   getenv("YUEYOU_OSS_SIGN_EP", "oss-cn-beijing.aliyuncs.com"),
		OSSBucket:   getenv("YUEYOU_OSS_BKT", "general-storage"),
		OSSPub:      getenv("YUEYOU_OSS_PUB", "https://general-storage.oss-cn-beijing.aliyuncs.com"),

		TTSObjectKeySecret: getenv("YUEYOU_TTS_OBJECT_SECRET", getenv("YUEYOU_AKSEC", "local-dev-only")),
		TTSSignedURLTTL:    time.Duration(getenvInt("YUEYOU_TTS_SIGNED_URL_TTL_SECONDS", 600)) * time.Second,
		TTSMaxBodyBytes:    int64(getenvInt("YUEYOU_TTS_MAX_BODY_BYTES", 16*1024)),
		TTSIPLimitPerMin:   getenvInt("YUEYOU_TTS_IP_LIMIT_PER_MIN", 30),
		TTSIDLimitPerHour:  getenvInt("YUEYOU_TTS_ID_LIMIT_PER_HOUR", 120),
	}
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getenvInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil || n <= 0 {
		return fallback
	}
	return n
}

package main

import "os"

// Config 持有所有运行时配置，优先从环境变量读取，回退到内置默认值。
// 生产部署：通过 systemd EnvironmentFile 或 Docker --env-file 注入。
type Config struct {
	AKID        string // 阿里云 AccessKey ID
	AKSecret    string // 阿里云 AccessKey Secret
	OSSEndpoint string // OSS 内网端点（服务器与 OSS 同 region 时用内网省流量）
	OSSBucket   string // OSS Bucket 名称
	OSSPub      string // OSS / CDN 公网访问前缀（无尾斜线）
}

// cfg 为全局单例配置，在 main() 启动前由 init() 初始化。
var cfg Config

func init() {
	cfg = Config{
		AKID:        getenv("YUEYOU_AKID", ""),
		AKSecret:    getenv("YUEYOU_AKSEC", ""),
		OSSEndpoint: getenv("YUEYOU_OSS_EP", "oss-cn-beijing-internal.aliyuncs.com"),
		OSSBucket:   getenv("YUEYOU_OSS_BKT", "general-storage"),
		OSSPub:      getenv("YUEYOU_OSS_PUB", "https://general-storage.oss-cn-beijing.aliyuncs.com"),
	}
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

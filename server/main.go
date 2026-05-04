package main

import (
	"log"

	"github.com/gin-gonic/gin"
)

func main() {
	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()
	if err := r.SetTrustedProxies(nil); err != nil {
		log.Fatal(err)
	}

	// ── TTS 语音合成 ──────────────────────────────────────────────────────
	r.POST("/api/v1/tts", ttsHandler)

	// ── 书籍服务 ──────────────────────────────────────────────────────────
	r.GET("/api/v1/book/catalog", bookCatalogHandler)
	r.POST("/api/v1/book/chapter", bookChapterHandler)

	// ── 合规页面 ──────────────────────────────────────────────────────────
	r.GET("/privacy", privacyHandler)

	log.Println("yueyou-server on :8081")
	r.Run(":8081")
}

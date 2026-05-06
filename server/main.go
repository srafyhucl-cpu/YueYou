package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
)

func main() {
	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()
	if err := r.SetTrustedProxies(nil); err != nil {
		log.Fatal(err)
	}

	if err := initOssBucket(); err != nil {
		log.Fatalf("OSS 初始化失败: %v", err)
	}

	// ── TTS 语音合成 ──────────────────────────────────────────────────────
	r.POST("/api/v1/tts", ttsHandler)

	// ── 书籍服务 ──────────────────────────────────────────────────────────
	r.GET("/api/v1/book/catalog", bookCatalogHandler)
	r.POST("/api/v1/book/chapter", bookChapterHandler)

	// ── 合规页面 ──────────────────────────────────────────────────────────
	r.GET("/privacy", privacyHandler)
	r.GET("/ping", func(c *gin.Context) { c.String(200, "pong") })

	srv := &http.Server{
		Addr:         ":8081",
		Handler:      r,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Println("yueyou-server on :8081")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("服务启动失败: %v", err)
		}
	}()

	// 优雅关闭：SIGINT / SIGTERM 时等待进行中的请求完成
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("正在关闭服务...")

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("服务关闭异常: %v", err)
	}
	log.Println("服务已退出")
}

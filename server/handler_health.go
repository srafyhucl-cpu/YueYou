package main

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// healthHandler 只表示进程存活，不探测外部依赖。
func healthHandler(c *gin.Context) {
	ok(c, gin.H{"status": "ok"})
}

// readyHandler 表示 TTS 所需 OSS 依赖可用。
func readyHandler(c *gin.Context) {
	if ttsStore == nil {
		fail(c, http.StatusServiceUnavailable, "OSS 未初始化")
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
	defer cancel()
	if err := ttsStore.Ready(ctx); err != nil {
		fail(c, http.StatusServiceUnavailable, "依赖未就绪")
		return
	}
	if err := edgeTTSReady(); err != nil {
		fail(c, http.StatusServiceUnavailable, "TTS 执行器未就绪")
		return
	}
	ok(c, gin.H{"status": "ready"})
}

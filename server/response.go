package main

import "github.com/gin-gonic/gin"

// ok 返回成功响应（HTTP 200）。
func ok(c *gin.Context, data gin.H) {
	c.JSON(200, data)
}

// fail 返回错误响应，统一 status/error/message 格式。
func fail(c *gin.Context, code int, msg string) {
	c.JSON(code, gin.H{"status": "error", "message": msg})
}

package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// ErrorResponse 统一的错误响应格式
func ErrorResponse(c *gin.Context, httpStatus int, message string) {
	c.JSON(httpStatus, gin.H{"error": message})
}

// SuccessResponse 统一的成功响应（带数据）
func SuccessResponse(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, data)
}

// SuccessMessage 统一的成功响应（无数据，仅提示）
func SuccessMessage(c *gin.Context, message string) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "ok",
		"message": message,
	})
}

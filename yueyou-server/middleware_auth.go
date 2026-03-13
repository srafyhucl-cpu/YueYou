package main

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// ======================================
// JWT 鉴权中间件 (middleware_auth.go)
// 职责：校验请求头中的 Bearer Token，
//       将解析出的 user_id 注入到请求上下文
// ======================================

// jwtSecret JWT 签名密钥
// ⚠️ 生产环境应从环境变量或配置文件读取，禁止硬编码
var jwtSecret = []byte("2048-infinite-loop-secret-key")

// AuthMiddleware JWT 鉴权中间件
func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "缺少或无效的 Token"})
			c.Abort()
			return
		}

		tokenString := strings.TrimPrefix(authHeader, "Bearer ")
		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return jwtSecret, nil
		})

		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Token 无效或已过期"})
			c.Abort()
			return
		}

		if claims, ok := token.Claims.(jwt.MapClaims); ok && token.Valid {
			userID := int64(claims["user_id"].(float64))
			c.Set("user_id", userID)
			c.Next()
		} else {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Token 解析失败"})
			c.Abort()
		}
	}
}

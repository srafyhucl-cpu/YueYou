package main

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

// ======================================
// 认证 Handler (handlers_auth.go)
// 职责：处理用户注册与登录，签发 JWT
// ======================================

// AuthRequest 注册/登录请求体
type AuthRequest struct {
	Phone    string `json:"phone" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// HandleRegister 手机号 + 密码注册，注册成功后自动签发 JWT
func HandleRegister(c *gin.Context) {
	var req AuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		ErrorResponse(c, http.StatusBadRequest, "请求字段不完整")
		return
	}

	phone := strings.TrimSpace(req.Phone)
	if len(phone) < 11 {
		ErrorResponse(c, http.StatusBadRequest, "手机号格式不正确")
		return
	}
	if len(req.Password) < 6 {
		ErrorResponse(c, http.StatusBadRequest, "密码长度至少 6 位")
		return
	}

	// 查重
	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM users WHERE phone = ?", phone).Scan(&count); err != nil {
		ErrorResponse(c, http.StatusInternalServerError, "数据库错误")
		return
	}
	if count > 0 {
		ErrorResponse(c, http.StatusConflict, "手机号已被注册")
		return
	}

	// Bcrypt 哈希密码
	hashedBytes, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		ErrorResponse(c, http.StatusInternalServerError, "密码加密失败")
		return
	}

	res, err := db.Exec("INSERT INTO users (phone, password_hash) VALUES (?, ?)", phone, string(hashedBytes))
	if err != nil {
		ErrorResponse(c, http.StatusInternalServerError, "创建用户失败")
		return
	}

	userID, _ := res.LastInsertId()

	// 注册成功后自动签发 JWT，免去二次登录
	tokenString, err := signJWT(userID)
	if err != nil {
		ErrorResponse(c, http.StatusInternalServerError, "Token 签发失败")
		return
	}

	SuccessResponse(c, gin.H{
		"token":   tokenString,
		"user_id": userID,
	})
}

// HandleLogin 手机号 + 密码登录
func HandleLogin(c *gin.Context) {
	var req AuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		ErrorResponse(c, http.StatusBadRequest, "请求字段不完整")
		return
	}

	phone := strings.TrimSpace(req.Phone)

	var userID int64
	var hash string
	err := db.QueryRow("SELECT id, password_hash FROM users WHERE phone = ?", phone).Scan(&userID, &hash)
	if err != nil {
		ErrorResponse(c, http.StatusUnauthorized, "用户不存在或手机号错误")
		return
	}

	if hash == "" {
		ErrorResponse(c, http.StatusUnauthorized, "账号异常，请重新注册")
		return
	}

	// Bcrypt 校验密码
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(req.Password)); err != nil {
		ErrorResponse(c, http.StatusUnauthorized, "密码错误")
		return
	}

	tokenString, err := signJWT(userID)
	if err != nil {
		ErrorResponse(c, http.StatusInternalServerError, "Token 签发失败")
		return
	}

	SuccessResponse(c, gin.H{
		"token":   tokenString,
		"user_id": userID,
	})
}

// signJWT 内部工具：生成有效期 7 天的 JWT
func signJWT(userID int64) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"user_id": userID,
		"exp":     time.Now().Add(time.Hour * 24 * 7).Unix(),
	})
	return token.SignedString(jwtSecret)
}

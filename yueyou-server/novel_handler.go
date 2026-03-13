package main

import (
	"database/sql"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

var validTextRegexp = regexp.MustCompile(`[\p{L}\p{N}\p{Han}]`) // 匹配必须包含字母、数字或汉字

// ========= Public Library API =========

// NovelInfo 小说列表简要信息
type NovelInfo struct {
	ID              int    `json:"id"`
	Title           string `json:"title"`
	UploaderID      int    `json:"uploader_id"`
	TotalParagraphs int    `json:"total_paragraphs"`
	HistoryIndex    int    `json:"history_index"`
	Uploader        string `json:"uploader"` // 脱敏后的手机号
	CreatedAt       string `json:"created_at"`
}

// GetNovels 获取全站共享的公共书库
func GetNovels(c *gin.Context) {
	var userID int64 = 0
	authHeader := c.GetHeader("Authorization")
	if authHeader != "" && strings.HasPrefix(authHeader, "Bearer ") {
		tokenString := strings.TrimPrefix(authHeader, "Bearer ")
		token, _ := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
			return jwtSecret, nil
		})
		if token != nil && token.Valid {
			if claims, ok := token.Claims.(jwt.MapClaims); ok && claims["user_id"] != nil {
				if uid, ok := claims["user_id"].(float64); ok {
					userID = int64(uid)
				}
			}
		}
	}

	// 联合查询
	rows, err := db.Query(`
		SELECT n.id, n.title, n.uploader_id, n.total_paragraphs, n.created_at, u.phone, COALESCE(p.paragraph_index, 0)
		FROM novels n
		LEFT JOIN users u ON n.uploader_id = u.id
		LEFT JOIN novel_progress p ON n.id = p.novel_id AND p.user_id = ?
		ORDER BY n.id DESC
	`, userID)
	if err != nil {
		log.Printf("[ERROR] Failed to query novels: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch novels: " + err.Error()})
		return
	}
	defer rows.Close()

	var novels []NovelInfo
	for rows.Next() {
		var n NovelInfo
		var phone sql.NullString
		if err := rows.Scan(&n.ID, &n.Title, &n.UploaderID, &n.TotalParagraphs, &n.CreatedAt, &phone, &n.HistoryIndex); err != nil {
			continue
		}

		// 脱敏处理
		if phone.Valid && len(phone.String) >= 11 {
			n.Uploader = phone.String[:3] + "****" + phone.String[7:]
		} else if phone.Valid {
			n.Uploader = phone.String
		} else {
			n.Uploader = "System"
		}

		novels = append(novels, n)
	}

	c.JSON(http.StatusOK, novels)
}

// Paragraph 格式，与前端要求相匹配
type Paragraph struct {
	V string `json:"v"` // voice
	T string `json:"t"` // text
}

// UploadNovel 上传 TXT 并防御查重
func UploadNovel(c *gin.Context) {
	userID := int(c.GetInt64("user_id"))

	title := strings.TrimSpace(c.PostForm("title"))
	if title == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "小说标题不能为空"})
		return
	}

	// 1. 查重防御 - 全局共享书库名不得重复
	var existingID int
	err := db.QueryRow("SELECT id FROM novels WHERE title = ?", title).Scan(&existingID)
	if err != sql.ErrNoRows {
		if err == nil {
			c.JSON(http.StatusConflict, gin.H{"error": "书库中已有该小说，请直接在书架中选择"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	// 2. 接收 TXT 文件
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "文件上传失败或未选择文件"})
		return
	}

	f, err := file.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "无法读取文件"})
		return
	}
	defer f.Close()

	contentBytes, err := io.ReadAll(f)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "无法读取文件内容"})
		return
	}

	// 3. 简单清洗和按段落分割为 JSON
	text := string(contentBytes)
	text = strings.ReplaceAll(text, "\r\n", "\n")
	rawParagraphs := strings.Split(text, "\n")

	var paragraphs []Paragraph
	for _, p := range rawParagraphs {
		cleanP := strings.TrimSpace(p)
		if len(cleanP) > 0 {
			// 如果至少包含一个有效汉字或英数（过滤掉诸如 "---", "***" 或者全是标点的无意义段落）
			if validTextRegexp.MatchString(cleanP) {
				paragraphs = append(paragraphs, Paragraph{
					V: "zh-CN-YunyangNeural",
					T: cleanP,
				})
			}
		}
	}

	if len(paragraphs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "文本内容为空或无法识别有效段落"})
		return
	}

	jsonBytes, _ := json.Marshal(paragraphs)

	// 4. 插入公共书库
	_, err = db.Exec("INSERT INTO novels (title, content_json, total_paragraphs, uploader_id) VALUES (?, ?, ?, ?)", title, string(jsonBytes), len(paragraphs), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "保存小说到书库失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok", "message": "上传成功并进入公共图书馆"})
}

// GetNovelContent 获取指定小说的内容
func GetNovelContent(c *gin.Context) {
	novelID := c.Param("id")

	var contentJson string
	err := db.QueryRow("SELECT content_json FROM novels WHERE id = ?", novelID).Scan(&contentJson)
	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "novel not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}

	c.Data(http.StatusOK, "application/json", []byte(contentJson))
}

package handlers

import (
	"database/sql"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"regexp"
	"strings"

	"2048-go/models"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

var validTextRegexp = regexp.MustCompile(`[\p{L}\p{N}\p{Han}]`)

// NovelInfo 小说列表简要信息
type NovelInfo struct {
	ID              int    `json:"id"`
	Title           string `json:"title"`
	UploaderID      int    `json:"uploader_id"`
	TotalParagraphs int    `json:"total_paragraphs"`
	HistoryIndex    int    `json:"history_index"`
	Uploader        string `json:"uploader"`
	CreatedAt       string `json:"created_at"`
}

// GetNovels 获取全站共享的公共书库
func GetNovels(c *gin.Context) {
	var userID int64 = 0
	authHeader := c.GetHeader("Authorization")
	if authHeader != "" && strings.HasPrefix(authHeader, "Bearer ") {
		tokenString := strings.TrimPrefix(authHeader, "Bearer ")
		token, _ := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
			return JwtSecret, nil
		})
		if token != nil && token.Valid {
			if claims, ok := token.Claims.(jwt.MapClaims); ok && claims["user_id"] != nil {
				if uid, ok := claims["user_id"].(float64); ok {
					userID = int64(uid)
				}
			}
		}
	}

	rows, err := models.DB.Query(`
		SELECT n.id, n.title, n.uploader_id, n.total_paragraphs, n.created_at, u.phone, COALESCE(p.paragraph_index, 0)
		FROM novels n
		LEFT JOIN users u ON n.uploader_id = u.id
		LEFT JOIN novel_progress p ON n.id = p.novel_id AND p.user_id = ?
		ORDER BY n.id DESC
	`, userID)
	if err != nil {
		log.Printf("[ERROR] Failed to query novels: %v", err)
		ErrorResponse(c, http.StatusInternalServerError, "获取书库失败: "+err.Error())
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

		if phone.Valid && len(phone.String) >= 11 {
			n.Uploader = phone.String[:3] + "****" + phone.String[7:]
		} else if phone.Valid {
			n.Uploader = phone.String
		} else {
			n.Uploader = "System"
		}
		novels = append(novels, n)
	}
	SuccessResponse(c, novels)
}

// Paragraph 格式
type Paragraph struct {
	V string `json:"v"`
	T string `json:"t"`
}

// UploadNovel 上传 TXT
func UploadNovel(c *gin.Context) {
	userID := int(c.GetInt64("user_id"))

	title := strings.TrimSpace(c.PostForm("title"))
	if title == "" {
		ErrorResponse(c, http.StatusBadRequest, "小说标题不能为空")
		return
	}

	var existingID int
	err := models.DB.QueryRow("SELECT id FROM novels WHERE title = ?", title).Scan(&existingID)
	if err != sql.ErrNoRows {
		if err == nil {
			ErrorResponse(c, http.StatusConflict, "书库中已有该小说，请直接在书架中选择")
			return
		}
		ErrorResponse(c, http.StatusInternalServerError, "数据库访问错误")
		return
	}

	file, err := c.FormFile("file")
	if err != nil {
		ErrorResponse(c, http.StatusBadRequest, "文件上传失败或未选择文件")
		return
	}

	f, err := file.Open()
	if err != nil {
		ErrorResponse(c, http.StatusInternalServerError, "无法读取文件")
		return
	}
	defer f.Close()

	contentBytes, err := io.ReadAll(f)
	if err != nil {
		ErrorResponse(c, http.StatusInternalServerError, "无法读取文件内容")
		return
	}

	text := string(contentBytes)
	text = strings.ReplaceAll(text, "\r\n", "\n")
	rawParagraphs := strings.Split(text, "\n")

	var paragraphs []Paragraph
	for _, p := range rawParagraphs {
		cleanP := strings.TrimSpace(p)
		if len(cleanP) > 0 {
			if validTextRegexp.MatchString(cleanP) {
				paragraphs = append(paragraphs, Paragraph{
					V: "zh-CN-YunyangNeural",
					T: cleanP,
				})
			}
		}
	}

	if len(paragraphs) == 0 {
		ErrorResponse(c, http.StatusBadRequest, "文本内容为空或无法识别有效段落")
		return
	}

	jsonBytes, _ := json.Marshal(paragraphs)

	_, err = models.DB.Exec("INSERT INTO novels (title, content_json, total_paragraphs, uploader_id) VALUES (?, ?, ?, ?)", title, string(jsonBytes), len(paragraphs), userID)
	if err != nil {
		ErrorResponse(c, http.StatusInternalServerError, "保存小说到书库失败")
		return
	}

	SuccessMessage(c, "上传成功并进入公共图书馆")
}

// GetNovelContent 获取指定小说的内容
func GetNovelContent(c *gin.Context) {
	novelID := c.Param("id")

	var contentJson string
	err := models.DB.QueryRow("SELECT content_json FROM novels WHERE id = ?", novelID).Scan(&contentJson)
	if err != nil {
		if err == sql.ErrNoRows {
			ErrorResponse(c, http.StatusNotFound, "未找到该小说")
			return
		}
		ErrorResponse(c, http.StatusInternalServerError, "数据库访问错误")
		return
	}

	c.Data(http.StatusOK, "application/json", []byte(contentJson))
}

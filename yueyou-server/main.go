package main

import (
	"database/sql"
	"log"
	"net/http"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

// ========= 状态上报与拉取 Handler =========

type SaveStateReq struct {
	BoardData      string `json:"board_data" binding:"required"`
	Score          int    `json:"score"`
	NovelIndex     int    `json:"novel_index"`
	CurrentNovelID int    `json:"current_novel_id"`
}

func SaveState(c *gin.Context) {
	userID := int(c.GetInt64("user_id"))

	var req SaveStateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid state data"})
		return
	}

	// 使用 SQLite 原生 UPSERT 覆盖更新最新进度
	stmt, err := db.Prepare(`
		INSERT INTO game_states (user_id, board_data, score, novel_index, current_novel_id, updated_at) 
		VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
		ON CONFLICT(user_id) DO UPDATE SET 
			board_data = excluded.board_data,
			score = excluded.score,
			novel_index = excluded.novel_index,
			current_novel_id = excluded.current_novel_id,
			updated_at = CURRENT_TIMESTAMP;
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Prepare error"})
		return
	}
	defer stmt.Close()

	if _, err := stmt.Exec(userID, req.BoardData, req.Score, req.NovelIndex, req.CurrentNovelID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Execution error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func LoadState(c *gin.Context) {
	userID := int(c.GetInt64("user_id"))

	var boardData string
	var score, novelIndex, currentNovelID int
	var novelTitle string

	err := db.QueryRow(`
		SELECT g.board_data, g.score, g.novel_index, g.current_novel_id, COALESCE(n.title, '三国演义·桃园结义片段')
		FROM game_states g
		LEFT JOIN novels n ON g.current_novel_id = n.id
		WHERE g.user_id = ?
	`, userID).Scan(&boardData, &score, &novelIndex, &currentNovelID, &novelTitle)

	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusOK, gin.H{
				"found":            false,
				"novel_index":      0,
				"current_novel_id": 1,
				"novel_title":      "三国演义·桃园结义片段",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"found":            true,
		"board_data":       boardData,
		"score":            score,
		"novel_index":      novelIndex,
		"current_novel_id": currentNovelID,
		"novel_title":      novelTitle,
	})
}

// ========= Main Web Server =========

func main() {
	// 初始化 SQLite (使用 modernc.org/sqlite, 无 CGO 取代 go-sqlite3)
	initDB()
	defer db.Close()

	r := gin.Default()

	// 允许跨域请求 (CORS) 供前端浏览器测试访问
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"}, // 测试环境允许所有
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Length", "Content-Type", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	api := r.Group("/api")
	{
		// 登录网关：签发 JWT Token
		api.POST("/auth/register", HandleRegister)
		api.POST("/auth/login", HandleLogin)

		// 进度存取 (需要 JWT)
		authLayer := api.Group("/", AuthMiddleware())
		{
			authLayer.GET("/state/load", LoadState)
			authLayer.POST("/state/save", SaveState)

			// 只有上传需要鉴权
			authLayer.POST("/novel/upload", UploadNovel)
		}

		// 公共书架 (获取无需 JWT，防滥用可加)
		api.GET("/novels", GetNovels)
		api.GET("/novel/:id", GetNovelContent)
	}

	log.Println("Go Backend listening on :8080 (Pure SQLite enabled, Public Library active)")
	err := r.Run(":8080")
	if err != nil {
		log.Fatalf("Server Startup failed: %v", err)
	}
}

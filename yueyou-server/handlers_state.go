package main

import (
	"database/sql"
	"net/http"

	"github.com/gin-gonic/gin"
)

// ======================================
// 游戏状态存取 Handler (state.go)
// 职责：处理游戏进度的云端保存与读取
// ======================================

// SaveStateReq 游戏状态保存请求体
type SaveStateReq struct {
	BoardData      string `json:"board_data" binding:"required"`
	Score          int    `json:"score"`
	NovelIndex     int    `json:"novel_index"`
	CurrentNovelID int    `json:"current_novel_id"`
}

// SaveState 保存当前用户的游戏进度（UPSERT 覆盖更新）
func SaveState(c *gin.Context) {
	userID := int(c.GetInt64("user_id"))

	var req SaveStateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求数据格式不正确"})
		return
	}

	// SQLite 原生 UPSERT：存在则覆盖，不存在则插入
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "数据库预处理失败"})
		return
	}
	defer stmt.Close()

	if _, err := stmt.Exec(userID, req.BoardData, req.Score, req.NovelIndex, req.CurrentNovelID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "游戏进度保存失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// LoadState 读取当前用户的游戏进度
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
			// 新用户，返回默认初始值
			c.JSON(http.StatusOK, gin.H{
				"found":            false,
				"novel_index":      0,
				"current_novel_id": 1,
				"novel_title":      "三国演义·桃园结义片段",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "数据库查询失败"})
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

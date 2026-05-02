package main

import (
	_ "embed"
	"fmt"
	"log"

	"github.com/gin-gonic/gin"
)

// xiyoujiCatalogJSON 在编译期嵌入目录文件，换版本时只需替换 data/xiyouji_catalog.json 并重新编译。
//
//go:embed data/xiyouji_catalog.json
var xiyoujiCatalogJSON []byte

// xiyoujiTotalChapters 总章节数，与客户端 BookConstants.defaultTotalChapters 严格对齐。
const xiyoujiTotalChapters = 100

// bookCatalogHandler 返回西游记目录（章节标题列表）。
//
// GET /api/v1/book/catalog?bookId=xiyouji
//
// 响应格式：{"status":"success","chapters":[{"title":"...","lineIndex":0}...]}
func bookCatalogHandler(c *gin.Context) {
	bookID := c.Query("bookId")
	if bookID != "xiyouji" {
		c.JSON(404, gin.H{"status": "error", "message": "书籍不存在"})
		return
	}
	// 直接返回嵌入的 JSON，客户端按约定解析
	c.Data(200, "application/json; charset=utf-8", xiyoujiCatalogJSON)
}

// bookChapterHandler 派发章节 CDN 下载地址，遵循分离下载原则。
//
// POST /api/v1/book/chapter
// 请求体：{"bookId":"xiyouji","chapterIndex":0}
// 响应体：{"status":"success","url":"https://cdn.../books/chapters/xiyouji/001.txt"}
//
// 客户端收到 URL 后自行 GET 下载章节正文，与 TTS 分离下载完全对齐。
func bookChapterHandler(c *gin.Context) {
	var req struct {
		BookID       string `json:"bookId"       binding:"required"`
		ChapterIndex int    `json:"chapterIndex"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"status": "error", "message": "参数错误"})
		return
	}
	if req.BookID != "xiyouji" {
		c.JSON(404, gin.H{"status": "error", "message": "书籍不存在"})
		return
	}
	if req.ChapterIndex < 0 || req.ChapterIndex >= xiyoujiTotalChapters {
		c.JSON(400, gin.H{"status": "error", "message": "章节索引越界"})
		return
	}

	// chapterIndex 0-based，OSS 文件名 1-based 三位补零
	filename := fmt.Sprintf("%03d.txt", req.ChapterIndex+1)
	url := fmt.Sprintf("%s/books/xiyouji/%s", cfg.OSSPub, filename)

	log.Printf("[Book] 派发章节: index=%d -> %s", req.ChapterIndex, url)

	c.JSON(200, gin.H{
		"status": "success",
		"url":    url,
	})
}

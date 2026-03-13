package main

import (
	"log"
	"time"

	"2048-go/handlers"
	"2048-go/models"
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

func main() {
	// 1. 初始化数据库
	models.InitDB()
	defer models.DB.Close()

	// 2. 创建 Gin 引擎
	r := gin.Default()

	// 3. 配置 CORS
	r.Use(cors.New(cors.Config{
		AllowOrigins: []string{
			"capacitor://localhost",
			"http://localhost",
			"http://localhost:3000",
			"http://localhost:8080",
			"http://localhost:5173",
		},
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Length", "Content-Type", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	// 4. 注册路由
	registerRoutes(r)

	// 5. 启动服务
	log.Println("阅游后端服务启动，监听端口 :8080")
	if err := r.Run(":8080"); err != nil {
		log.Fatalf("服务启动失败: %v", err)
	}
}

func registerRoutes(r *gin.Engine) {
	api := r.Group("/api")
	{
		// --- 认证相关（无需 JWT）---
		api.POST("/auth/register", handlers.HandleRegister)
		api.POST("/auth/login", handlers.HandleLogin)

		// --- 需要 JWT 鉴权的接口 ---
		auth := api.Group("/", handlers.AuthMiddleware())
		{
			auth.GET("/state/load", handlers.LoadState)
			auth.POST("/state/save", handlers.SaveState)
			auth.POST("/novel/upload", handlers.UploadNovel)
		}

		// --- 公共书架（无需 JWT）---
		api.GET("/novels", handlers.GetNovels)
		api.GET("/novel/:id", handlers.GetNovelContent)
	}
}

package main

import (
	"log"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

// ======================================
// 应用入口 (main.go)
// 职责：初始化服务、注册路由、启动服务器
// 业务逻辑请勿写在此文件
// ======================================

func main() {
	// 1. 初始化数据库
	initDB()
	defer db.Close()

	// 2. 创建 Gin 引擎
	r := gin.Default()

	// 3. 配置 CORS（白名单制，详见 Task 1.2）
	r.Use(cors.New(cors.Config{
		AllowOrigins: []string{
			"capacitor://localhost", // Android/iOS WebView（APK 内嵌模式）
			"http://localhost",      // 本地开发
			"http://localhost:3000", // 本地开发端口
			"http://localhost:8080", // 本地开发端口
			"http://localhost:5173", // Vite 开发服务器
			// 部署上线后在此添加正式域名，例如：
			// "https://yueyou.yourdomain.com",
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

// registerRoutes 集中注册所有路由
// 新增接口时，请在此处添加路由，Handler 实现放到对应的 handlers_*.go 文件
func registerRoutes(r *gin.Engine) {
	api := r.Group("/api")
	{
		// --- 认证相关（无需 JWT）---
		api.POST("/auth/register", HandleRegister)
		api.POST("/auth/login", HandleLogin)

		// --- 需要 JWT 鉴权的接口 ---
		auth := api.Group("/", AuthMiddleware())
		{
			auth.GET("/state/load", LoadState)
			auth.POST("/state/save", SaveState)
			auth.POST("/novel/upload", UploadNovel)
		}

		// --- 公共书架（无需 JWT）---
		api.GET("/novels", GetNovels)
		api.GET("/novel/:id", GetNovelContent)
	}
}

package main

import (
	"bytes"
	"crypto/md5"
	"fmt"
	"log"
	"os"
	"os/exec"

	"github.com/aliyun/aliyun-oss-go-sdk/oss"
	"github.com/gin-gonic/gin"
)

// ttsHandler 接受文本和音色，生成 MP3 并上传 OSS，返回 CDN 播放地址。
// 遵循分离下载原则：客户端 POST 获取 URL，再自行 GET 下载音频。
func ttsHandler(c *gin.Context) {
	var req struct {
		Text  string `json:"text"  binding:"required"`
		Voice string `json:"voice"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"status": "error", "message": "JSON error"})
		return
	}
	if req.Voice == "" {
		req.Voice = "zh-CN-XiaoxiaoNeural"
	}

	hash := md5.Sum([]byte(req.Text + req.Voice))
	fn := fmt.Sprintf("cache/%x.mp3", hash)
	fu := fmt.Sprintf("%s/%s", cfg.OSSPub, fn)

	bk, err := ossBucket()
	if err != nil {
		c.JSON(500, gin.H{"status": "error", "message": "OSS 初始化失败"})
		return
	}

	// 缓存命中直接返回
	if ok, _ := bk.IsObjectExist(fn); ok {
		c.JSON(200, gin.H{"status": "success", "url": fu})
		return
	}

	log.Printf("[TTS] 合成: %s", req.Text)

	tmpFile := fmt.Sprintf("/tmp/tts_%x.mp3",
		md5.Sum([]byte(req.Text+req.Voice+fmt.Sprintf("%d", os.Getpid()))))
	cmd := exec.Command("edge-tts",
		"--text", req.Text,
		"--voice", req.Voice,
		"--write-media", tmpFile,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		log.Printf("[TTS] edge-tts 错误: %v, output: %s", err, string(out))
		c.JSON(500, gin.H{"status": "error", "message": "语音合成失败"})
		return
	}

	audioData, err := os.ReadFile(tmpFile)
	os.Remove(tmpFile)
	if err != nil {
		c.JSON(500, gin.H{"status": "error", "message": "读取音频失败"})
		return
	}
	if len(audioData) < 100 {
		c.JSON(500, gin.H{"status": "error", "message": "生成音频为空"})
		return
	}

	if err := bk.PutObject(fn, bytes.NewReader(audioData)); err != nil {
		c.JSON(500, gin.H{"status": "error", "message": "OSS 上传失败"})
		return
	}

	c.JSON(200, gin.H{"status": "success", "url": fu})
}

// ossBucket 返回配置好的 OSS bucket 客户端。
func ossBucket() (*oss.Bucket, error) {
	cli, err := oss.New(cfg.OSSEndpoint, cfg.AKID, cfg.AKSecret)
	if err != nil {
		return nil, err
	}
	return cli.Bucket(cfg.OSSBucket)
}

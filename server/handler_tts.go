package main

import (
	"bytes"
	"crypto/md5"
	"fmt"
	"log"
	"os"
	"os/exec"
	"sync"

	"github.com/aliyun/aliyun-oss-go-sdk/oss"
	"github.com/gin-gonic/gin"
)

// edgeTtsSem 严格串行化 edge-tts 进程，避免触发微软服务端并发任务限制。
var edgeTtsSem = make(chan struct{}, 1)

// inflightMu 保护 inflightKeys，用于对同一文本的并发请求去重。
var (
	inflightMu   sync.Mutex
	inflightKeys = map[string]chan struct{}{}
)

// allowedVoices 是服务端音色白名单，与客户端 VoiceConstants 保持同步。
var allowedVoices = map[string]bool{
	"zh-CN-XiaoxiaoNeural": true,
	"zh-CN-YunxiNeural":    true,
	"zh-CN-YunjianNeural":  true,
	"zh-CN-XiaoyiNeural":   true,
	"zh-CN-XiaomengNeural": true,
}

// maxTextRunes 单次 TTS 请求的最大文本长度（Unicode 字符数）。
const maxTextRunes = 2000

// ttsHandler 接受文本和音色，生成 MP3 并上传 OSS，返回 CDN 播放地址。
// 遵循分离下载原则：客户端 POST 获取 URL，再自行 GET 下载音频。
func ttsHandler(c *gin.Context) {
	var req struct {
		Text  string `json:"text"  binding:"required"`
		Voice string `json:"voice"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		fail(c, 400, "JSON error")
		return
	}

	// 输入校验：文本长度上限，防止超大请求耗尽资源
	if len([]rune(req.Text)) > maxTextRunes {
		fail(c, 400, "文本过长，最多支持 2000 字符")
		return
	}

	// 输入校验：音色白名单
	if req.Voice == "" {
		req.Voice = "zh-CN-XiaoxiaoNeural"
	} else if !allowedVoices[req.Voice] {
		fail(c, 400, "不支持的音色")
		return
	}

	hash := md5.Sum([]byte(req.Text + req.Voice))
	fn := fmt.Sprintf("cache/%x.mp3", hash)
	fu := fmt.Sprintf("%s/%s", cfg.OSSPub, fn)

	if ossBk == nil {
		fail(c, 500, "OSS 未初始化")
		return
	}

	// 缓存命中直接返回
	if ossExist(fn) {
		ok(c, gin.H{"status": "success", "url": fu})
		return
	}

	// 同一文本正在合成时，等待已有任务完成后复用 OSS 缓存，避免重复调用 edge-tts
	inflightMu.Lock()
	if ch, exists := inflightKeys[fn]; exists {
		inflightMu.Unlock()
		<-ch
		if ossExist(fn) {
			ok(c, gin.H{"status": "success", "url": fu})
		} else {
			fail(c, 500, "语音合成失败")
		}
		return
	}
	doneCh := make(chan struct{})
	inflightKeys[fn] = doneCh
	inflightMu.Unlock()
	defer func() {
		close(doneCh)
		inflightMu.Lock()
		delete(inflightKeys, fn)
		inflightMu.Unlock()
	}()

	log.Printf("[TTS] 合成: %s", req.Text)

	// 获取信号量，严格串行化 edge-tts 进程
	edgeTtsSem <- struct{}{}
	defer func() { <-edgeTtsSem }()

	tmpFile := fmt.Sprintf("/tmp/tts_%x.mp3",
		md5.Sum([]byte(req.Text+req.Voice+fmt.Sprintf("%d", os.Getpid()))))
	cmd := exec.Command("edge-tts",
		"--text", req.Text,
		"--voice", req.Voice,
		"--write-media", tmpFile,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		log.Printf("[TTS] edge-tts 错误: %v, output: %s", err, string(out))
		fail(c, 500, "语音合成失败")
		return
	}

	audioData, err := os.ReadFile(tmpFile)
	os.Remove(tmpFile)
	if err != nil {
		fail(c, 500, "读取音频失败")
		return
	}
	if len(audioData) < 100 {
		fail(c, 500, "生成音频为空")
		return
	}

	if err := ossBk.PutObject(fn, bytes.NewReader(audioData)); err != nil {
		fail(c, 500, "OSS 上传失败")
		return
	}

	// 上传成功后主动写入缓存，避免下次再发起 IsObjectExist 请求
	ossExistCache.Store(fn, true)

	ok(c, gin.H{"status": "success", "url": fu})
}

var ossBk *oss.Bucket
var ossExistCache sync.Map

func initOssBucket() error {
	cli, err := oss.New(cfg.OSSEndpoint, cfg.AKID, cfg.AKSecret)
	if err != nil {
		return err
	}
	ossBk, err = cli.Bucket(cfg.OSSBucket)
	return err
}

func ossExist(key string) bool {
	if _, ok := ossExistCache.Load(key); ok {
		// 只有上传成功后才会写入 true，直接信任缓存
		return true
	}
	exists, _ := ossBk.IsObjectExist(key)
	if exists {
		// 仅缓存"存在"的 key，"不存在"不缓存（防止 stale false-positive）
		ossExistCache.Store(key, true)
	}
	return exists
}

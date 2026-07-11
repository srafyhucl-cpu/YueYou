package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/aliyun/aliyun-oss-go-sdk/oss"
	"github.com/gin-gonic/gin"
)

// edgeTtsSem 严格串行化 edge-tts 进程，避免触发微软服务端并发任务限制。
var edgeTtsSem = make(chan struct{}, 1)

// edgeTtsQueue 限制等待合成的请求数量，防止无界 goroutine 堆积。
var edgeTtsQueue = make(chan struct{}, 50)

// inflightMu 保护 inflightKeys，用于对同一安全对象键的并发请求去重。
var (
	inflightMu   sync.Mutex
	inflightKeys = map[string]chan struct{}{}
)

// allowedVoices 是服务端音色白名单。
// 新增音色时须同步更新客户端 settings_provider.dart 的 loadFromStorage 白名单。
var allowedVoices = map[string]bool{
	"zh-CN-XiaoxiaoNeural": true,
	"zh-CN-YunxiNeural":    true,
	"zh-CN-YunjianNeural":  true,
	"zh-CN-XiaoyiNeural":   true,
	"zh-CN-XiaomengNeural": true,
}

// maxTextRunes 单次 TTS 请求的最大文本长度（Unicode 字符数）。
const maxTextRunes = 2000

const defaultVoice = "zh-CN-XiaoxiaoNeural"

type ttsRequest struct {
	Text  string `json:"text"`
	Voice string `json:"voice"`
}

type ttsObjectStore interface {
	Exists(key string) bool
	PutPrivate(key string, audio []byte) error
	SignedGetURL(key string, ttl time.Duration) (string, error)
	Ready(ctx context.Context) error
}

type edgeTTSExecutor interface {
	Synthesize(ctx context.Context, text string, voice string) ([]byte, error)
}

var (
	ttsStore     ttsObjectStore
	ttsExecutor  edgeTTSExecutor = realEdgeTTSExecutor{}
	edgeTTSReady                 = realEdgeTTSReady
	ttsLimiter                   = newTTSRateLimiter()
)

// ttsHandler 接受文本和音色，生成 MP3 并上传私有 OSS 对象，返回短效签名下载 URL。
// 遵循分离下载原则：客户端 POST 获取 URL，再自行 GET 下载音频。
func ttsHandler(c *gin.Context) {
	requestID := newRequestID()
	req, okReq := bindTTSRequest(c)
	if !okReq {
		return
	}
	if !allowTTSRequest(c, requestID) {
		return
	}

	objKey := ttsObjectKey(req.Text, req.Voice)
	if ttsStore == nil {
		log.Printf("[TTS] request_id=%s status=store_not_ready", requestID)
		fail(c, http.StatusServiceUnavailable, "TTS 存储未就绪")
		return
	}

	if ttsStore.Exists(objKey) {
		respondWithSignedURL(c, requestID, objKey, "cache_hit")
		return
	}

	inflightCh, ownsInflight := acquireInflight(objKey)
	if !ownsInflight {
		waitForInflight(c, requestID, objKey, inflightCh)
		return
	}
	defer releaseInflight(objKey, inflightCh)

	if !acquireEdgeSlot(c, requestID) {
		return
	}
	defer releaseEdgeSlot()

	log.Printf(
		"[TTS] request_id=%s status=synth_start voice=%s chars=%d",
		requestID,
		req.Voice,
		utf8.RuneCountInString(req.Text),
	)
	started := time.Now()
	audioData, err := ttsExecutor.Synthesize(c.Request.Context(), req.Text, req.Voice)
	if err != nil {
		if errors.Is(err, context.Canceled) {
			log.Printf("[TTS] request_id=%s status=client_canceled", requestID)
			return
		}
		log.Printf("[TTS] request_id=%s status=edge_error error=%T", requestID, err)
		fail(c, http.StatusInternalServerError, "语音合成失败")
		return
	}
	if len(audioData) < 100 {
		log.Printf("[TTS] request_id=%s status=empty_audio bytes=%d", requestID, len(audioData))
		fail(c, http.StatusInternalServerError, "生成音频为空")
		return
	}
	if err := ttsStore.PutPrivate(objKey, audioData); err != nil {
		log.Printf("[TTS] request_id=%s status=oss_upload_failed error=%T", requestID, err)
		fail(c, http.StatusInternalServerError, "OSS 上传失败")
		return
	}

	log.Printf(
		"[TTS] request_id=%s status=synth_ok voice=%s chars=%d bytes=%d elapsed_ms=%d",
		requestID,
		req.Voice,
		utf8.RuneCountInString(req.Text),
		len(audioData),
		time.Since(started).Milliseconds(),
	)
	respondWithSignedURL(c, requestID, objKey, "synth_ok")
}

func bindTTSRequest(c *gin.Context) (ttsRequest, bool) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, cfg.TTSMaxBodyBytes)
	defer c.Request.Body.Close()

	var req ttsRequest
	decoder := json.NewDecoder(c.Request.Body)
	if err := decoder.Decode(&req); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			fail(c, http.StatusRequestEntityTooLarge, "请求体过大")
			return req, false
		}
		fail(c, http.StatusBadRequest, "JSON error")
		return req, false
	}
	if strings.TrimSpace(req.Text) == "" {
		fail(c, http.StatusBadRequest, "文本不能为空")
		return req, false
	}
	if utf8.RuneCountInString(req.Text) > maxTextRunes {
		fail(c, http.StatusBadRequest, "文本过长，最多支持 2000 字符")
		return req, false
	}
	if req.Voice == "" {
		req.Voice = defaultVoice
	} else if !allowedVoices[req.Voice] {
		fail(c, http.StatusBadRequest, "不支持的音色")
		return req, false
	}
	return req, true
}

func allowTTSRequest(c *gin.Context, requestID string) bool {
	if !ttsLimiter.allow("ip:"+c.ClientIP(), cfg.TTSIPLimitPerMin, time.Minute) {
		log.Printf("[TTS] request_id=%s status=rate_limited dimension=ip", requestID)
		fail(c, http.StatusTooManyRequests, "请求过于频繁")
		return false
	}
	installID := strings.TrimSpace(c.GetHeader("X-YueYou-Install-ID"))
	if installID == "" {
		return true
	}
	if len(installID) > 128 {
		fail(c, http.StatusBadRequest, "安装 ID 无效")
		return false
	}
	if !ttsLimiter.allow("install:"+installID, cfg.TTSIDLimitPerHour, time.Hour) {
		log.Printf("[TTS] request_id=%s status=rate_limited dimension=install_id", requestID)
		fail(c, http.StatusTooManyRequests, "请求过于频繁")
		return false
	}
	return true
}

func waitForInflight(c *gin.Context, requestID string, objKey string, ch chan struct{}) {
	select {
	case <-ch:
		if ttsStore.Exists(objKey) {
			respondWithSignedURL(c, requestID, objKey, "inflight_reused")
		} else {
			fail(c, http.StatusInternalServerError, "语音合成失败")
		}
	case <-c.Request.Context().Done():
		log.Printf("[TTS] request_id=%s status=client_canceled_waiting_inflight", requestID)
	}
}

func acquireInflight(objKey string) (chan struct{}, bool) {
	inflightMu.Lock()
	defer inflightMu.Unlock()
	if ch, exists := inflightKeys[objKey]; exists {
		return ch, false
	}
	doneCh := make(chan struct{})
	inflightKeys[objKey] = doneCh
	return doneCh, true
}

func releaseInflight(objKey string, doneCh chan struct{}) {
	close(doneCh)
	inflightMu.Lock()
	delete(inflightKeys, objKey)
	inflightMu.Unlock()
}

func acquireEdgeSlot(c *gin.Context, requestID string) bool {
	select {
	case edgeTtsQueue <- struct{}{}:
	case <-c.Request.Context().Done():
		log.Printf("[TTS] request_id=%s status=client_canceled_waiting_queue", requestID)
		return false
	default:
		log.Printf("[TTS] request_id=%s status=queue_full", requestID)
		fail(c, http.StatusTooManyRequests, "TTS 队列已满，请稍后重试")
		return false
	}
	select {
	case edgeTtsSem <- struct{}{}:
		return true
	case <-c.Request.Context().Done():
		<-edgeTtsQueue
		log.Printf("[TTS] request_id=%s status=client_canceled_waiting_synth", requestID)
		return false
	}
}

func releaseEdgeSlot() {
	<-edgeTtsSem
	<-edgeTtsQueue
}

func respondWithSignedURL(c *gin.Context, requestID string, objKey string, status string) {
	signedURL, err := ttsStore.SignedGetURL(objKey, cfg.TTSSignedURLTTL)
	if err != nil {
		log.Printf("[TTS] request_id=%s status=sign_url_failed error=%T", requestID, err)
		fail(c, http.StatusInternalServerError, "生成下载链接失败")
		return
	}
	log.Printf("[TTS] request_id=%s status=%s ttl_seconds=%d", requestID, status, int64(cfg.TTSSignedURLTTL.Seconds()))
	ok(c, gin.H{"status": "success", "url": signedURL})
}

func ttsObjectKey(text string, voice string) string {
	mac := hmac.New(sha256.New, []byte(cfg.TTSObjectKeySecret))
	_, _ = io.WriteString(mac, voice)
	_, _ = io.WriteString(mac, "\n")
	_, _ = io.WriteString(mac, text)
	return fmt.Sprintf("cache/tts/v2/%s.mp3", hex.EncodeToString(mac.Sum(nil)))
}

func newRequestID() string {
	var b [12]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b[:])
}

type realEdgeTTSExecutor struct{}

func realEdgeTTSReady() error {
	_, err := exec.LookPath("edge-tts")
	return err
}

func (realEdgeTTSExecutor) Synthesize(ctx context.Context, text string, voice string) ([]byte, error) {
	tmpFile, err := os.CreateTemp("", "yueyou_tts_*.mp3")
	if err != nil {
		return nil, err
	}
	tmpPath := tmpFile.Name()
	if err := tmpFile.Close(); err != nil {
		_ = os.Remove(tmpPath)
		return nil, err
	}
	defer os.Remove(tmpPath)

	cmd := exec.CommandContext(ctx, "edge-tts",
		"--text", text,
		"--voice", voice,
		"--write-media", tmpPath,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		log.Printf("[TTS] edge_tts_failed error=%T output_bytes=%d", err, len(out))
		return nil, err
	}
	return os.ReadFile(tmpPath)
}

type ossTTSObjectStore struct {
	uploadBucket *oss.Bucket
	signBucket   *oss.Bucket
	existCache   sync.Map
}

func (s *ossTTSObjectStore) Exists(key string) bool {
	if _, ok := s.existCache.Load(key); ok {
		return true
	}
	exists, err := s.uploadBucket.IsObjectExist(key)
	if err != nil {
		log.Printf("[TTS] oss_exist_failed error=%T", err)
		return false
	}
	if exists {
		s.existCache.Store(key, true)
	}
	return exists
}

func (s *ossTTSObjectStore) PutPrivate(key string, audio []byte) error {
	err := s.uploadBucket.PutObject(
		key,
		bytes.NewReader(audio),
		oss.ObjectACL(oss.ACLPrivate),
		oss.ContentType("audio/mpeg"),
	)
	if err != nil {
		return err
	}
	s.existCache.Store(key, true)
	return nil
}

func (s *ossTTSObjectStore) SignedGetURL(key string, ttl time.Duration) (string, error) {
	return s.signBucket.SignURL(key, oss.HTTPGet, int64(ttl.Seconds()))
}

func (s *ossTTSObjectStore) Ready(ctx context.Context) error {
	if s == nil || s.uploadBucket == nil || s.signBucket == nil {
		return errors.New("oss bucket not initialized")
	}
	errCh := make(chan error, 1)
	go func() {
		_, err := s.uploadBucket.IsObjectExist(".ready")
		errCh <- err
	}()
	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		return ctx.Err()
	}
}

func initOssBucket() error {
	uploadCli, err := oss.New(cfg.OSSEndpoint, cfg.AKID, cfg.AKSecret)
	if err != nil {
		return err
	}
	uploadBucket, err := uploadCli.Bucket(cfg.OSSBucket)
	if err != nil {
		return err
	}
	signCli, err := oss.New(cfg.OSSSignEP, cfg.AKID, cfg.AKSecret)
	if err != nil {
		return err
	}
	signBucket, err := signCli.Bucket(cfg.OSSBucket)
	if err != nil {
		return err
	}
	ttsStore = &ossTTSObjectStore{uploadBucket: uploadBucket, signBucket: signBucket}
	return nil
}

type ttsRateLimiter struct {
	mu    sync.Mutex
	store ttsRateLimitStore
	clock ttsClock
}

type rateWindow struct {
	resetAt time.Time
	count   int
}

type ttsClock interface {
	Now() time.Time
}

type ttsRateLimitStore interface {
	Get(key string) rateWindow
	Set(key string, value rateWindow)
}

type realTTSClock struct{}

func (realTTSClock) Now() time.Time {
	return time.Now()
}

type memoryTTSRateLimitStore struct {
	windows map[string]rateWindow
}

func newMemoryTTSRateLimitStore() *memoryTTSRateLimitStore {
	return &memoryTTSRateLimitStore{windows: map[string]rateWindow{}}
}

func (s *memoryTTSRateLimitStore) Get(key string) rateWindow {
	return s.windows[key]
}

func (s *memoryTTSRateLimitStore) Set(key string, value rateWindow) {
	s.windows[key] = value
}

func newTTSRateLimiter() *ttsRateLimiter {
	return newTTSRateLimiterWithClock(realTTSClock{})
}

func newTTSRateLimiterWithClock(clock ttsClock) *ttsRateLimiter {
	return newTTSRateLimiterWithClockAndStore(clock, newMemoryTTSRateLimitStore())
}

func newTTSRateLimiterWithClockAndStore(clock ttsClock, store ttsRateLimitStore) *ttsRateLimiter {
	return &ttsRateLimiter{store: store, clock: clock}
}

func (l *ttsRateLimiter) allow(key string, limit int, window time.Duration) bool {
	now := l.clock.Now()
	l.mu.Lock()
	defer l.mu.Unlock()
	current := l.store.Get(key)
	if now.After(current.resetAt) {
		current = rateWindow{resetAt: now.Add(window)}
	}
	if current.count >= limit {
		l.store.Set(key, current)
		return false
	}
	current.count++
	l.store.Set(key, current)
	return true
}

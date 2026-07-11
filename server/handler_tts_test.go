package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

type fakeTTSStore struct {
	exists   map[string]bool
	putKeys  []string
	signKeys []string
	readyErr error
	putErr   error
	signErr  error
}

func (s *fakeTTSStore) Exists(key string) bool {
	return s.exists[key]
}

func (s *fakeTTSStore) PutPrivate(key string, audio []byte) error {
	if s.putErr != nil {
		return s.putErr
	}
	s.exists[key] = true
	s.putKeys = append(s.putKeys, key)
	return nil
}

func (s *fakeTTSStore) SignedGetURL(key string, ttl time.Duration) (string, error) {
	if s.signErr != nil {
		return "", s.signErr
	}
	s.signKeys = append(s.signKeys, key)
	return "https://oss.test/" + key + "?Expires=600&Signature=fake", nil
}

func (s *fakeTTSStore) Ready(ctx context.Context) error {
	return s.readyErr
}

type fakeEdgeExecutor struct {
	calls int
}

func (e *fakeEdgeExecutor) Synthesize(ctx context.Context, text string, voice string) ([]byte, error) {
	e.calls++
	return bytes.Repeat([]byte{1}, 256), nil
}

func setupTTSTest(t *testing.T) (*gin.Engine, *fakeTTSStore, *fakeEdgeExecutor) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	oldCfg := cfg
	oldStore := ttsStore
	oldExecutor := ttsExecutor
	oldEdgeReady := edgeTTSReady
	oldLimiter := ttsLimiter
	oldSem := edgeTtsSem
	oldQueue := edgeTtsQueue
	oldInflight := inflightKeys
	oldLogOutput := log.Writer()

	cfg.TTSObjectKeySecret = "unit-test-secret"
	cfg.TTSSignedURLTTL = 10 * time.Minute
	cfg.TTSMaxBodyBytes = 16 * 1024
	cfg.TTSIPLimitPerMin = 30
	cfg.TTSIDLimitPerHour = 120
	edgeTtsSem = make(chan struct{}, 1)
	edgeTtsQueue = make(chan struct{}, 50)
	inflightKeys = map[string]chan struct{}{}
	ttsLimiter = newTTSRateLimiter()

	store := &fakeTTSStore{exists: map[string]bool{}}
	executor := &fakeEdgeExecutor{}
	ttsStore = store
	ttsExecutor = executor
	edgeTTSReady = func() error { return nil }

	router := gin.New()
	router.POST("/api/v1/tts", ttsHandler)
	router.GET("/api/v1/book/catalog", bookCatalogHandler)
	router.POST("/api/v1/book/chapter", bookChapterHandler)
	router.GET("/privacy", privacyHandler)
	router.GET("/health", healthHandler)
	router.GET("/ready", readyHandler)

	t.Cleanup(func() {
		cfg = oldCfg
		ttsStore = oldStore
		ttsExecutor = oldExecutor
		edgeTTSReady = oldEdgeReady
		ttsLimiter = oldLimiter
		edgeTtsSem = oldSem
		edgeTtsQueue = oldQueue
		inflightKeys = oldInflight
		log.SetOutput(oldLogOutput)
	})
	return router, store, executor
}

func postTTS(router http.Handler, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/api/v1/tts", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-YueYou-Install-ID", "install-unit")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

func TestTTSHandlerReturnsSignedURLWithoutLoggingRawText(t *testing.T) {
	router, store, executor := setupTTSTest(t)
	var logs bytes.Buffer
	log.SetOutput(&logs)
	rawText := "这是一段绝密朗读正文，绝不能出现在服务端日志里"
	body, _ := json.Marshal(map[string]string{
		"text":  rawText,
		"voice": "zh-CN-XiaoxiaoNeural",
	})

	w := postTTS(router, string(body))

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	if executor.calls != 1 {
		t.Fatalf("edge calls = %d, want 1", executor.calls)
	}
	if len(store.putKeys) != 1 {
		t.Fatalf("put keys = %v, want one", store.putKeys)
	}
	if !strings.HasPrefix(store.putKeys[0], "cache/tts/v2/") {
		t.Fatalf("object key = %s, want secure v2 prefix", store.putKeys[0])
	}
	if strings.Contains(store.putKeys[0], rawText) {
		t.Fatalf("object key leaked raw text: %s", store.putKeys[0])
	}
	if strings.Contains(logs.String(), rawText) {
		t.Fatalf("logs leaked raw text: %s", logs.String())
	}
	var decoded map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded["status"] != "success" {
		t.Fatalf("status body = %v", decoded)
	}
	if !strings.Contains(decoded["url"], "Expires=600") || !strings.Contains(decoded["url"], "Signature=fake") {
		t.Fatalf("url is not signed: %s", decoded["url"])
	}
}

func TestTTSHandlerRejectsOversizedBody(t *testing.T) {
	router, _, executor := setupTTSTest(t)
	largeText := strings.Repeat("甲", 9000)
	body, _ := json.Marshal(map[string]string{"text": largeText})

	w := postTTS(router, string(body))

	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413, body = %s", w.Code, w.Body.String())
	}
	if executor.calls != 0 {
		t.Fatalf("edge calls = %d, want 0", executor.calls)
	}
}

func TestTTSHandlerRejectsInvalidRequests(t *testing.T) {
	router, _, executor := setupTTSTest(t)
	cases := []struct {
		name string
		body string
		code int
	}{
		{name: "非法 JSON", body: `{"text":`, code: http.StatusBadRequest},
		{name: "空文本", body: `{"text":"   "}`, code: http.StatusBadRequest},
		{name: "文本过长", body: `{"text":"` + strings.Repeat("甲", maxTextRunes+1) + `"}`, code: http.StatusBadRequest},
		{name: "非法音色", body: `{"text":"你好","voice":"evil"}`, code: http.StatusBadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w := postTTS(router, tc.body)
			if w.Code != tc.code {
				t.Fatalf("status = %d, want %d, body = %s", w.Code, tc.code, w.Body.String())
			}
		})
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/tts", strings.NewReader(`{"text":"你好"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-YueYou-Install-ID", strings.Repeat("x", 129))
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("long install id status = %d, want 400", w.Code)
	}
	if executor.calls != 0 {
		t.Fatalf("edge calls = %d, want 0", executor.calls)
	}
}

func TestTTSHandlerRateLimitsIP(t *testing.T) {
	router, _, _ := setupTTSTest(t)
	cfg.TTSIPLimitPerMin = 1
	body := `{"text":"第一句","voice":"zh-CN-XiaoxiaoNeural"}`

	first := postTTS(router, body)
	second := postTTS(router, body)

	if first.Code != http.StatusOK {
		t.Fatalf("first status = %d", first.Code)
	}
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("second status = %d, want 429", second.Code)
	}
}

func TestTTSHandlerHandlesStoreFailures(t *testing.T) {
	router, store, executor := setupTTSTest(t)
	store.putErr = errors.New("oss put failed")
	putFailed := postTTS(router, `{"text":"上传失败","voice":"zh-CN-XiaoxiaoNeural"}`)
	if putFailed.Code != http.StatusInternalServerError {
		t.Fatalf("put failed status = %d, want 500", putFailed.Code)
	}
	if len(store.signKeys) != 0 {
		t.Fatalf("sign keys after put failure = %v, want empty", store.signKeys)
	}

	store.putErr = nil
	store.signErr = errors.New("sign failed")
	signFailed := postTTS(router, `{"text":"签名失败","voice":"zh-CN-XiaoxiaoNeural"}`)
	if signFailed.Code != http.StatusInternalServerError {
		t.Fatalf("sign failed status = %d, want 500", signFailed.Code)
	}
	if executor.calls != 2 {
		t.Fatalf("edge calls = %d, want 2", executor.calls)
	}
}

func TestTTSHandlerStoreNotReady(t *testing.T) {
	router, _, executor := setupTTSTest(t)
	ttsStore = nil

	w := postTTS(router, `{"text":"存储未就绪","voice":"zh-CN-XiaoxiaoNeural"}`)

	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", w.Code)
	}
	if executor.calls != 0 {
		t.Fatalf("edge calls = %d, want 0", executor.calls)
	}
}

func TestTTSHandlerRejectsWhenQueueFull(t *testing.T) {
	router, _, executor := setupTTSTest(t)
	edgeTtsQueue = make(chan struct{}, 1)
	edgeTtsQueue <- struct{}{}

	w := postTTS(router, `{"text":"排队测试","voice":"zh-CN-XiaoxiaoNeural"}`)

	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want 429", w.Code)
	}
	if executor.calls != 0 {
		t.Fatalf("edge calls = %d, want 0", executor.calls)
	}
}

func TestBookAndPrivacyHandlers(t *testing.T) {
	router, _, _ := setupTTSTest(t)

	privacyReq := httptest.NewRequest(http.MethodGet, "/privacy", nil)
	privacyW := httptest.NewRecorder()
	router.ServeHTTP(privacyW, privacyReq)
	if privacyW.Code != http.StatusOK {
		t.Fatalf("privacy status = %d, want 200", privacyW.Code)
	}
	if !strings.Contains(privacyW.Body.String(), "阅游隐私政策") {
		t.Fatalf("privacy body missing title")
	}

	catalogReq := httptest.NewRequest(http.MethodGet, "/api/v1/book/catalog?bookId=xiyouji", nil)
	catalogW := httptest.NewRecorder()
	router.ServeHTTP(catalogW, catalogReq)
	if catalogW.Code != http.StatusOK {
		t.Fatalf("catalog status = %d, want 200", catalogW.Code)
	}
	if !strings.Contains(catalogW.Body.String(), `"status"`) {
		t.Fatalf("catalog body missing status")
	}

	missingCatalogReq := httptest.NewRequest(http.MethodGet, "/api/v1/book/catalog?bookId=unknown", nil)
	missingCatalogW := httptest.NewRecorder()
	router.ServeHTTP(missingCatalogW, missingCatalogReq)
	if missingCatalogW.Code != http.StatusNotFound {
		t.Fatalf("missing catalog status = %d, want 404", missingCatalogW.Code)
	}

	chapterReq := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/book/chapter",
		strings.NewReader(`{"bookId":"xiyouji","chapterIndex":0}`),
	)
	chapterReq.Header.Set("Content-Type", "application/json")
	chapterW := httptest.NewRecorder()
	router.ServeHTTP(chapterW, chapterReq)
	if chapterW.Code != http.StatusOK {
		t.Fatalf("chapter status = %d, want 200", chapterW.Code)
	}
	if !strings.Contains(chapterW.Body.String(), "/books/xiyouji/001.txt") {
		t.Fatalf("chapter url unexpected: %s", chapterW.Body.String())
	}
}

func TestBookChapterHandlerRejectsInvalidRequests(t *testing.T) {
	router, _, _ := setupTTSTest(t)
	cases := []struct {
		name string
		body string
		code int
	}{
		{name: "非法 JSON", body: `{"bookId":`, code: http.StatusBadRequest},
		{name: "未知书籍", body: `{"bookId":"unknown","chapterIndex":0}`, code: http.StatusNotFound},
		{name: "章节越界", body: `{"bookId":"xiyouji","chapterIndex":100}`, code: http.StatusBadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/api/v1/book/chapter", strings.NewReader(tc.body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			router.ServeHTTP(w, req)
			if w.Code != tc.code {
				t.Fatalf("status = %d, want %d, body = %s", w.Code, tc.code, w.Body.String())
			}
		})
	}
}

func TestHealthAndReadyHandlers(t *testing.T) {
	router, store, _ := setupTTSTest(t)

	healthReq := httptest.NewRequest(http.MethodGet, "/health", nil)
	healthW := httptest.NewRecorder()
	router.ServeHTTP(healthW, healthReq)
	if healthW.Code != http.StatusOK {
		t.Fatalf("health status = %d", healthW.Code)
	}

	readyReq := httptest.NewRequest(http.MethodGet, "/ready", nil)
	readyW := httptest.NewRecorder()
	router.ServeHTTP(readyW, readyReq)
	if readyW.Code != http.StatusOK {
		t.Fatalf("ready status = %d", readyW.Code)
	}

	store.readyErr = errors.New("oss down")
	failedReadyW := httptest.NewRecorder()
	router.ServeHTTP(failedReadyW, readyReq)
	if failedReadyW.Code != http.StatusServiceUnavailable {
		t.Fatalf("failed ready status = %d", failedReadyW.Code)
	}

	store.readyErr = nil
	edgeTTSReady = func() error { return errors.New("edge missing") }
	failedEdgeReadyW := httptest.NewRecorder()
	router.ServeHTTP(failedEdgeReadyW, readyReq)
	if failedEdgeReadyW.Code != http.StatusServiceUnavailable {
		t.Fatalf("failed edge ready status = %d", failedEdgeReadyW.Code)
	}
}

func TestTTSHandlerCacheHitSkipsEdge(t *testing.T) {
	router, store, executor := setupTTSTest(t)
	key := ttsObjectKey("缓存命中", defaultVoice)
	store.exists[key] = true

	w := postTTS(router, `{"text":"缓存命中"}`)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	if executor.calls != 0 {
		t.Fatalf("edge calls = %d, want 0", executor.calls)
	}
	if len(store.signKeys) != 1 || store.signKeys[0] != key {
		t.Fatalf("sign keys = %v, want %s", store.signKeys, key)
	}
}

func TestNoRawTextInEdgeErrorLog(t *testing.T) {
	router, _, _ := setupTTSTest(t)
	ttsExecutor = failingEdgeExecutor{}
	var logs bytes.Buffer
	log.SetOutput(&logs)
	rawText := "失败时也不能泄露的正文"

	w := postTTS(router, `{"text":"`+rawText+`"}`)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", w.Code)
	}
	if strings.Contains(logs.String(), rawText) {
		t.Fatalf("logs leaked raw text: %s", logs.String())
	}
}

type failingEdgeExecutor struct{}

func (failingEdgeExecutor) Synthesize(ctx context.Context, text string, voice string) ([]byte, error) {
	return nil, io.ErrUnexpectedEOF
}

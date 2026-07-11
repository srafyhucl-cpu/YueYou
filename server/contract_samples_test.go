package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func readContractSample(t *testing.T, name string) []byte {
	t.Helper()
	path := filepath.Join("..", "docs", "contracts", name)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read contract sample %s: %v", name, err)
	}
	return data
}

func TestSharedContractSamplesForTTS(t *testing.T) {
	var success struct {
		Status string `json:"status"`
		URL    string `json:"url"`
	}
	if err := json.Unmarshal(readContractSample(t, "tts_success.json"), &success); err != nil {
		t.Fatalf("unmarshal tts success: %v", err)
	}
	if success.Status != "success" || !strings.Contains(success.URL, "Expires=") {
		t.Fatalf("unexpected tts success sample: %+v", success)
	}

	var failure struct {
		Status  string `json:"status"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal(readContractSample(t, "tts_error.json"), &failure); err != nil {
		t.Fatalf("unmarshal tts error: %v", err)
	}
	if failure.Status != "error" || failure.Message == "" {
		t.Fatalf("unexpected tts error sample: %+v", failure)
	}
}

func TestSharedContractSamplesForBook(t *testing.T) {
	var chapter struct {
		Status string `json:"status"`
		URL    string `json:"url"`
	}
	if err := json.Unmarshal(readContractSample(t, "book_chapter_success.json"), &chapter); err != nil {
		t.Fatalf("unmarshal book chapter: %v", err)
	}
	if chapter.Status != "success" || !strings.HasSuffix(chapter.URL, "/books/xiyouji/001.txt") {
		t.Fatalf("unexpected book chapter sample: %+v", chapter)
	}

	var catalog struct {
		Status   string `json:"status"`
		Chapters []struct {
			Title     string `json:"title"`
			LineIndex int    `json:"lineIndex"`
		} `json:"chapters"`
	}
	if err := json.Unmarshal(readContractSample(t, "book_catalog_success.json"), &catalog); err != nil {
		t.Fatalf("unmarshal book catalog: %v", err)
	}
	if catalog.Status != "success" || len(catalog.Chapters) == 0 || catalog.Chapters[0].Title == "" {
		t.Fatalf("unexpected book catalog sample: %+v", catalog)
	}
}

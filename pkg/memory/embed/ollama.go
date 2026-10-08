package embed

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os/exec"
	"strings"
	"time"
)

// OllamaEmbedder calls Ollama's embeddings API.
type OllamaEmbedder struct {
	Host   string
	Model  string
	client *http.Client
}

func NewOllamaEmbedder(host, model string) *OllamaEmbedder {
	return &OllamaEmbedder{
		Host:   strings.TrimRight(host, "/"),
		Model:  model,
		client: &http.Client{Timeout: 30 * time.Second},
	}
}

type ollamaEmbeddingReq struct {
	Model  string `json:"model"`
	Prompt string `json:"prompt"`
}

type ollamaEmbeddingResp struct {
	Embedding []float32 `json:"embedding"`
}

func (o *OllamaEmbedder) Embed(text string) ([]float32, error) {
	reqBody, err := json.Marshal(ollamaEmbeddingReq{
		Model:  o.Model,
		Prompt: text,
	})
	if err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/api/embeddings", o.Host)
	resp, err := o.client.Post(url, "application/json", bytes.NewReader(reqBody))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("ollama embed returned status %d", resp.StatusCode)
	}

	var res ollamaEmbeddingResp
	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
		return nil, err
	}

	return res.Embedding, nil
}

// ModelPresent checks if the model is locally available in Ollama.
func ModelPresent(host, model string) bool {
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(fmt.Sprintf("%s/api/tags", strings.TrimRight(host, "/")))
	if err != nil || resp.StatusCode != http.StatusOK {
		return false
	}
	defer resp.Body.Close()

	var tags struct {
		Models []struct {
			Name string `json:"name"`
		} `json:"models"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&tags); err != nil {
		return false
	}

	for _, m := range tags.Models {
		if strings.EqualFold(m.Name, model) || strings.HasPrefix(strings.ToLower(m.Name), strings.ToLower(model)+":") {
			return true
		}
	}
	return false
}

// PullModel executes `ollama pull <model>` or posts to /api/pull.
func PullModel(host, model string) error {
	// Try ollama CLI first if available
	cmd := exec.Command("ollama", "pull", model)
	if err := cmd.Run(); err == nil {
		return nil
	}

	// Fallback to HTTP POST /api/pull
	client := &http.Client{Timeout: 5 * time.Minute}
	reqBody, _ := json.Marshal(map[string]string{"name": model})
	resp, err := client.Post(fmt.Sprintf("%s/api/pull", strings.TrimRight(host, "/")), "application/json", bytes.NewReader(reqBody))
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("pull failed with status %d", resp.StatusCode)
	}
	return nil
}

// PullModelContext allows pulling with context.
func PullModelContext(ctx context.Context, host, model string) error {
	return PullModel(host, model)
}

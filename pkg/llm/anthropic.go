package llm

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/wdvn/tars/pkg/stream"
)

// AnthropicProvider implements Provider for Anthropic Messages API.
type AnthropicProvider struct {
	BaseURL string
	APIKey  string
	Model   string
	client  *http.Client
}

// NewAnthropicProvider initializes an AnthropicProvider.
func NewAnthropicProvider() *AnthropicProvider {
	baseURL := GetFirstEnv("ANTHROPIC_BASE_URL")
	if baseURL == "" {
		baseURL = "https://api.anthropic.com"
	}
	baseURL = strings.TrimRight(baseURL, "/")

	apiKey := GetFirstEnv("ANTHROPIC_API_KEY")
	model := GetFirstEnv("ANTHROPIC_MODEL")
	if model == "" {
		model = "claude-3-5-sonnet-20241022"
	}

	return &AnthropicProvider{
		BaseURL: baseURL,
		APIKey:  apiKey,
		Model:   model,
		client:  &http.Client{},
	}
}

type anthropicMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type anthropicRequest struct {
	Model       string             `json:"model"`
	System      string             `json:"system,omitempty"`
	Messages    []anthropicMessage `json:"messages"`
	MaxTokens   int                `json:"max_tokens"`
	Temperature float64            `json:"temperature,omitempty"`
	Stream      bool               `json:"stream,omitempty"`
}

type anthropicResponse struct {
	Content []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
	Usage struct {
		InputTokens  int `json:"input_tokens"`
		OutputTokens int `json:"output_tokens"`
	} `json:"usage"`
}

func (p *AnthropicProvider) buildRequest(req CompletionRequest, streamMode bool) anthropicRequest {
	model := req.Config.Model
	if model == "" || model == "default" {
		model = p.Model
	}

	msgs := make([]anthropicMessage, 0, len(req.Messages))
	for _, m := range req.Messages {
		msgs = append(msgs, anthropicMessage{Role: m.Role, Content: m.Content})
	}

	maxTokens := req.Config.MaxTokens
	if maxTokens == 0 {
		maxTokens = 4096
	}

	temp := req.Config.Temperature
	if temp == 0 {
		temp = 0.2
	}

	return anthropicRequest{
		Model:       model,
		System:      req.System,
		Messages:    msgs,
		MaxTokens:   maxTokens,
		Temperature: temp,
		Stream:      streamMode,
	}
}

func (p *AnthropicProvider) Complete(ctx context.Context, req CompletionRequest) (CompletionResponse, error) {
	antReq := p.buildRequest(req, false)
	reqBody, err := json.Marshal(antReq)
	if err != nil {
		return CompletionResponse{}, err
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", p.BaseURL+"/v1/messages", bytes.NewReader(reqBody))
	if err != nil {
		return CompletionResponse{}, err
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("x-api-key", p.APIKey)
	httpReq.Header.Set("anthropic-version", "2023-06-01")

	resp, err := p.client.Do(httpReq)
	if err != nil {
		return CompletionResponse{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return CompletionResponse{}, fmt.Errorf("anthropic request failed with status %d: %s", resp.StatusCode, string(body))
	}

	var antResp anthropicResponse
	if err := json.NewDecoder(resp.Body).Decode(&antResp); err != nil {
		return CompletionResponse{}, err
	}

	var sb strings.Builder
	for _, c := range antResp.Content {
		if c.Type == "text" {
			sb.WriteString(c.Text)
		}
	}
	content := sb.String()
	tokens := antResp.Usage.InputTokens + antResp.Usage.OutputTokens
	if tokens == 0 {
		tokens = len(content)
	}

	return CompletionResponse{
		ContentJSON: content,
		TokensUsed:  tokens,
	}, nil
}

func (p *AnthropicProvider) CompleteStream(ctx context.Context, req CompletionRequest, sink stream.Sink) (CompletionResponse, error) {
	antReq := p.buildRequest(req, true)
	reqBody, err := json.Marshal(antReq)
	if err != nil {
		return CompletionResponse{}, err
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", p.BaseURL+"/v1/messages", bytes.NewReader(reqBody))
	if err != nil {
		return CompletionResponse{}, err
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("x-api-key", p.APIKey)
	httpReq.Header.Set("anthropic-version", "2023-06-01")

	resp, err := p.client.Do(httpReq)
	if err != nil {
		return CompletionResponse{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return CompletionResponse{}, fmt.Errorf("anthropic stream failed with status %d: %s", resp.StatusCode, string(body))
	}

	var sb strings.Builder
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)
		if !strings.HasPrefix(trimmed, "data:") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(trimmed, "data:"))

		var event struct {
			Type  string `json:"type"`
			Delta struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"delta"`
		}
		if err := json.Unmarshal([]byte(data), &event); err == nil {
			if event.Type == "content_block_delta" && event.Delta.Text != "" {
				delta := event.Delta.Text
				sb.WriteString(delta)
				if sink != nil {
					_ = sink.Emit(stream.Chunk{Kind: stream.ChunkToken, Text: delta})
				}
			}
		}
	}

	full := sb.String()
	return CompletionResponse{
		ContentJSON: full,
		TokensUsed:  len(full),
	}, scanner.Err()
}

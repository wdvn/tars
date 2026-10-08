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

// OpenAIProvider calls OpenAI or compatible endpoints.
type OpenAIProvider struct {
	BaseURL    string
	APIKey     string
	APIHeader  string
	Model      string
	FromOllama bool
	client     *http.Client
}

// NewOpenAIProvider creates an OpenAIProvider.
func NewOpenAIProvider(compat *OpenAICompat) *OpenAIProvider {
	return &OpenAIProvider{
		BaseURL:    compat.BaseURL,
		APIKey:     compat.APIKey,
		APIHeader:  compat.APIHeader,
		Model:      compat.Model,
		FromOllama: compat.FromOllama,
		client:     &http.Client{},
	}
}

type openAIChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type openAIChatRequest struct {
	Model       string              `json:"model"`
	Messages    []openAIChatMessage `json:"messages"`
	Temperature float64             `json:"temperature,omitempty"`
	MaxTokens   int                 `json:"max_tokens,omitempty"`
	Stream      bool                `json:"stream,omitempty"`
}

type openAIChatChoice struct {
	Message struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	} `json:"message"`
	Delta struct {
		Content string `json:"content"`
	} `json:"delta"`
}

type openAIChatResponse struct {
	Choices []openAIChatChoice `json:"choices"`
	Usage   struct {
		TotalTokens int `json:"total_tokens"`
	} `json:"usage"`
}

func (p *OpenAIProvider) buildRequest(req CompletionRequest, streamMode bool) openAIChatRequest {
	model := req.Config.Model
	if model == "" || model == "default" {
		model = p.Model
	}

	msgs := make([]openAIChatMessage, 0, len(req.Messages)+1)
	if req.System != "" {
		msgs = append(msgs, openAIChatMessage{Role: "system", Content: req.System})
	}
	for _, m := range req.Messages {
		msgs = append(msgs, openAIChatMessage{Role: m.Role, Content: m.Content})
	}

	temp := req.Config.Temperature
	if temp == 0 {
		temp = 0.2
	}

	maxTokens := req.Config.MaxTokens
	if maxTokens == 0 {
		maxTokens = 4096
	}

	return openAIChatRequest{
		Model:       model,
		Messages:    msgs,
		Temperature: temp,
		MaxTokens:   maxTokens,
		Stream:      streamMode,
	}
}

func (p *OpenAIProvider) Complete(ctx context.Context, req CompletionRequest) (CompletionResponse, error) {
	chatReq := p.buildRequest(req, false)
	reqBody, err := json.Marshal(chatReq)
	if err != nil {
		return CompletionResponse{}, err
	}

	url := p.BaseURL + "/chat/completions"
	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(reqBody))
	if err != nil {
		return CompletionResponse{}, err
	}

	httpReq.Header.Set("Content-Type", "application/json")
	if p.APIKey != "" {
		if strings.EqualFold(p.APIHeader, "authorization") && !strings.HasPrefix(strings.ToLower(p.APIKey), "bearer ") {
			httpReq.Header.Set(p.APIHeader, "Bearer "+p.APIKey)
		} else {
			httpReq.Header.Set(p.APIHeader, p.APIKey)
		}
	}

	resp, err := p.client.Do(httpReq)
	if err != nil {
		return CompletionResponse{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return CompletionResponse{}, fmt.Errorf("openai request failed with status %d: %s", resp.StatusCode, string(body))
	}

	var chatResp openAIChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		return CompletionResponse{}, err
	}

	var content string
	if len(chatResp.Choices) > 0 {
		content = chatResp.Choices[0].Message.Content
	}
	tokens := chatResp.Usage.TotalTokens
	if tokens == 0 {
		tokens = len(content)
	}

	return CompletionResponse{
		ContentJSON: content,
		TokensUsed:  tokens,
	}, nil
}

func (p *OpenAIProvider) CompleteStream(ctx context.Context, req CompletionRequest, sink stream.Sink) (CompletionResponse, error) {
	chatReq := p.buildRequest(req, true)
	reqBody, err := json.Marshal(chatReq)
	if err != nil {
		return CompletionResponse{}, err
	}

	url := p.BaseURL + "/chat/completions"
	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(reqBody))
	if err != nil {
		return CompletionResponse{}, err
	}

	httpReq.Header.Set("Content-Type", "application/json")
	if p.APIKey != "" {
		if strings.EqualFold(p.APIHeader, "authorization") && !strings.HasPrefix(strings.ToLower(p.APIKey), "bearer ") {
			httpReq.Header.Set(p.APIHeader, "Bearer "+p.APIKey)
		} else {
			httpReq.Header.Set(p.APIHeader, p.APIKey)
		}
	}

	resp, err := p.client.Do(httpReq)
	if err != nil {
		return CompletionResponse{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return CompletionResponse{}, fmt.Errorf("openai stream failed with status %d: %s", resp.StatusCode, string(body))
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
		if data == "[DONE]" {
			break
		}

		var chunk openAIChatResponse
		if err := json.Unmarshal([]byte(data), &chunk); err == nil {
			if len(chunk.Choices) > 0 && chunk.Choices[0].Delta.Content != "" {
				delta := chunk.Choices[0].Delta.Content
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

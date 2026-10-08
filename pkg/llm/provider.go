package llm

import (
	"context"

	"github.com/wdvn/tars/pkg/stream"
)

// RequestConfig specifies completion parameters for a single call.
type RequestConfig struct {
	Model       string  `json:"model,omitempty"`
	Temperature float64 `json:"temperature,omitempty"`
	MaxTokens   int     `json:"max_tokens,omitempty"`
}

// Message represents a conversational turn in LLM requests.
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// CompletionRequest holds full parameters for non-streaming or streaming completion.
type CompletionRequest struct {
	Config       RequestConfig `json:"config"`
	System       string        `json:"system"`
	Messages     []Message     `json:"messages"`
	OutputSchema string        `json:"output_schema"`
}

// CompletionResponse returns the LLM response and token accounting.
type CompletionResponse struct {
	ContentJSON string `json:"content_json"`
	TokensUsed  int    `json:"tokens_used"`
}

// Provider represents any LLM execution backend (OpenAI, Anthropic, Ollama, Stub).
type Provider interface {
	Complete(ctx context.Context, req CompletionRequest) (CompletionResponse, error)
	CompleteStream(ctx context.Context, req CompletionRequest, sink stream.Sink) (CompletionResponse, error)
}

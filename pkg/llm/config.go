package llm

import (
	"os"
	"strconv"
	"strings"
)

const (
	DefaultOllamaHost  = "http://127.0.0.1:11434"
	DefaultOllamaModel = "qwen2.5:0.5b"
	AltOllamaModel     = "deepseek-r1:0.5b"
)

// Config holds global runtime LLM parameters.
type Config struct {
	MaxTokens    int
	SystemPrompt string
}

// LoadConfig loads runtime configuration from environment or file.
func LoadConfig() Config {
	cfg := Config{
		MaxTokens: 8192,
	}

	if raw := GetFirstEnv("TARS_MAX_TOKENS", "MINI_MAX_TOKENS"); raw != "" {
		if val, err := strconv.Atoi(strings.TrimSpace(raw)); err == nil && val > 0 {
			cfg.MaxTokens = val
		}
	}

	if sysPath := GetFirstEnv("TARS_SYSTEM_FILE", "MINI_SYSTEM_FILE"); sysPath != "" {
		if data, err := os.ReadFile(sysPath); err == nil && len(data) > 0 {
			cfg.SystemPrompt = string(data)
		}
	}

	return cfg
}

// OpenAICompat holds parameters for calling OpenAI or an OpenAI-compatible endpoint.
type OpenAICompat struct {
	BaseURL    string
	APIKey     string
	APIHeader  string
	Model      string
	FromOllama bool
}

// LoadOpenAICompat resolves OpenAI-compatible endpoint configuration.
func LoadOpenAICompat(requireExplicitURL bool) *OpenAICompat {
	url := GetFirstEnv("OPENAI_COMPAT_URL", "OPENAI_BASE_URL")
	key := GetFirstEnv("OPENAI_COMPAT_API_KEY", "OPENAI_API_KEY")

	if requireExplicitURL && url == "" {
		return nil
	}
	if url == "" && key == "" {
		return nil
	}

	baseURL := strings.TrimRight(url, "/")
	if baseURL == "" {
		baseURL = "https://api.openai.com/v1"
	}

	header := GetFirstEnv("OPENAI_COMPAT_API_HEADER")
	if header == "" {
		header = "Authorization"
	}

	model := GetFirstEnv("OPENAI_COMPAT_MODEL", "OPENAI_MODEL")
	if model == "" {
		model = "gpt-4o-mini"
	}

	return &OpenAICompat{
		BaseURL:    baseURL,
		APIKey:     key,
		APIHeader:  header,
		Model:      model,
		FromOllama: false,
	}
}

// LoadOllamaCompat resolves Ollama OpenAI-compatible endpoint (/v1).
func LoadOllamaCompat() *OpenAICompat {
	host := OllamaHost()
	model := GetFirstEnv("TARS_LLM_MODEL", "MINI_LLM_MODEL")
	if model == "" {
		model = DefaultOllamaModel
	}

	return &OpenAICompat{
		BaseURL:    strings.TrimRight(host, "/") + "/v1",
		APIKey:     "ollama",
		APIHeader:  "Authorization",
		Model:      model,
		FromOllama: true,
	}
}

// OllamaHost returns the configured Ollama host URL.
func OllamaHost() string {
	if host := GetFirstEnv("OLLAMA_HOST", "OLLAMA_BASE_URL"); host != "" {
		return strings.TrimRight(host, "/")
	}
	return DefaultOllamaHost
}

// LLMAutoPullEnabled checks if auto-pulling LLM models in Ollama is enabled.
func LLMAutoPullEnabled() bool {
	val := GetFirstEnv("TARS_LLM_AUTO_PULL", "MINI_LLM_AUTO_PULL")
	if val == "" {
		return true
	}
	trimmed := strings.TrimSpace(val)
	return trimmed != "0" && strings.ToLower(trimmed) != "false"
}

// GetFirstEnv retrieves the first non-empty environment variable among candidates.
func GetFirstEnv(keys ...string) string {
	for _, k := range keys {
		if v := os.Getenv(k); v != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

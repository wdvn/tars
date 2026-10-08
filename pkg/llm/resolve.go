package llm

import (
	"context"
	"strings"
)

var (
	activeRuntimeConfig *Config
)

// RuntimeConfig returns the currently active runtime Config if loaded.
func RuntimeConfig() *Config {
	return activeRuntimeConfig
}

// Resolve resolves the active LLM Provider according to environment configuration.
// Resolution order:
// 1. TARS_LLM_PROVIDER override (openai, anthropic, ollama, stub)
// 2. Ollama local (default qwen2.5:0.5b)
// 3. OPENAI_COMPAT_URL / OPENAI_BASE_URL (explicit endpoint)
// 4. ANTHROPIC_API_KEY
// 5. stub
func Resolve(ctx context.Context) (Provider, string, error) {
	_ = NewDotEnv()

	cfg := LoadConfig()
	activeRuntimeConfig = &cfg

	choice := strings.ToLower(strings.TrimSpace(GetFirstEnv("TARS_LLM_PROVIDER")))
	switch choice {
	case "openai":
		compat := LoadOpenAICompat(false)
		if compat != nil {
			return NewOpenAIProvider(compat), "openai", nil
		}
	case "anthropic", "claude":
		return NewAnthropicProvider(), "anthropic", nil
	case "ollama":
		compat := LoadOllamaCompat()
		return NewOpenAIProvider(compat), "ollama", nil
	case "stub":
		return NewStubProvider(), "stub", nil
	}

	// Auto-detect if no explicit TARS_LLM_PROVIDER
	if compat := LoadOpenAICompat(true); compat != nil {
		return NewOpenAIProvider(compat), "openai", nil
	}
	if antKey := GetFirstEnv("ANTHROPIC_API_KEY"); antKey != "" {
		return NewAnthropicProvider(), "anthropic", nil
	}

	// Default to Ollama
	compat := LoadOllamaCompat()
	return NewOpenAIProvider(compat), "ollama", nil
}

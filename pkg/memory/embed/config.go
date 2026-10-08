package embed

import (
	"os"
	"strconv"
	"strings"
)

const (
	DefaultOllamaHost  = "http://127.0.0.1:11434"
	DefaultEmbedModel  = "qwen3-embedding:0.6b"
	DefaultDimension   = 384
)

// Config manages embedding backend configuration.
type Config struct {
	Provider   string
	OllamaHost string
	Model      string
	Dimension  int
	AutoPull   bool
}

// LoadConfig loads embedding configuration from environment variables.
func LoadConfig() Config {
	host := os.Getenv("TARS_EMBED_HOST")
	if host == "" {
		host = os.Getenv("OLLAMA_HOST")
	}
	if host == "" {
		host = DefaultOllamaHost
	}
	host = strings.TrimRight(host, "/")

	model := os.Getenv("TARS_EMBED_MODEL")
	if model == "" {
		model = DefaultEmbedModel
	}

	provider := os.Getenv("TARS_EMBED_PROVIDER")
	if provider == "" {
		provider = "ollama"
	}

	dim := DefaultDimension
	if rawDim := os.Getenv("TARS_EMBED_DIM"); rawDim != "" {
		if val, err := strconv.Atoi(strings.TrimSpace(rawDim)); err == nil && val > 0 {
			dim = val
		}
	}

	autoPull := true
	if rawPull := os.Getenv("TARS_EMBED_AUTO_PULL"); rawPull != "" {
		trimmed := strings.ToLower(strings.TrimSpace(rawPull))
		if trimmed == "0" || trimmed == "false" {
			autoPull = false
		}
	}

	return Config{
		Provider:   provider,
		OllamaHost: host,
		Model:      model,
		Dimension:  dim,
		AutoPull:   autoPull,
	}
}

func (c Config) ResolvedProvider() string {
	return strings.ToLower(c.Provider)
}

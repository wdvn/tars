package embed

import (
	"context"
	"math"
	"strings"
)

// Embedder generates dense vectors from text inputs.
type Embedder interface {
	Embed(text string) ([]float32, error)
}

var activeConfig *Config

// RuntimeConfig returns the loaded embedding config.
func RuntimeConfig() *Config {
	return activeConfig
}

// Dimension returns vector dimension.
func Dimension() int {
	if activeConfig != nil {
		return activeConfig.Dimension
	}
	return DefaultDimension
}

// Resolve resolves the active Embedder based on configuration.
func Resolve(ctx context.Context) (Embedder, error) {
	cfg := LoadConfig()
	activeConfig = &cfg

	prov := strings.ToLower(cfg.Provider)
	if prov == "hash" {
		return NewHashEmbedder(cfg.Dimension), nil
	}

	if prov == "ollama" {
		if cfg.AutoPull && !ModelPresent(cfg.OllamaHost, cfg.Model) {
			_ = PullModel(cfg.OllamaHost, cfg.Model)
		}
		return NewOllamaEmbedder(cfg.OllamaHost, cfg.Model), nil
	}

	return NewHashEmbedder(cfg.Dimension), nil
}

// CosineSimilarity computes cosine similarity between two float32 slices.
func CosineSimilarity(a, b []float32) float64 {
	if len(a) == 0 || len(b) == 0 || len(a) != len(b) {
		return 0
	}

	var dot, normA, normB float64
	for i := range a {
		va := float64(a[i])
		vb := float64(b[i])
		dot += va * vb
		normA += va * va
		normB += vb * vb
	}

	denom := math.Sqrt(normA) * math.Sqrt(normB)
	if denom == 0 {
		return 0
	}
	return dot / denom
}

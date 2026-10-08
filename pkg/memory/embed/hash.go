package embed

import (
	"hash/fnv"
	"math"
)

// HashEmbedder generates deterministic mock embeddings for offline use.
type HashEmbedder struct {
	dim int
}

func NewHashEmbedder(dim int) *HashEmbedder {
	if dim <= 0 {
		dim = DefaultDimension
	}
	return &HashEmbedder{dim: dim}
}

// Embed produces a normalized vector from input text.
func (h *HashEmbedder) Embed(text string) ([]float32, error) {
	vec := make([]float32, h.dim)
	if text == "" {
		return vec, nil
	}

	// Pseudo-random generation based on FNV hash
	hasher := fnv.New64a()
	_, _ = hasher.Write([]byte(text))
	baseHash := hasher.Sum64()

	var normSq float64
	for i := 0; i < h.dim; i++ {
		// Linear congruential derivation from base hash
		v := float64((baseHash + uint64(i)*2654435761) % 10000) / 10000.0
		vec[i] = float32(v - 0.5)
		normSq += float64(vec[i] * vec[i])
	}

	norm := math.Sqrt(normSq)
	if norm > 0 {
		for i := 0; i < h.dim; i++ {
			vec[i] = float32(float64(vec[i]) / norm)
		}
	}

	return vec, nil
}

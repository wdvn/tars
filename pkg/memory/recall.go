package memory

import (
	"context"
	"encoding/json"
	"sort"
	"strings"

	"github.com/wdvn/tars/pkg/memory/embed"
	"github.com/wdvn/tars/pkg/metrics"
)

// Hit represents a recalled episodic memory item with similarity score.
type Hit struct {
	Score   float64 `json:"score"`
	Content string  `json:"content"`
	Meta    string  `json:"meta"`
}

// Recall performs semantic vector similarity search against stored episodic memory.
func Recall(store *Store, query string, k int) ([]Hit, error) {
	metrics.GInc("memory.recall.queries", 1)

	if k <= 0 {
		k = 3
	}

	embedder, err := embed.Resolve(context.Background())
	if err != nil {
		return nil, err
	}

	queryVec, err := embedder.Embed(query)
	if err != nil {
		// Fallback to hash embedder if Ollama failed
		hashEmb := embed.NewHashEmbedder(embed.Dimension())
		queryVec, _ = hashEmb.Embed(query)
	}

	raw, err := store.QueryAllEpisodes()
	if err != nil {
		return nil, err
	}

	lines := strings.Split(raw, "\n")
	var hits []Hit

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}

		parts := strings.SplitN(trimmed, "|", 4)
		if len(parts) < 4 {
			continue
		}

		content := parts[1]
		meta := parts[2]
		embJSON := parts[3]

		var vec []float32
		if err := json.Unmarshal([]byte(embJSON), &vec); err != nil || len(vec) == 0 {
			continue
		}

		score := embed.CosineSimilarity(queryVec, vec)
		hits = append(hits, Hit{
			Score:   score,
			Content: content,
			Meta:    meta,
		})
	}

	sort.Slice(hits, func(i, j int) bool {
		return hits[i].Score > hits[j].Score
	})

	if len(hits) > k {
		hits = hits[:k]
	}

	metrics.GInc("memory.recall.hits", float64(len(hits)))
	if len(hits) > 0 {
		metrics.GSet("memory.recall.top_score", hits[0].Score)
	}

	return hits, nil
}

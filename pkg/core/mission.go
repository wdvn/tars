package core

import (
	"context"
	"encoding/json"
	"time"

	"github.com/wdvn/tars/pkg/memory"
	"github.com/wdvn/tars/pkg/memory/embed"
	"github.com/wdvn/tars/pkg/metrics"
	"github.com/wdvn/tars/pkg/types"
)

// DefaultContext creates a MissionContext in initial ORIENT state.
func DefaultContext(missionID, goal string) types.MissionContext {
	return types.MissionContext{
		MissionID: missionID,
		Goal:      goal,
		Phase:     types.PhaseOrient,
		Status:    types.StatusOrient,
		Priority:  types.PriorityNormal,
		Evidence:  "{}",
	}
}

// WriteEpisodeFromOutcome stores episodic memory along with its embedding.
func WriteEpisodeFromOutcome(
	store *memory.Store,
	missionID, agent, content string,
	tags []string,
) error {
	embedder, err := embed.Resolve(context.Background())
	var vec []float32
	if err == nil {
		vec, _ = embedder.Embed(content)
	}
	if len(vec) == 0 {
		hashEmb := embed.NewHashEmbedder(embed.Dimension())
		vec, _ = hashEmb.Embed(content)
	}

	metaObj := map[string]any{
		"tags":      tags,
		"embedding": vec,
	}
	metaBytes, _ := json.Marshal(metaObj)

	now := time.Now().Unix()
	mid := missionID
	err = store.WriteEpisode(&mid, agent, content, string(metaBytes), now)
	if err == nil {
		metrics.GInc("memory.episodes.written", 1)
	}
	return err
}

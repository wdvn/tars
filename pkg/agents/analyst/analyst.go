package analyst

import (
	"context"
	"time"

	"github.com/wdvn/tars/pkg/agents/analyst/reasoning"
	"github.com/wdvn/tars/pkg/llm"
	"github.com/wdvn/tars/pkg/memory"
	"github.com/wdvn/tars/pkg/metrics"
	"github.com/wdvn/tars/pkg/types"
)

// Analyst coordinates reasoning blocks during ORIENT, ASSESS, and PLAN phases.
type Analyst struct {
	store    *memory.Store
	provider llm.Provider
}

// NewAnalyst initializes an Analyst agent.
func NewAnalyst(store *memory.Store, provider llm.Provider) *Analyst {
	return &Analyst{
		store:    store,
		provider: provider,
	}
}

// RunPhase executes all reasoning blocks registered for the current mission phase.
func (a *Analyst) RunPhase(ctx context.Context, mctx *types.MissionContext) ([]types.BlockResult, error) {
	blocks := reasoning.AllBlocks()
	var results []types.BlockResult
	now := time.Now().Unix()

	for _, b := range blocks {
		if b.Phase() != mctx.Phase {
			continue
		}

		res, err := b.Invoke(ctx, a.provider, mctx)
		if err != nil {
			return results, err
		}

		metrics.GInc("analyst.blocks.invoked", 1)
		results = append(results, res)

		_ = a.store.WriteArtifact(
			mctx.MissionID,
			mctx.Phase.Name(),
			types.AgentAnalyst.Name(),
			res.Kind,
			res.PayloadJSON,
			now,
		)
		metrics.GInc("analyst.artifacts.written", 1)
	}

	if mctx.Phase == types.PhasePlan {
		for _, r := range results {
			if r.Kind == "plan" {
				_ = a.store.PublishBusEvent(
					mctx.MissionID,
					"analyst",
					"executor",
					"plan_ready",
					r.PayloadJSON,
					now,
				)
				metrics.GInc("bus.events.published", 1)
				break
			}
		}
	}

	return results, nil
}

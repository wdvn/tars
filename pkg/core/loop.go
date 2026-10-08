package core

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/wdvn/tars/pkg/agents/analyst"
	"github.com/wdvn/tars/pkg/agents/executor"
	"github.com/wdvn/tars/pkg/agents/monitor"
	"github.com/wdvn/tars/pkg/llm"
	"github.com/wdvn/tars/pkg/memory"
	"github.com/wdvn/tars/pkg/metrics"
	"github.com/wdvn/tars/pkg/perception"
	"github.com/wdvn/tars/pkg/stream"
	"github.com/wdvn/tars/pkg/types"
)

// LoopConfig governs autonomous loop execution limits and inputs.
type LoopConfig struct {
	MaxIterations   int
	VerifyCommands  []string
	PerceptionPaths []string
	RepoRoot        string
}

// DefaultLoopConfig returns default loop settings.
func DefaultLoopConfig() LoopConfig {
	return LoopConfig{
		MaxIterations:   8,
		VerifyCommands:  []string{},
		PerceptionPaths: []string{"build.zig", "src/root.zig"},
		RepoRoot:        ".",
	}
}

// LoopResult reports final outcome of an autonomous run.
type LoopResult struct {
	Iterations  int
	FinalStatus types.MissionStatus
	LastVerify  *types.VerifyOutcome
}

// RunAutonomous drives the OODA cycle until completion or max iterations.
func RunAutonomous(
	ctx context.Context,
	store *memory.Store,
	provider llm.Provider,
	sink stream.Sink,
	cfg LoopConfig,
	mctx *types.MissionContext,
	plan *types.ApprovedPlan,
) (LoopResult, error) {
	if cfg.MaxIterations <= 0 {
		cfg.MaxIterations = 8
	}
	if cfg.RepoRoot == "" {
		cfg.RepoRoot = "."
	}

	analystAgent := analyst.NewAnalyst(store, provider)
	execAgent := executor.NewExecutor(store)
	monAgent := monitor.NewMonitor(store)

	iteration := 0
	var lastVerify *types.VerifyOutcome
	effectiveRollback := plan.Rollback

	for iteration < cfg.MaxIterations {
		metrics.GInc("mission.phase.entered", 1)
		if sink != nil {
			_ = sink.Emit(stream.Chunk{Kind: stream.ChunkPhase, Text: mctx.Phase.Name()})
		}
		start := time.Now()

		// ORIENT: combine codebase perception with semantic recall into JSON evidence
		if mctx.Phase == types.PhaseOrient {
			evidence, _ := perception.GatherEvidence(cfg.RepoRoot, cfg.PerceptionPaths)
			hits, _ := memory.Recall(store, mctx.Goal, 3)

			var evMap map[string]any
			if err := json.Unmarshal([]byte(evidence), &evMap); err != nil {
				evMap = make(map[string]any)
			}
			if len(hits) > 0 {
				evMap["recall"] = hits
			}
			evBytes, _ := json.Marshal(evMap)
			mctx.Evidence = string(evBytes)
		}

		// ORIENT, ASSESS, PLAN: Analyst executes reasoning blocks
		if mctx.Phase == types.PhaseOrient || mctx.Phase == types.PhaseAssess || mctx.Phase == types.PhasePlan {
			results, err := analystAgent.RunPhase(ctx, mctx)
			if err != nil {
				// Continue on reasoning block soft failure
			}

			if mctx.Phase == types.PhasePlan {
				if rb, err := LoadLatestRollback(store, mctx.MissionID); err == nil && rb != "" {
					effectiveRollback = rb
				} else if plan.Rollback != "" {
					effectiveRollback = plan.Rollback
				}
				_ = results
			}
		}

		// ACT -> VERIFY: Executor runs plan, Monitor verifies results
		if mctx.Phase == types.PhaseAct {
			outcome, err := execAgent.Execute(ctx, plan, sink, executor.ExecuteOptions{RepoRoot: cfg.RepoRoot})
			if err != nil {
				return LoopResult{
					Iterations:  iteration + 1,
					FinalStatus: types.StatusBlocked,
				}, err
			}

			mctx.Phase = types.PhaseVerify
			mctx.Status = types.StatusVerify

			verifyOut, err := monAgent.Verify(ctx, mctx.MissionID, outcome.Completed, cfg.VerifyCommands)
			if err != nil {
				return LoopResult{
					Iterations:  iteration + 1,
					FinalStatus: types.StatusBlocked,
				}, err
			}
			lastVerify = &verifyOut

			if verifyOut.Pass != nil {
				mctx.Status = types.StatusDone
				metrics.GInc("mission.verify.pass", 1)
				metrics.GInc("mission.iterations", float64(iteration+1))
				durationMs := time.Since(start).Milliseconds()

				if sink != nil {
					_ = sink.Emit(stream.Chunk{Kind: stream.ChunkToken, Text: fmt.Sprintf(" (%dms)", durationMs)})
					_ = sink.Emit(stream.Chunk{Kind: stream.ChunkDone, Text: "mission complete"})
				}

				return LoopResult{
					Iterations:  iteration + 1,
					FinalStatus: types.StatusDone,
					LastVerify:  lastVerify,
				}, nil
			}

			if verifyOut.Fail != nil {
				metrics.GInc("mission.verify.fail", 1)
				execAgent.RollbackCompletedSteps(mctx.MissionID, outcome.Completed, cfg.RepoRoot)

				if effectiveRollback != "" {
					if sink != nil {
						_ = sink.Emit(stream.Chunk{Kind: stream.ChunkPhase, Text: "plan rollback"})
					}
					_, _ = execAgent.RunPlanRollback(ctx, mctx.MissionID, effectiveRollback, cfg.RepoRoot, verifyOut.Fail.Reason)
				}

				mctx.Phase = verifyOut.Fail.TargetPhase
				mctx.Status = types.MissionStatus(mctx.Phase)
				durationMs := time.Since(start).Milliseconds()

				if sink != nil {
					_ = sink.Emit(stream.Chunk{Kind: stream.ChunkToken, Text: fmt.Sprintf(" (failed in %dms)", durationMs)})
					_ = sink.Emit(stream.Chunk{Kind: stream.ChunkPhase, Text: verifyOut.Fail.Reason})
				}

				iteration++
				continue
			}
		}

		durationMs := time.Since(start).Milliseconds()
		if sink != nil {
			_ = sink.Emit(stream.Chunk{Kind: stream.ChunkToken, Text: fmt.Sprintf(" (%dms)", durationMs)})
		}

		mctx.Phase = nextPhase(mctx.Phase)
		mctx.Status = types.MissionStatus(mctx.Phase)
		iteration++
	}

	metrics.GInc("mission.iterations", float64(iteration))
	return LoopResult{
		Iterations:  iteration,
		FinalStatus: mctx.Status,
		LastVerify:  lastVerify,
	}, nil
}

func nextPhase(p types.Phase) types.Phase {
	switch p {
	case types.PhaseOrient:
		return types.PhaseAssess
	case types.PhaseAssess:
		return types.PhasePlan
	case types.PhasePlan:
		return types.PhaseAct
	case types.PhaseAct:
		return types.PhaseVerify
	case types.PhaseVerify:
		return types.PhaseOrient
	default:
		return types.PhaseOrient
	}
}

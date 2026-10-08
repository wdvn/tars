package core

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/wdvn/tars/pkg/agents/analyst"
	"github.com/wdvn/tars/pkg/agents/executor"
	"github.com/wdvn/tars/pkg/agents/monitor"
	"github.com/wdvn/tars/pkg/llm"
	"github.com/wdvn/tars/pkg/memory"
	"github.com/wdvn/tars/pkg/metrics"
	"github.com/wdvn/tars/pkg/perception"
	"github.com/wdvn/tars/pkg/session"
	"github.com/wdvn/tars/pkg/stream"
	"github.com/wdvn/tars/pkg/types"
)

// ChatConfig sets parameters for interactive operator turns.
type ChatConfig struct {
	RepoRoot        string
	PerceptionPaths []string
}

// DefaultChatConfig returns standard chat turn configuration.
func DefaultChatConfig() ChatConfig {
	return ChatConfig{
		RepoRoot:        ".",
		PerceptionPaths: []string{"README.md", "docs/vi/README.md"},
	}
}

// TurnResult encapsulates chat reply and verification metadata.
type TurnResult struct {
	Response string
	Verified bool
	Streamed bool
}

const verifyInstruction = `Answer the operator using [verified_evidence] and memory context blocks.
If evidence is present, stick strictly to the evidence and do not invent facts.
If no tools were executed, answer the query naturally using conversational context or general knowledge.`

// RunTurn processes one operator chat message through tri-agent verification.
func RunTurn(
	ctx context.Context,
	store *memory.Store,
	sess *session.Session,
	provider llm.Provider,
	sink stream.Sink,
	query string,
	pack *memory.ContextPack,
	cfg ChatConfig,
) (TurnResult, error) {
	if cfg.RepoRoot == "" {
		cfg.RepoRoot = "."
	}

	evidence := buildChatEvidence(store, query, pack, cfg)
	mctx := DefaultContext(sess.ID, query)
	mctx.Evidence = evidence

	analystAgent := analyst.NewAnalyst(store, provider)
	execAgent := executor.NewExecutor(store)
	monAgent := monitor.NewMonitor(store)

	ooda := []types.Phase{types.PhaseOrient, types.PhaseAssess, types.PhasePlan}
	var planJSON string

	for _, phase := range ooda {
		mctx.Phase = phase
		metrics.GInc("mission.phase.entered", 1)
		if sink != nil {
			_ = sink.Emit(stream.Chunk{Kind: stream.ChunkPhase, Text: phase.Name()})
		}
		start := time.Now()

		results, err := analystAgent.RunPhase(ctx, &mctx)
		durationMs := time.Since(start).Milliseconds()

		if err != nil {
			if sink != nil {
				_ = sink.Emit(stream.Chunk{Kind: stream.ChunkToken, Text: fmt.Sprintf(" (failed in %dms)", durationMs)})
			}
		} else {
			if sink != nil {
				_ = sink.Emit(stream.Chunk{Kind: stream.ChunkToken, Text: fmt.Sprintf(" (%dms)", durationMs)})
			}
			if phase == types.PhasePlan {
				for _, r := range results {
					if r.Kind == "plan" {
						planJSON = r.PayloadJSON
					}
				}
			}
		}
	}

	verified := false
	var verifiedBlock string

	if planJSON != "" {
		if approvedPlan, err := FromPlannerJSON(sess.ID, planJSON); err == nil && len(approvedPlan.Steps) > 0 {
			metrics.GInc("mission.phase.entered", 1)
			if sink != nil {
				_ = sink.Emit(stream.Chunk{Kind: stream.ChunkPhase, Text: "act"})
			}
			actStart := time.Now()

			outcome, err := execAgent.Execute(ctx, approvedPlan, sink, executor.ExecuteOptions{RepoRoot: cfg.RepoRoot})
			actDurationMs := time.Since(actStart).Milliseconds()

			if err != nil {
				if sink != nil {
					_ = sink.Emit(stream.Chunk{Kind: stream.ChunkToken, Text: fmt.Sprintf(" (failed in %dms)", actDurationMs)})
				}
				verifiedBlock = "Executor failed to run plan steps."
				return synthesizeResponse(ctx, provider, sink, pack, query, verifiedBlock, false)
			}

			if sink != nil {
				_ = sink.Emit(stream.Chunk{Kind: stream.ChunkToken, Text: fmt.Sprintf(" (%dms)", actDurationMs)})
			}

			metrics.GInc("mission.phase.entered", 1)
			if sink != nil {
				_ = sink.Emit(stream.Chunk{Kind: stream.ChunkPhase, Text: "verify"})
			}
			verifyStart := time.Now()

			verifyOut, err := monAgent.Verify(ctx, sess.ID, outcome.Completed, nil)
			verifyDurationMs := time.Since(verifyStart).Milliseconds()

			if err != nil {
				if sink != nil {
					_ = sink.Emit(stream.Chunk{Kind: stream.ChunkToken, Text: fmt.Sprintf(" (failed in %dms)", verifyDurationMs)})
				}
				verifiedBlock = formatActionEvidence(outcome.Completed)
				return synthesizeResponse(ctx, provider, sink, pack, query, verifiedBlock, false)
			}

			if sink != nil {
				_ = sink.Emit(stream.Chunk{Kind: stream.ChunkToken, Text: fmt.Sprintf(" (%dms)", verifyDurationMs)})
			}

			if verifyOut.Pass != nil {
				verified = true
				metrics.GInc("mission.verify.pass", 1)
				verifiedBlock = formatActionEvidence(outcome.Completed)
			} else if verifyOut.Fail != nil {
				metrics.GInc("mission.verify.fail", 1)
				verifiedBlock = fmt.Sprintf("Verify failed: %s\n", verifyOut.Fail.Reason)
			}
		}
	}

	return synthesizeResponse(ctx, provider, sink, pack, query, verifiedBlock, verified)
}

func buildChatEvidence(
	store *memory.Store,
	query string,
	pack *memory.ContextPack,
	cfg ChatConfig,
) string {
	fileEv, _ := perception.GatherEvidence(cfg.RepoRoot, cfg.PerceptionPaths)
	hits, _ := memory.Recall(store, query, 3)

	evMap := map[string]any{
		"memory_context": pack.System,
		"file_snapshot":  fileEv,
		"recall":         hits,
	}
	bytes, _ := json.Marshal(evMap)
	return string(bytes)
}

func formatActionEvidence(results []types.ActionResult) string {
	var sb strings.Builder
	for _, r := range results {
		sb.WriteString(fmt.Sprintf("step %d (%s): ", r.StepIndex, r.Kind.Name()))
		if r.Stdout != "" {
			stdout := r.Stdout
			if len(stdout) > 6000 {
				stdout = stdout[:6000]
			}
			sb.WriteString(stdout)
		} else {
			sb.WriteString("(empty stdout)")
		}
		if r.Stderr != "" {
			stderr := r.Stderr
			if len(stderr) > 512 {
				stderr = stderr[:512]
			}
			sb.WriteString(fmt.Sprintf("\nstderr: %s", stderr))
		}
		sb.WriteString("\n\n")
	}
	return sb.String()
}

func synthesizeResponse(
	ctx context.Context,
	provider llm.Provider,
	sink stream.Sink,
	pack *memory.ContextPack,
	query string,
	verifiedBlock string,
	verified bool,
) (TurnResult, error) {
	if verified && verifiedBlock != "" && !strings.Contains(verifiedBlock, "(empty stdout)") {
		return TurnResult{
			Response: fmt.Sprintf("Verified answer (Monitor PASS):\n%s", verifiedBlock),
			Verified: true,
			Streamed: false,
		}, nil
	}

	var sb strings.Builder
	sb.WriteString(pack.System)
	sb.WriteString("\n\n")
	sb.WriteString(verifyInstruction)

	if verifiedBlock != "" {
		sb.WriteString("\n\n[verified_evidence]\n")
		sb.WriteString(verifiedBlock)
		if verified {
			sb.WriteString("\n(verify: PASS — this block overrides any conflicting memory below)")
		}
	} else {
		sb.WriteString("\n\n[verified_evidence]\n(none — no tool steps executed or verified)")
	}

	maxTokens := 4096
	if rc := llm.RuntimeConfig(); rc != nil && rc.MaxTokens > 0 {
		maxTokens = rc.MaxTokens
	}

	req := llm.CompletionRequest{
		Config:       llm.RequestConfig{MaxTokens: maxTokens},
		System:       sb.String(),
		Messages:     []llm.Message{{Role: "user", Content: query}},
		OutputSchema: "{}",
	}

	resp, err := provider.Complete(ctx, req)
	if err != nil {
		return TurnResult{}, err
	}

	return TurnResult{
		Response: resp.ContentJSON,
		Verified: verified,
		Streamed: false,
	}, nil
}

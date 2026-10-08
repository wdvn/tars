package executor

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/wdvn/tars/pkg/agents/executor/action"
	"github.com/wdvn/tars/pkg/memory"
	"github.com/wdvn/tars/pkg/metrics"
	"github.com/wdvn/tars/pkg/policy"
	"github.com/wdvn/tars/pkg/stream"
	"github.com/wdvn/tars/pkg/types"
)

// ExecuteOptions specifies execution parameters and resumption boundaries.
type ExecuteOptions struct {
	FromStep             int
	RollbackBeforeRetry  bool
	RepoRoot             string
}

// Executor Agent executes approved plans with Safety Guard boundaries.
type Executor struct {
	store *memory.Store
	guard *policy.SafetyGuard
}

// NewExecutor creates an Executor agent.
func NewExecutor(store *memory.Store) *Executor {
	return &Executor{
		store: store,
		guard: policy.NewSafetyGuard(),
	}
}

// Execute drives plan steps through the safety guard and concrete action blocks.
func (e *Executor) Execute(
	ctx context.Context,
	plan *types.ApprovedPlan,
	sink stream.Sink,
	opts ExecuteOptions,
) (types.ExecuteOutcome, error) {
	if len(plan.Steps) == 0 {
		return types.ExecuteOutcome{}, types.ErrInvalidPlan
	}

	steps := plan.Steps
	if len(steps) == 0 {
		return types.ExecuteOutcome{}, types.ErrInvalidPlan
	}

	repoRoot := opts.RepoRoot
	if repoRoot == "" {
		repoRoot = "."
	}

	var completed []types.ActionResult
	now := time.Now().Unix()

	for i, step := range steps {
		if i < opts.FromStep {
			continue
		}

		if opts.RollbackBeforeRetry && i == opts.FromStep {
			_ = RollbackStep(e.store, plan.MissionID, i, repoRoot)
			metrics.GInc("executor.retry.from_step", 1)
		}

		act := types.Action{Kind: step.Kind, Payload: step.Payload}
		metrics.GInc("executor.actions.total", 1)

		verdict := e.guard.Evaluate(act)
		if !verdict.Allowed {
			metrics.GInc("executor.actions.denied", 1)
			d := verdict.Denial

			detail := fmt.Sprintf(`{"step":%d,"boundary":"%s","reason":"%s","alternative":"%s"}`,
				i, d.Boundary, d.Reason, d.Alternative)

			_ = e.store.AppendAudit(plan.MissionID, "executor", "action_denied", detail, now)

			blocked := types.BlockedAction{
				StepIndex:   i,
				Boundary:    d.Boundary,
				Reason:      d.Reason,
				Alternative: d.Alternative,
			}

			_ = e.store.WriteArtifact(
				plan.MissionID,
				types.PhaseAct.Name(),
				types.AgentExecutor.Name(),
				"blocked_action",
				detail,
				now,
			)

			_ = e.store.PublishBusEvent(
				plan.MissionID,
				"executor",
				"monitor",
				"blocked",
				detail,
				now,
			)

			return types.ExecuteOutcome{
				Completed: completed,
				Blocked:   &blocked,
			}, nil
		}

		backupDir, err := PrepareStep(e.store, plan.MissionID, i, step, repoRoot, now)
		if err != nil {
			return types.ExecuteOutcome{Completed: completed}, err
		}

		startedDetail := fmt.Sprintf(`{"step":%d,"kind":"%s","backup_dir":"%s"}`, i, step.Kind.Name(), backupDir)
		_ = e.store.AppendAudit(plan.MissionID, "executor", "action_started", startedDetail, now)

		block := action.BlockForKind(step.Kind)
		if block == nil {
			return types.ExecuteOutcome{Completed: completed}, types.ErrInvalidPlan
		}

		stream.EmitToolStart(sink, step.Kind.Name(), step.Payload)
		start := time.Now()

		result, err := block.Run(ctx, act)
		durationMs := time.Since(start).Milliseconds()
		stream.EmitToolEnd(sink, step.Kind.Name(), result.Success, result.ExitCode, durationMs)

		if err != nil {
			result = types.ActionResult{
				StepIndex: i,
				Kind:      step.Kind,
				Success:   false,
				Stderr:    err.Error(),
				ExitCode:  1,
			}
		}
		result.StepIndex = i

		completed = append(completed, result)
		if result.Success {
			metrics.GInc("executor.actions.success", 1)
		} else {
			metrics.GInc("executor.actions.failed", 1)
		}

		resBytes, _ := json.Marshal(result)
		resJSON := string(resBytes)

		_ = CompleteStep(e.store, plan.MissionID, i, result.Success, resJSON)

		_ = e.store.WriteArtifact(
			plan.MissionID,
			types.PhaseAct.Name(),
			types.AgentExecutor.Name(),
			"action_result",
			resJSON,
			now,
		)
		metrics.GInc("executor.artifacts.written", 1)

		doneDetail := fmt.Sprintf(`{"step":%d,"success":%v,"exit":%d,"backup_dir":"%s"}`,
			i, result.Success, result.ExitCode, backupDir)
		_ = e.store.AppendAudit(plan.MissionID, "executor", "action_completed", doneDetail, now)

		if !result.Success {
			break
		}
	}

	if len(completed) > 0 {
		lastRes := completed[len(completed)-1]
		lastBytes, _ := json.Marshal(lastRes)
		_ = e.store.PublishBusEvent(
			plan.MissionID,
			"executor",
			"monitor",
			"action_done",
			string(lastBytes),
			now,
		)
		metrics.GInc("bus.events.published", 1)
	}

	return types.ExecuteOutcome{Completed: completed}, nil
}

// RollbackCompletedSteps restores executor step checkpoints.
func (e *Executor) RollbackCompletedSteps(missionID string, results []types.ActionResult, repoRoot string) {
	RollbackCompletedSteps(e.store, missionID, results, repoRoot)
}

// RunPlanRollback executes rollback shell instructions.
func (e *Executor) RunPlanRollback(ctx context.Context, missionID, script, repoRoot, reason string) (RollbackResult, error) {
	return RunPlanRollback(ctx, e.store, e.guard, missionID, script, repoRoot, reason)
}

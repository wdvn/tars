package executor

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"time"

	"github.com/wdvn/tars/pkg/memory"
	"github.com/wdvn/tars/pkg/policy"
	"github.com/wdvn/tars/pkg/types"
)

// RollbackResult holds execution outputs from plan rollback script.
type RollbackResult struct {
	Success  bool   `json:"success"`
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
	ExitCode int    `json:"exit_code"`
}

// RollbackCompletedSteps restores executor step checkpoints in reverse order.
func RollbackCompletedSteps(
	store *memory.Store,
	missionID string,
	actionResults []types.ActionResult,
	repoRoot string,
) {
	for i := len(actionResults) - 1; i >= 0; i-- {
		stepIdx := actionResults[i].StepIndex
		_ = RollbackStep(store, missionID, stepIdx, repoRoot)
	}
}

// RunPlanRollback runs Analyst plan.rollback shell script (Safety Guard gated).
func RunPlanRollback(
	ctx context.Context,
	store *memory.Store,
	guard *policy.SafetyGuard,
	missionID string,
	script string,
	repoRoot string,
	reason string,
) (RollbackResult, error) {
	if script == "" {
		return RollbackResult{Success: true}, nil
	}

	act := types.Action{Kind: types.ActionShell, Payload: script}
	verdict := guard.Evaluate(act)
	now := time.Now().Unix()

	if !verdict.Allowed {
		detail := fmt.Sprintf(`{"reason":"%s","script":"%s","blocked":"%s"}`, reason, script, verdict.Denial.Reason)
		_ = store.AppendAudit(missionID, "executor", "plan_rollback_denied", detail, now)
		return RollbackResult{
			Success:  false,
			Stderr:   "Safety Guard denied rollback script: " + verdict.Denial.Reason,
			ExitCode: 1,
		}, nil
	}

	cmd := exec.CommandContext(ctx, "bash", "-c", script)
	cmd.Dir = repoRoot
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	exitCode := 0
	success := true
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = 1
		}
		success = false
	}

	detail := fmt.Sprintf(`{"reason":"%s","script":"%s","success":%v,"exit":%d}`, reason, script, success, exitCode)
	_ = store.AppendAudit(missionID, "executor", "plan_rollback_run", detail, now)

	return RollbackResult{
		Success:  success,
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
		ExitCode: exitCode,
	}, nil
}

package verify

import (
	"bytes"
	"context"
	"encoding/json"
	"os/exec"

	"github.com/wdvn/tars/pkg/types"
)

// Watchdog tracks consecutive failure counts to determine loopback phase.
type Watchdog struct {
	consecutiveFailures int
}

func (w *Watchdog) RecordFailure() int {
	w.consecutiveFailures++
	return w.consecutiveFailures
}

func (w *Watchdog) RecordSuccess() {
	w.consecutiveFailures = 0
}

func (w *Watchdog) LoopBackPhase() types.Phase {
	if w.consecutiveFailures >= 2 {
		return types.PhaseOrient
	}
	return types.PhaseAssess
}

// VerifyCheck records the execution of a verify check command.
type VerifyCheck struct {
	Command  string `json:"command"`
	Passed   bool   `json:"passed"`
	ExitCode int    `json:"exit_code"`
	Output   string `json:"output"`
}

// RunVerifyCheck runs a single verification command.
func RunVerifyCheck(ctx context.Context, cmdStr string) VerifyCheck {
	cmd := exec.CommandContext(ctx, "bash", "-c", cmdStr)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out

	err := cmd.Run()
	exitCode := 0
	passed := true
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = 1
		}
		passed = false
	}

	return VerifyCheck{
		Command:  cmdStr,
		Passed:   passed,
		ExitCode: exitCode,
		Output:   out.String(),
	}
}

// BuildHandoff generates a handoff summary on successful verification.
func BuildHandoff(missionID string, checks []VerifyCheck, stepsCount int) (types.Handoff, error) {
	summary := map[string]any{
		"mission_id":    missionID,
		"status":        "verified",
		"steps_executed": stepsCount,
		"checks_count":  len(checks),
	}
	data, err := json.Marshal(summary)
	if err != nil {
		return types.Handoff{SummaryJSON: "{}"}, err
	}
	return types.Handoff{
		SummaryJSON: string(data),
	}, nil
}

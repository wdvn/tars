package monitor

import (
	"context"
	"fmt"
	"time"

	"github.com/wdvn/tars/pkg/agents/monitor/verify"
	"github.com/wdvn/tars/pkg/memory"
	"github.com/wdvn/tars/pkg/metrics"
	"github.com/wdvn/tars/pkg/types"
)

// Monitor Agent inspects execution artifacts, runs verification, and manages loop-back.
type Monitor struct {
	store    *memory.Store
	watchdog verify.Watchdog
}

// NewMonitor initializes a Monitor agent.
func NewMonitor(store *memory.Store) *Monitor {
	return &Monitor{
		store: store,
	}
}

// Verify evaluates action execution results and runs verify checks.
func (m *Monitor) Verify(
	ctx context.Context,
	missionID string,
	actionResults []types.ActionResult,
	verifyCommands []string,
) (types.VerifyOutcome, error) {
	now := time.Now().Unix()

	// 1. Fail-fast on any failed action result
	for _, r := range actionResults {
		if !r.Success {
			_ = m.watchdog.RecordFailure()
			metrics.GInc("monitor.watchdog.failures", 1)
			metrics.GInc("monitor.verify.fail", 1)

			detail := fmt.Sprintf(`{"step":%d,"exit":%d}`, r.StepIndex, r.ExitCode)
			_ = m.store.AppendAudit(missionID, "monitor", "verify_fail", detail, now)

			loop := types.LoopBack{
				TargetPhase: m.watchdog.LoopBackPhase(),
				Reason:      "executor action failed",
				DetailJSON:  detail,
			}

			_ = m.store.PublishBusEvent(missionID, "monitor", "analyst", "verify_failed", detail, now)
			metrics.GInc("bus.events.published", 1)

			return types.VerifyOutcome{Fail: &loop}, nil
		}
	}

	// 2. Run verify commands
	var checks []verify.VerifyCheck
	for _, cmdStr := range verifyCommands {
		metrics.GInc("monitor.verify.checks", 1)
		check := verify.RunVerifyCheck(ctx, cmdStr)
		checks = append(checks, check)

		if !check.Passed {
			_ = m.watchdog.RecordFailure()
			metrics.GInc("monitor.watchdog.failures", 1)
			metrics.GInc("monitor.verify.fail", 1)

			detail := fmt.Sprintf(`{"command":"%s","exit":%d}`, cmdStr, check.ExitCode)
			_ = m.store.AppendAudit(missionID, "monitor", "verify_fail", detail, now)

			loop := types.LoopBack{
				TargetPhase: types.PhaseAssess,
				Reason:      "verify command failed",
				DetailJSON:  detail,
			}

			_ = m.store.PublishBusEvent(missionID, "monitor", "analyst", "verify_failed", detail, now)
			metrics.GInc("bus.events.published", 1)

			return types.VerifyOutcome{Fail: &loop}, nil
		}
	}

	// 3. All checks passed
	m.watchdog.RecordSuccess()
	metrics.GInc("monitor.verify.pass", 1)

	handoff, err := verify.BuildHandoff(missionID, checks, len(actionResults))
	if err != nil {
		return types.VerifyOutcome{}, err
	}

	_ = m.store.AppendAudit(missionID, "monitor", "verify_pass", handoff.SummaryJSON, now)
	_ = m.store.WriteArtifact(
		missionID,
		types.PhaseVerify.Name(),
		types.AgentMonitor.Name(),
		"handoff",
		handoff.SummaryJSON,
		now,
	)

	_ = m.store.PublishBusEvent(missionID, "monitor", "operator", "verify_passed", handoff.SummaryJSON, now)
	metrics.GInc("bus.events.published", 1)

	return types.VerifyOutcome{Pass: &handoff}, nil
}

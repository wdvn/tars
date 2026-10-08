package core

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/wdvn/tars/pkg/memory"
	"github.com/wdvn/tars/pkg/types"
)

type plannerPayload struct {
	Steps         []string `json:"steps"`
	Rollback      string   `json:"rollback"`
	Contingencies []string `json:"contingencies"`
}

// FromPlannerJSON parses planner block JSON into an ApprovedPlan with step kind mappings.
func FromPlannerJSON(missionID, planJSON string) (*types.ApprovedPlan, error) {
	var payload plannerPayload
	if err := json.Unmarshal([]byte(planJSON), &payload); err != nil {
		return nil, fmt.Errorf("invalid plan json: %w", err)
	}

	var steps []types.ActionStep
	for _, rawStep := range payload.Steps {
		step := strings.TrimSpace(rawStep)
		if step == "" {
			continue
		}

		mapped := mapStep(step)
		steps = append(steps, mapped)
	}

	return &types.ApprovedPlan{
		MissionID: missionID,
		Steps:     steps,
		Rollback:  payload.Rollback,
	}, nil
}

func mapStep(step string) types.ActionStep {
	if strings.HasPrefix(step, "mcp:") {
		return types.ActionStep{
			Kind:    types.ActionMCP,
			Payload: strings.TrimSpace(strings.TrimPrefix(step, "mcp:")),
		}
	}
	if strings.HasPrefix(step, "skill:") {
		return types.ActionStep{
			Kind:    types.ActionSkill,
			Payload: strings.TrimSpace(strings.TrimPrefix(step, "skill:")),
		}
	}
	if strings.HasPrefix(step, "git:") {
		return types.ActionStep{
			Kind:    types.ActionGit,
			Payload: strings.TrimSpace(strings.TrimPrefix(step, "git:")),
		}
	}
	if strings.HasPrefix(step, "grep:") {
		pattern := strings.TrimSpace(strings.TrimPrefix(step, "grep:"))
		cmd := fmt.Sprintf("rg -m 8 -- %s . 2>/dev/null || grep -r -m 8 -- %s . 2>/dev/null || true", pattern, pattern)
		return types.ActionStep{
			Kind:    types.ActionShell,
			Payload: cmd,
		}
	}
	if strings.HasPrefix(step, "shell:") {
		return types.ActionStep{
			Kind:    types.ActionShell,
			Payload: strings.TrimSpace(strings.TrimPrefix(step, "shell:")),
		}
	}
	return types.ActionStep{
		Kind:    types.ActionShell,
		Payload: step,
	}
}

// ExtractRollbackField extracts the rollback script from a plan JSON string.
func ExtractRollbackField(planJSON string) string {
	var payload plannerPayload
	_ = json.Unmarshal([]byte(planJSON), &payload)
	return payload.Rollback
}

// LoadLatestRollback queries the newest plan artifact from SQLite and extracts rollback.
func LoadLatestRollback(store *memory.Store, missionID string) (string, error) {
	payload, err := store.QueryLatestArtifactPayload(missionID, "plan")
	if err != nil {
		return "", err
	}
	return ExtractRollbackField(payload), nil
}

// FromLatestArtifact loads the newest plan artifact for a mission from SQLite.
func FromLatestArtifact(store *memory.Store, missionID string) (*types.ApprovedPlan, error) {
	payload, err := store.QueryLatestArtifactPayload(missionID, "plan")
	if err != nil {
		return nil, err
	}
	return FromPlannerJSON(missionID, payload)
}

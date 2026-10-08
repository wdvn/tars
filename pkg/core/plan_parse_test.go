package core_test

import (
	"testing"

	"github.com/wdvn/tars/pkg/core"
	"github.com/wdvn/tars/pkg/types"
)

func TestFromPlannerJSONValidPlan(t *testing.T) {
	planJSON := `{
  "steps": [
    "git:status",
    "mcp:fetch_data",
    "skill:summarize",
    "shell:echo done"
  ],
  "rollback": "git reset --hard"
}`

	plan, err := core.FromPlannerJSON("m-test", planJSON)
	if err != nil {
		t.Fatalf("unexpected error parsing plan: %v", err)
	}

	if plan.MissionID != "m-test" {
		t.Errorf("expected mission ID m-test, got %s", plan.MissionID)
	}
	if plan.Rollback != "git reset --hard" {
		t.Errorf("expected rollback 'git reset --hard', got %s", plan.Rollback)
	}
	if len(plan.Steps) != 4 {
		t.Fatalf("expected 4 steps, got %d", len(plan.Steps))
	}

	if plan.Steps[0].Kind != types.ActionGit || plan.Steps[0].Payload != "status" {
		t.Errorf("step 0 mismatch: %+v", plan.Steps[0])
	}
	if plan.Steps[1].Kind != types.ActionMCP || plan.Steps[1].Payload != "fetch_data" {
		t.Errorf("step 1 mismatch: %+v", plan.Steps[1])
	}
	if plan.Steps[2].Kind != types.ActionSkill || plan.Steps[2].Payload != "summarize" {
		t.Errorf("step 2 mismatch: %+v", plan.Steps[2])
	}
	if plan.Steps[3].Kind != types.ActionShell || plan.Steps[3].Payload != "echo done" {
		t.Errorf("step 3 mismatch: %+v", plan.Steps[3])
	}
}

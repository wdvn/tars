package types_test

import (
	"testing"

	"github.com/wdvn/tars/pkg/types"
)

func TestAgentNameMapping(t *testing.T) {
	if types.AgentAnalyst.Name() != "analyst" {
		t.Errorf("expected analyst, got %s", types.AgentAnalyst.Name())
	}
	if types.AgentExecutor.Name() != "executor" {
		t.Errorf("expected executor, got %s", types.AgentExecutor.Name())
	}
	if types.AgentMonitor.Name() != "monitor" {
		t.Errorf("expected monitor, got %s", types.AgentMonitor.Name())
	}
}

func TestPhaseNameMapping(t *testing.T) {
	if types.PhaseOrient.Name() != "orient" {
		t.Errorf("expected orient, got %s", types.PhaseOrient.Name())
	}
	if types.PhaseAssess.Name() != "assess" {
		t.Errorf("expected assess, got %s", types.PhaseAssess.Name())
	}
	if types.PhasePlan.Name() != "plan" {
		t.Errorf("expected plan, got %s", types.PhasePlan.Name())
	}
	if types.PhaseAct.Name() != "act" {
		t.Errorf("expected act, got %s", types.PhaseAct.Name())
	}
	if types.PhaseVerify.Name() != "verify" {
		t.Errorf("expected verify, got %s", types.PhaseVerify.Name())
	}
}

func TestMissionStatusName(t *testing.T) {
	if types.StatusOrient.Name() != "orient" {
		t.Errorf("expected orient, got %s", types.StatusOrient.Name())
	}
	if types.StatusDone.Name() != "done" {
		t.Errorf("expected done, got %s", types.StatusDone.Name())
	}
	if types.StatusBlocked.Name() != "blocked" {
		t.Errorf("expected blocked, got %s", types.StatusBlocked.Name())
	}
}

func TestActionKindName(t *testing.T) {
	if types.ActionShell.Name() != "shell" {
		t.Errorf("expected shell, got %s", types.ActionShell.Name())
	}
	if types.ActionFileEdit.Name() != "file_edit" {
		t.Errorf("expected file_edit, got %s", types.ActionFileEdit.Name())
	}
	if types.ActionGit.Name() != "git" {
		t.Errorf("expected git, got %s", types.ActionGit.Name())
	}
	if types.ActionVerify.Name() != "verify" {
		t.Errorf("expected verify, got %s", types.ActionVerify.Name())
	}
	if types.ActionMCP.Name() != "mcp" {
		t.Errorf("expected mcp, got %s", types.ActionMCP.Name())
	}
	if types.ActionSkill.Name() != "skill" {
		t.Errorf("expected skill, got %s", types.ActionSkill.Name())
	}
}

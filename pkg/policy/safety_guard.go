// Package policy implements P5 hard safety boundaries for Executor actions.
package policy

import (
	"strings"

	"github.com/wdvn/tars/pkg/metrics"
	"github.com/wdvn/tars/pkg/types"
)

// DenyReason holds structured explanation for a rejected action.
type DenyReason struct {
	Boundary    string `json:"boundary"`
	Reason      string `json:"reason"`
	Alternative string `json:"alternative"`
}

// Verdict represents safety guard decision.
type Verdict struct {
	Allowed bool
	Denial  *DenyReason
}

// SafetyGuard gates actions through strict boundaries before execution.
type SafetyGuard struct{}

// NewSafetyGuard creates a SafetyGuard instance.
func NewSafetyGuard() *SafetyGuard {
	return &SafetyGuard{}
}

// Evaluate evaluates an action against safety boundaries.
func (g *SafetyGuard) Evaluate(action types.Action) Verdict {
	metrics.GInc("safety.guard.evaluations", 1)
	v := g.evaluateInner(action)
	if !v.Allowed {
		metrics.GInc("safety.guard.denials", 1)
	}
	return v
}

func (g *SafetyGuard) evaluateInner(action types.Action) Verdict {
	switch action.Kind {
	case types.ActionShell:
		return g.evaluateShell(action.Payload)
	case types.ActionFileEdit:
		return g.evaluateFileEdit(action.Payload)
	case types.ActionGit:
		return g.evaluateGit(action.Payload)
	case types.ActionVerify, types.ActionMCP, types.ActionSkill:
		return allow()
	default:
		return allow()
	}
}

func (g *SafetyGuard) evaluateShell(command string) Verdict {
	lower := strings.ToLower(command)

	if containsAny(lower, []string{
		"rm -rf /",
		"rm -rf /*",
		"mkfs.",
		":(){ :|:& };:",
	}) {
		return deny(
			"irreversible_data_destruction",
			"command may destroy system data",
			"scope deletion to a specific project path",
		)
	}

	if containsAny(lower, []string{
		"git push --force",
		"git push -f ",
		"push --force origin main",
		"push --force origin master",
	}) {
		return deny(
			"irreversible_data_destruction",
			"force push to main/master is forbidden",
			"use a feature branch and open a PR",
		)
	}

	if containsAny(lower, []string{
		"--no-verify",
		"skip hooks",
		"husky=0",
	}) {
		return deny(
			"security_bypass",
			"skipping git hooks is forbidden",
			"fix hook failures or ask operator to override explicitly",
		)
	}

	if containsAny(lower, []string{
		"git add .env",
		"git add -f .env",
		"credentials.json",
		"id_rsa",
	}) {
		return deny(
			"security_bypass",
			"adding secrets to version control is forbidden",
			"add path to .gitignore and rotate exposed secrets",
		)
	}

	return allow()
}

func (g *SafetyGuard) evaluateFileEdit(payload string) Verdict {
	if strings.Contains(payload, ".env") && !strings.Contains(payload, "gitignore") {
		return deny(
			"security_bypass",
			"editing .env may expose secrets",
			"use environment variables or a secrets manager",
		)
	}
	return allow()
}

func (g *SafetyGuard) evaluateGit(subcommand string) Verdict {
	if strings.HasPrefix(subcommand, "push") &&
		(strings.Contains(subcommand, "--force") || strings.Contains(subcommand, " -f")) {
		return deny(
			"irreversible_data_destruction",
			"force push is forbidden by default",
			"push to a non-protected branch",
		)
	}
	if strings.TrimSpace(subcommand) == "commit" {
		return deny(
			"obedience_boundary",
			"git commit requires explicit operator request",
			"pass approved=true in plan metadata",
		)
	}
	return allow()
}

func containsAny(haystack string, needles []string) bool {
	for _, n := range needles {
		if strings.Contains(haystack, n) {
			return true
		}
	}
	return false
}

func allow() Verdict {
	return Verdict{Allowed: true}
}

func deny(boundary, reason, alternative string) Verdict {
	return Verdict{
		Allowed: false,
		Denial: &DenyReason{
			Boundary:    boundary,
			Reason:      reason,
			Alternative: alternative,
		},
	}
}

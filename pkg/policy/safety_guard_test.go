package policy_test

import (
	"testing"

	"github.com/wdvn/tars/pkg/policy"
	"github.com/wdvn/tars/pkg/types"
)

func TestSafetyGuardAllow(t *testing.T) {
	guard := policy.NewSafetyGuard()

	allowActions := []types.Action{
		{Kind: types.ActionShell, Payload: "ls -la"},
		{Kind: types.ActionShell, Payload: "git status"},
		{Kind: types.ActionFileEdit, Payload: "src/main.go"},
		{Kind: types.ActionGit, Payload: "status --short"},
		{Kind: types.ActionVerify, Payload: "test -f build.zig"},
		{Kind: types.ActionMCP, Payload: "filesystem__read"},
		{Kind: types.ActionSkill, Payload: "list"},
	}

	for _, a := range allowActions {
		v := guard.Evaluate(a)
		if !v.Allowed {
			t.Errorf("expected action %+v to be allowed, got denied: %+v", a, v.Denial)
		}
	}
}

func TestSafetyGuardDenyDestructiveShell(t *testing.T) {
	guard := policy.NewSafetyGuard()

	destructive := []string{
		"rm -rf /",
		"rm -rf /*",
		"mkfs.ext4 /dev/sda",
		":(){ :|:& };:",
		"git push --force origin main",
		"git push -f origin master",
		"git commit -m 'wip' --no-verify",
		"git add .env",
		"cat credentials.json",
	}

	for _, cmd := range destructive {
		v := guard.Evaluate(types.Action{Kind: types.ActionShell, Payload: cmd})
		if v.Allowed {
			t.Errorf("expected command %q to be denied", cmd)
		}
	}
}

func TestSafetyGuardDenyFileEdit(t *testing.T) {
	guard := policy.NewSafetyGuard()

	v := guard.Evaluate(types.Action{Kind: types.ActionFileEdit, Payload: ".env"})
	if v.Allowed {
		t.Errorf("expected edit .env to be denied")
	}

	// Allowed if mentioning gitignore
	v2 := guard.Evaluate(types.Action{Kind: types.ActionFileEdit, Payload: ".gitignore"})
	if !v2.Allowed {
		t.Errorf("expected edit .gitignore to be allowed")
	}
}

func TestSafetyGuardDenyGitCommit(t *testing.T) {
	guard := policy.NewSafetyGuard()

	v := guard.Evaluate(types.Action{Kind: types.ActionGit, Payload: "commit"})
	if v.Allowed {
		t.Errorf("expected git commit to be denied by default")
	}
	if v.Denial.Boundary != "obedience_boundary" {
		t.Errorf("expected obedience_boundary, got %s", v.Denial.Boundary)
	}
}

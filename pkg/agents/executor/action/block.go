package action

import (
	"context"

	"github.com/wdvn/tars/pkg/types"
)

// Block represents an executable tool block in the Executor Agent.
type Block interface {
	ID() string
	Kind() types.ActionKind
	Run(ctx context.Context, act types.Action) (types.ActionResult, error)
}

// BlockForKind returns the appropriate Block for an ActionKind.
func BlockForKind(kind types.ActionKind) Block {
	switch kind {
	case types.ActionShell:
		return &ShellRunner{}
	case types.ActionFileEdit:
		return &FileEditor{}
	case types.ActionGit:
		return &GitOps{}
	case types.ActionMCP:
		return &MCPBridge{}
	case types.ActionSkill:
		return &SkillRunner{}
	default:
		return nil
	}
}

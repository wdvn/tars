package action

import (
	"bytes"
	"context"
	"os/exec"
	"strings"

	"github.com/wdvn/tars/pkg/mcp"
	"github.com/wdvn/tars/pkg/skills"
	"github.com/wdvn/tars/pkg/types"
)

// ShellRunner executes arbitrary shell commands.
type ShellRunner struct{}

func (r *ShellRunner) ID() string             { return "shell_runner" }
func (r *ShellRunner) Kind() types.ActionKind { return types.ActionShell }
func (r *ShellRunner) Run(ctx context.Context, act types.Action) (types.ActionResult, error) {
	cmd := exec.CommandContext(ctx, "bash", "-c", act.Payload)
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

	return types.ActionResult{
		Kind:     types.ActionShell,
		Success:  success,
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
		ExitCode: exitCode,
	}, nil
}

// GitOps executes git subcommands.
type GitOps struct{}

func (g *GitOps) ID() string             { return "git_ops" }
func (g *GitOps) Kind() types.ActionKind { return types.ActionGit }
func (g *GitOps) Run(ctx context.Context, act types.Action) (types.ActionResult, error) {
	cmd := exec.CommandContext(ctx, "bash", "-c", "git "+act.Payload)
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

	return types.ActionResult{
		Kind:     types.ActionGit,
		Success:  success,
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
		ExitCode: exitCode,
	}, nil
}

// FileEditor applies file modifications.
type FileEditor struct{}

func (f *FileEditor) ID() string             { return "file_editor" }
func (f *FileEditor) Kind() types.ActionKind { return types.ActionFileEdit }
func (f *FileEditor) Run(ctx context.Context, act types.Action) (types.ActionResult, error) {
	// Payload can be a path or a bash snippet touching a file
	cmd := exec.CommandContext(ctx, "bash", "-c", act.Payload)
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

	return types.ActionResult{
		Kind:     types.ActionFileEdit,
		Success:  success,
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
		ExitCode: exitCode,
	}, nil
}

// MCPBridge executes Model Context Protocol tools.
type MCPBridge struct{}

func (m *MCPBridge) ID() string             { return "mcp_bridge" }
func (m *MCPBridge) Kind() types.ActionKind { return types.ActionMCP }
func (m *MCPBridge) Run(ctx context.Context, act types.Action) (types.ActionResult, error) {
	client := mcp.ClientFromEnv()

	var toolName, argsJSON string
	if idx := strings.Index(act.Payload, ":"); idx != -1 {
		toolName = strings.TrimSpace(act.Payload[:idx])
		argsJSON = strings.TrimSpace(act.Payload[idx+1:])
	} else {
		toolName = strings.TrimSpace(act.Payload)
	}

	if client != nil {
		res, err := client.CallTool(toolName, argsJSON)
		if err != nil {
			return types.ActionResult{
				Kind:     types.ActionMCP,
				Success:  false,
				Stdout:   "",
				Stderr:   err.Error(),
				ExitCode: 1,
			}, nil
		}
		return types.ActionResult{
			Kind:     types.ActionMCP,
			Success:  true,
			Stdout:   res,
			Stderr:   "",
			ExitCode: 0,
		}, nil
	}

	// Stub fallback
	res := mcp.StubCall(toolName)
	return types.ActionResult{
		Kind:     types.ActionMCP,
		Success:  true,
		Stdout:   res,
		Stderr:   "",
		ExitCode: 0,
	}, nil
}

// SkillRunner loads and executes skills.
type SkillRunner struct{}

func (s *SkillRunner) ID() string             { return "skill_runner" }
func (s *SkillRunner) Kind() types.ActionKind { return types.ActionSkill }
func (s *SkillRunner) Run(ctx context.Context, act types.Action) (types.ActionResult, error) {
	payload := strings.TrimSpace(act.Payload)
	if payload == "list" || payload == "" {
		list, err := skills.ListSkills()
		if err != nil {
			return types.ActionResult{
				Kind:     types.ActionSkill,
				Success:  false,
				Stderr:   err.Error(),
				ExitCode: 1,
			}, nil
		}
		return types.ActionResult{
			Kind:     types.ActionSkill,
			Success:  true,
			Stdout:   list,
			ExitCode: 0,
		}, nil
	}

	content, err := skills.LoadSkill(payload)
	if err != nil {
		return types.ActionResult{
			Kind:     types.ActionSkill,
			Success:  false,
			Stderr:   err.Error(),
			ExitCode: 1,
		}, nil
	}
	return types.ActionResult{
		Kind:     types.ActionSkill,
		Success:  true,
		Stdout:   content,
		ExitCode: 0,
	}, nil
}

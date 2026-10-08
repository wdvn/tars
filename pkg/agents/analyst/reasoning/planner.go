package reasoning

import (
	"context"

	"github.com/wdvn/tars/pkg/llm"
	"github.com/wdvn/tars/pkg/types"
)

const (
	PlannerOutputSchema = `{"type":"object","properties":{"steps":{"type":"array","items":{"type":"string"}},"rollback":{"type":"string"},"contingencies":{"type":"array","items":{"type":"string"}}},"required":["steps","rollback","contingencies"]}`

	PlannerPrompt = `You are the TARS Planner (Analyst Agent). Produce a minimal correct plan to gather evidence before answering.
If the query is a simple greeting, conversational chitchat, or does not require external commands/information, return an EMPTY steps array. Do NOT invent/run any commands.
Use step prefixes: shell: (curl/rg/echo), grep:pattern, mcp:tool:args, skill:name, git:subcommand.
For external facts (weather, release notes, web): plan shell:curl -s … fetch steps.
For codebase facts: plan grep:term or shell:rg … steps.
Include Plan A steps, rollback path, and contingencies. Output strict JSON only.`
)

type PlannerBlock struct{}

func (b *PlannerBlock) ID() string         { return "planner" }
func (b *PlannerBlock) Phase() types.Phase { return types.PhasePlan }
func (b *PlannerBlock) Invoke(ctx context.Context, provider llm.Provider, mctx *types.MissionContext) (types.BlockResult, error) {
	return CompleteJSON(ctx, provider, mctx, PlannerPrompt, PlannerOutputSchema, "plan", 0.2)
}

package reasoning

import (
	"context"
	"fmt"

	"github.com/wdvn/tars/pkg/llm"
	"github.com/wdvn/tars/pkg/types"
)

// Block represents a single cognitive reasoning block in the Analyst Agent.
type Block interface {
	ID() string
	Phase() types.Phase
	Invoke(ctx context.Context, provider llm.Provider, mctx *types.MissionContext) (types.BlockResult, error)
}

// AssembleUserPrompt formats mission context and evidence for LLM input.
func AssembleUserPrompt(mctx *types.MissionContext, outputSchema string) string {
	return fmt.Sprintf(`Mission: %s
Goal: %s
Phase: %s
Evidence:
%s
Respond ONLY with JSON matching:
%s`, mctx.MissionID, mctx.Goal, mctx.Phase.Name(), mctx.Evidence, outputSchema)
}

// CompleteJSON invokes the LLM provider with user prompt and expects structured JSON output.
func CompleteJSON(
	ctx context.Context,
	provider llm.Provider,
	mctx *types.MissionContext,
	systemPrompt string,
	outputSchema string,
	kind string,
	temperature float64,
) (types.BlockResult, error) {
	prompt := AssembleUserPrompt(mctx, outputSchema)

	maxTokens := 4096
	if rc := llm.RuntimeConfig(); rc != nil && rc.MaxTokens > 0 {
		maxTokens = rc.MaxTokens
	}

	req := llm.CompletionRequest{
		Config: llm.RequestConfig{
			Temperature: temperature,
			MaxTokens:   maxTokens,
		},
		System: systemPrompt,
		Messages: []llm.Message{
			{Role: "user", Content: prompt},
		},
		OutputSchema: outputSchema,
	}

	resp, err := provider.Complete(ctx, req)
	if err != nil {
		return types.BlockResult{}, types.ErrLLMFailed
	}

	return types.BlockResult{
		Kind:        kind,
		PayloadJSON: resp.ContentJSON,
	}, nil
}

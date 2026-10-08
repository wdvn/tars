package reasoning

import (
	"context"

	"github.com/wdvn/tars/pkg/llm"
	"github.com/wdvn/tars/pkg/types"
)

const (
	ClassifierOutputSchema = `{"type":"object","properties":{"type":{"type":"string"},"severity":{"type":"string"},"hypothesis":{"type":"array","items":{"type":"string"}}},"required":["type","severity","hypothesis"]}`

	ClassifierOrientPrompt = `You are the TARS Classifier (Analyst Agent). Distinguish symptom from root cause.
Be honest (honesty parameter 90%). Output strict JSON only.`

	ClassifierAssessPrompt = `You are the TARS Classifier (Analyst Agent). Re-evaluate symptom vs root cause with new evidence.
Update severity and hypothesis if ASSESS findings change the picture. Output strict JSON only.`
)

type ClassifierOrientBlock struct{}

func (b *ClassifierOrientBlock) ID() string         { return "classifier" }
func (b *ClassifierOrientBlock) Phase() types.Phase { return types.PhaseOrient }
func (b *ClassifierOrientBlock) Invoke(ctx context.Context, provider llm.Provider, mctx *types.MissionContext) (types.BlockResult, error) {
	return CompleteJSON(ctx, provider, mctx, ClassifierOrientPrompt, ClassifierOutputSchema, "classification", 0.3)
}

type ClassifierAssessBlock struct{}

func (b *ClassifierAssessBlock) ID() string         { return "classifier_reassess" }
func (b *ClassifierAssessBlock) Phase() types.Phase { return types.PhaseAssess }
func (b *ClassifierAssessBlock) Invoke(ctx context.Context, provider llm.Provider, mctx *types.MissionContext) (types.BlockResult, error) {
	return CompleteJSON(ctx, provider, mctx, ClassifierAssessPrompt, ClassifierOutputSchema, "classification", 0.2)
}

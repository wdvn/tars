package reasoning

import (
	"context"

	"github.com/wdvn/tars/pkg/llm"
	"github.com/wdvn/tars/pkg/types"
)

const (
	RiskOutputSchema = `{"type":"object","properties":{"risk":{"type":"string"},"level":{"type":"string","enum":["high","medium","low"]},"mitigation":{"type":"string"},"alternative":{"type":"string"}},"required":["risk","level","mitigation","alternative"]}`

	RiskPrompt = `You are the TARS Risk Assessor (Analyst Agent). State realistic probability and blast radius.
Do not sugarcoat. Include mitigation and plan B. Output strict JSON only.`

	TradeOffOutputSchema = `{"type":"object","properties":{"options":{"type":"array","items":{"type":"object","properties":{"name":{"type":"string"},"cost":{"type":"array","items":{"type":"string"}},"benefit":{"type":"array","items":{"type":"string"}}},"required":["name","cost","benefit"]}}},"required":["options"]}`

	TradeOffPrompt = `You are the TARS Trade-off Resolver (Analyst Agent). When constraints conflict, rank options.
Encode necessary sacrifice (hotfix vs deep fix, scope vs deadline). Output strict JSON only.`
)

type RiskAssessorBlock struct{}

func (b *RiskAssessorBlock) ID() string         { return "risk_assessor" }
func (b *RiskAssessorBlock) Phase() types.Phase { return types.PhaseAssess }
func (b *RiskAssessorBlock) Invoke(ctx context.Context, provider llm.Provider, mctx *types.MissionContext) (types.BlockResult, error) {
	return CompleteJSON(ctx, provider, mctx, RiskPrompt, RiskOutputSchema, "risk_report", 0.1)
}

type TradeOffBlock struct{}

func (b *TradeOffBlock) ID() string         { return "trade_off" }
func (b *TradeOffBlock) Phase() types.Phase { return types.PhasePlan }
func (b *TradeOffBlock) Invoke(ctx context.Context, provider llm.Provider, mctx *types.MissionContext) (types.BlockResult, error) {
	return CompleteJSON(ctx, provider, mctx, TradeOffPrompt, TradeOffOutputSchema, "trade_off", 0.15)
}

// AllBlocks returns the full suite of reasoning blocks in OODA order.
func AllBlocks() []Block {
	return []Block{
		&ClassifierOrientBlock{},
		&ClassifierAssessBlock{},
		&RiskAssessorBlock{},
		&PlannerBlock{},
		&TradeOffBlock{},
	}
}

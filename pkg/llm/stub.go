package llm

import (
	"context"
	"strings"

	"github.com/wdvn/tars/pkg/stream"
)

// StubProvider serves deterministic placeholder responses for testing and fallback.
type StubProvider struct{}

func NewStubProvider() *StubProvider {
	return &StubProvider{}
}

func (s *StubProvider) Complete(ctx context.Context, req CompletionRequest) (CompletionResponse, error) {
	var respJSON string
	if strings.Contains(req.OutputSchema, "rollback") {
		respJSON = `{"steps":["echo stub-plan-step"],"rollback":"echo analyst-plan-rollback","contingencies":["re-run verify"]}`
	} else {
		respJSON = `{"status":"stub","note":"set TARS_LLM_PROVIDER=ollama or OPENAI_COMPAT_URL / ANTHROPIC_API_KEY"}`
	}

	return CompletionResponse{
		ContentJSON: respJSON,
		TokensUsed:  len(respJSON),
	}, nil
}

func (s *StubProvider) CompleteStream(ctx context.Context, req CompletionRequest, sink stream.Sink) (CompletionResponse, error) {
	resp, err := s.Complete(ctx, req)
	if err != nil {
		return resp, err
	}

	if sink != nil {
		for _, r := range resp.ContentJSON {
			_ = sink.Emit(stream.Chunk{
				Kind: stream.ChunkToken,
				Text: string(r),
			})
		}
	}

	return resp, nil
}

package llm

import (
	"context"
	"time"

	"github.com/wdvn/tars/pkg/metrics"
	"github.com/wdvn/tars/pkg/stream"
)

// InstrumentedProvider wraps an LLM Provider with metrics accounting.
type InstrumentedProvider struct {
	inner Provider
}

// InstrumentProvider wraps a Provider with telemetry for latency, requests, errors, and tokens.
func InstrumentProvider(p Provider) Provider {
	if p == nil {
		return nil
	}
	return &InstrumentedProvider{inner: p}
}

func (p *InstrumentedProvider) Complete(ctx context.Context, req CompletionRequest) (CompletionResponse, error) {
	metrics.GInc("llm.requests.total", 1)
	start := time.Now()

	resp, err := p.inner.Complete(ctx, req)
	latencyMs := time.Since(start).Milliseconds()
	metrics.GInc("llm.latency_ms.total", float64(latencyMs))

	if err != nil {
		metrics.GInc("llm.requests.errors", 1)
		return resp, err
	}

	metrics.GInc("llm.tokens.total", float64(resp.TokensUsed))
	return resp, nil
}

func (p *InstrumentedProvider) CompleteStream(ctx context.Context, req CompletionRequest, sink stream.Sink) (CompletionResponse, error) {
	metrics.GInc("llm.requests.total", 1)
	start := time.Now()

	instrumentedSink := &instrumentedStreamSink{inner: sink}
	resp, err := p.inner.CompleteStream(ctx, req, instrumentedSink)
	latencyMs := time.Since(start).Milliseconds()
	metrics.GInc("llm.latency_ms.total", float64(latencyMs))

	if err != nil {
		metrics.GInc("llm.requests.errors", 1)
		return resp, err
	}

	metrics.GInc("llm.tokens.total", float64(resp.TokensUsed))
	return resp, nil
}

type instrumentedStreamSink struct {
	inner stream.Sink
}

func (s *instrumentedStreamSink) Emit(chunk stream.Chunk) error {
	metrics.GInc("llm.stream.chunks", 1)
	if s.inner != nil {
		return s.inner.Emit(chunk)
	}
	return nil
}

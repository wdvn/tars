package stream_test

import (
	"strings"
	"testing"

	"github.com/wdvn/tars/pkg/stream"
)

func TestFormatFromName(t *testing.T) {
	if stream.FromName("plain") != stream.FormatPlain {
		t.Errorf("expected plain, got %s", stream.FromName("plain"))
	}
	if stream.FromName("sse") != stream.FormatSSE {
		t.Errorf("expected sse, got %s", stream.FromName("sse"))
	}
	if stream.FromName("SSE") != stream.FormatSSE {
		t.Errorf("expected sse, got %s", stream.FromName("SSE"))
	}
	if stream.FromName("ndjson") != stream.FormatNDJSON {
		t.Errorf("expected ndjson, got %s", stream.FromName("ndjson"))
	}
	if stream.FromName("unknown") != stream.FormatPlain {
		t.Errorf("expected fallback plain, got %s", stream.FromName("unknown"))
	}
}

func TestEventNameMapping(t *testing.T) {
	if stream.EventName(stream.ChunkToken) != "token" {
		t.Errorf("expected token, got %s", stream.EventName(stream.ChunkToken))
	}
	if stream.EventName(stream.ChunkPhase) != "phase" {
		t.Errorf("expected phase, got %s", stream.EventName(stream.ChunkPhase))
	}
	if stream.EventName(stream.ChunkDone) != "done" {
		t.Errorf("expected done, got %s", stream.EventName(stream.ChunkDone))
	}
	if stream.EventName(stream.ChunkError) != "error" {
		t.Errorf("expected error, got %s", stream.EventName(stream.ChunkError))
	}
}

func TestEncodeSSEAndNDJSON(t *testing.T) {
	sse, err := stream.EncodeSSE(stream.ChunkToken, "hello")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.HasPrefix(sse, "event: token\n") {
		t.Errorf("expected event: token prefix, got: %s", sse)
	}
	if !strings.HasSuffix(sse, "\n\n") {
		t.Errorf("expected \\n\\n suffix, got: %s", sse)
	}

	ndjson, err := stream.EncodeNDJSON(stream.ChunkPhase, "orient")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.HasPrefix(ndjson, `{"type":"phase"`) {
		t.Errorf("expected type: phase prefix, got: %s", ndjson)
	}
	if !strings.HasSuffix(ndjson, "\n") {
		t.Errorf("expected \\n suffix, got: %s", ndjson)
	}
}

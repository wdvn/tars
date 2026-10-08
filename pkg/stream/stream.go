package stream

import (
	"fmt"
	"io"
	"os"
	"sync"

	"github.com/wdvn/tars/pkg/metrics"
)

// ChunkKind classifies streaming output units.
type ChunkKind int

const (
	ChunkToken ChunkKind = iota
	ChunkPhase
	ChunkStep
	ChunkToolStart
	ChunkToolEnd
	ChunkDone
	ChunkError
)

// Chunk represents one emission unit to the operator.
type Chunk struct {
	Kind ChunkKind
	Text string
}

// Sink defines the destination for streaming emissions.
type Sink interface {
	Emit(chunk Chunk) error
}

// StdoutSink writes formatted chunks to standard output.
type StdoutSink struct {
	w  io.Writer
	mu sync.Mutex
}

func NewStdoutSink(w io.Writer) *StdoutSink {
	if w == nil {
		w = os.Stdout
	}
	return &StdoutSink{w: w}
}

func (s *StdoutSink) Emit(chunk Chunk) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	var prefix string
	switch chunk.Kind {
	case ChunkToken:
		prefix = ""
	case ChunkPhase:
		prefix = "\n[phase] "
	case ChunkStep:
		prefix = "\n[step] "
	case ChunkToolStart:
		prefix = "\n[tool] "
	case ChunkToolEnd:
		prefix = "\n[/tool] "
	case ChunkDone:
		prefix = "\n[done] "
	case ChunkError:
		prefix = "\n[error] "
	}

	_, err := fmt.Fprintf(s.w, "%s%s", prefix, chunk.Text)
	if err == nil {
		metrics.GInc("stream.chunks.emitted", 1)
	}
	return err
}

// SSESink emits Server-Sent Events frames.
type SSESink struct {
	w  io.Writer
	mu sync.Mutex
}

func NewSSESink(w io.Writer) *SSESink {
	if w == nil {
		w = os.Stdout
	}
	return &SSESink{w: w}
}

func (s *SSESink) Emit(chunk Chunk) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	frame, err := EncodeSSE(chunk.Kind, chunk.Text)
	if err != nil {
		return err
	}
	_, err = fmt.Fprint(s.w, frame)
	if err == nil {
		metrics.GInc("stream.sse.frames", 1)
		metrics.GInc("stream.chunks.emitted", 1)
	}
	return err
}

// NDJSONSink emits Newline-Delimited JSON objects.
type NDJSONSink struct {
	w  io.Writer
	mu sync.Mutex
}

func NewNDJSONSink(w io.Writer) *NDJSONSink {
	if w == nil {
		w = os.Stdout
	}
	return &NDJSONSink{w: w}
}

func (s *NDJSONSink) Emit(chunk Chunk) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	line, err := EncodeNDJSON(chunk.Kind, chunk.Text)
	if err != nil {
		return err
	}
	_, err = fmt.Fprint(s.w, line)
	if err == nil {
		metrics.GInc("stream.ndjson.lines", 1)
		metrics.GInc("stream.chunks.emitted", 1)
	}
	return err
}

// ResolveStdout creates the appropriate Sink based on environment configuration.
func ResolveStdout() Sink {
	switch ResolveFormat() {
	case FormatSSE:
		return NewSSESink(os.Stdout)
	case FormatNDJSON:
		return NewNDJSONSink(os.Stdout)
	default:
		return NewStdoutSink(os.Stdout)
	}
}

// StepTrace tracks structured execution steps.
type StepTrace struct {
	sink Sink
	step string
}

func BeginStepTrace(sink Sink, step string) *StepTrace {
	if sink != nil {
		_ = sink.Emit(Chunk{Kind: ChunkStep, Text: step})
	}
	return &StepTrace{sink: sink, step: step}
}

func (t *StepTrace) End(detail string) {
	if t.sink != nil && detail != "" {
		_ = t.sink.Emit(Chunk{Kind: ChunkToken, Text: fmt.Sprintf(" (%s)", detail)})
	}
}

// EmitToolStart notifies sink of tool execution commencement.
func EmitToolStart(sink Sink, kind, payload string) {
	if sink != nil {
		_ = sink.Emit(Chunk{Kind: ChunkToolStart, Text: fmt.Sprintf("%s: %s", kind, payload)})
	}
}

// EmitToolEnd notifies sink of tool execution completion.
func EmitToolEnd(sink Sink, kind string, success bool, exitCode int, durationMs int64) {
	if sink != nil {
		status := "ok"
		if !success {
			status = fmt.Sprintf("fail exit=%d", exitCode)
		}
		_ = sink.Emit(Chunk{Kind: ChunkToolEnd, Text: fmt.Sprintf("%s (%s in %dms)", kind, status, durationMs)})
	}
}

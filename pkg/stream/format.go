package stream

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// Format represents output wire format.
type Format string

const (
	FormatPlain  Format = "plain"
	FormatSSE    Format = "sse"
	FormatNDJSON Format = "ndjson"
)

// FromName parses a format string (case-insensitive).
func FromName(name string) Format {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "sse":
		return FormatSSE
	case "ndjson":
		return FormatNDJSON
	default:
		return FormatPlain
	}
}

// ResolveFormat reads TARS_STREAM_FORMAT from environment or defaults to plain.
func ResolveFormat() Format {
	if val := os.Getenv("TARS_STREAM_FORMAT"); val != "" {
		return FromName(val)
	}
	return FormatPlain
}

// EventName returns the stable event name for SSE/NDJSON.
func EventName(kind ChunkKind) string {
	switch kind {
	case ChunkToken:
		return "token"
	case ChunkPhase:
		return "phase"
	case ChunkStep:
		return "step"
	case ChunkToolStart:
		return "tool_start"
	case ChunkToolEnd:
		return "tool_end"
	case ChunkDone:
		return "done"
	case ChunkError:
		return "error"
	default:
		return "token"
	}
}

// EncodeSSE formats a single SSE frame.
func EncodeSSE(kind ChunkKind, text string) (string, error) {
	escaped, err := json.Marshal(text)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("event: %s\ndata: {\"text\":%s}\n\n", EventName(kind), string(escaped)), nil
}

// EncodeNDJSON formats a single NDJSON line.
func EncodeNDJSON(kind ChunkKind, text string) (string, error) {
	escaped, err := json.Marshal(text)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("{\"type\":\"%s\",\"text\":%s}\n", EventName(kind), string(escaped)), nil
}

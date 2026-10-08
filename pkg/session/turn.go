package session

import (
	"bufio"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/wdvn/tars/pkg/llm"
)

// Turn represents a single dialogue utterance in a session.
type Turn struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// ParseTurnsJSON parses newline-delimited JSON rows into a slice of Turn structs.
func ParseTurnsJSON(blob string) ([]Turn, error) {
	var turns []Turn
	scanner := bufio.NewScanner(strings.NewReader(blob))

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		var t Turn
		if err := json.Unmarshal([]byte(line), &t); err != nil {
			return nil, fmt.Errorf("invalid turn json: %w", err)
		}
		if t.Role == "" || t.Content == "" {
			return nil, fmt.Errorf("missing role or content")
		}
		turns = append(turns, t)
	}

	return turns, scanner.Err()
}

// ToLLMMessage maps a persisted session turn to an LLM-compatible Message.
func ToLLMMessage(t Turn) llm.Message {
	if t.Role == "operator" {
		return llm.Message{Role: "user", Content: t.Content}
	}
	if t.Role == "analyst" {
		return llm.Message{Role: "assistant", Content: t.Content}
	}
	return llm.Message{
		Role:    "user",
		Content: fmt.Sprintf("[%s] %s", t.Role, t.Content),
	}
}

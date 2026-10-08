package session_test

import (
	"testing"

	"github.com/wdvn/tars/pkg/session"
)

func TestParseTurnsJSONAndToLLMMessage(t *testing.T) {
	blob := `{"role":"operator","content":"Hello TARS"}
{"role":"analyst","content":"Greetings, Cooper."}
{"role":"monitor","content":"All systems nominal."}`

	turns, err := session.ParseTurnsJSON(blob)
	if err != nil {
		t.Fatalf("unexpected error parsing turns: %v", err)
	}

	if len(turns) != 3 {
		t.Fatalf("expected 3 turns, got %d", len(turns))
	}

	if turns[0].Role != "operator" || turns[0].Content != "Hello TARS" {
		t.Errorf("turn 0 mismatch: %+v", turns[0])
	}

	m0 := session.ToLLMMessage(turns[0])
	if m0.Role != "user" || m0.Content != "Hello TARS" {
		t.Errorf("msg 0 mismatch: %+v", m0)
	}

	m1 := session.ToLLMMessage(turns[1])
	if m1.Role != "assistant" || m1.Content != "Greetings, Cooper." {
		t.Errorf("msg 1 mismatch: %+v", m1)
	}

	m2 := session.ToLLMMessage(turns[2])
	if m2.Role != "user" || m2.Content != "[monitor] All systems nominal." {
		t.Errorf("msg 2 mismatch: %+v", m2)
	}
}

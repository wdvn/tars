package llm_test

import (
	"testing"

	"github.com/wdvn/tars/pkg/llm"
)

func TestDotEnvParseLine(t *testing.T) {
	cases := []struct {
		input string
		expK  string
		expV  string
		expOk bool
	}{
		{"KEY=value", "KEY", "value", true},
		{"export FOO=bar", "FOO", "bar", true},
		{"  SPACED = trimmed  ", "SPACED", "trimmed", true},
		{`QUOTED="hello world"`, "QUOTED", "hello world", true},
		{`SINGLE='single quote'`, "SINGLE", "single quote", true},
		{"# comment", "", "", false},
		{"", "", "", false},
		{"INVALID_LINE", "", "", false},
	}

	for _, c := range cases {
		k, v, ok := llm.ParseDotEnvLine(c.input)
		if ok != c.expOk {
			t.Errorf("input %q: expected ok=%v, got %v", c.input, c.expOk, ok)
		}
		if ok {
			if k != c.expK || v != c.expV {
				t.Errorf("input %q: expected (%q, %q), got (%q, %q)", c.input, c.expK, c.expV, k, v)
			}
		}
	}
}

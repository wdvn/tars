package skills_test

import (
	"strings"
	"testing"

	"github.com/wdvn/tars/pkg/skills"
)

func TestListSkills(t *testing.T) {
	listJSON, err := skills.ListSkills()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.HasPrefix(listJSON, `{"skills":`) {
		t.Errorf("expected JSON with skills array, got: %s", listJSON)
	}
}

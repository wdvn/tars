package metrics_test

import (
	"testing"

	"github.com/wdvn/tars/pkg/metrics"
)

func TestUnitName(t *testing.T) {
	if metrics.UnitCount.Name() != "count" {
		t.Errorf("expected count, got %s", metrics.UnitCount.Name())
	}
	if metrics.UnitBytes.Name() != "bytes" {
		t.Errorf("expected bytes, got %s", metrics.UnitBytes.Name())
	}
	if metrics.UnitTokens.Name() != "tokens" {
		t.Errorf("expected tokens, got %s", metrics.UnitTokens.Name())
	}
	if metrics.UnitMilliseconds.Name() != "milliseconds" {
		t.Errorf("expected milliseconds, got %s", metrics.UnitMilliseconds.Name())
	}
	if metrics.UnitScore.Name() != "score" {
		t.Errorf("expected score, got %s", metrics.UnitScore.Name())
	}
}

func TestFindMetric(t *testing.T) {
	def := metrics.Find("llm.requests.total")
	if def == nil {
		t.Fatal("expected to find llm.requests.total")
	}
	if def.Subsystem != "llm" {
		t.Errorf("expected llm subsystem, got %s", def.Subsystem)
	}
	if def.Unit != metrics.UnitCount {
		t.Errorf("expected count unit, got %s", def.Unit)
	}

	notFound := metrics.Find("non_existent_metric")
	if notFound != nil {
		t.Errorf("expected nil for non existent metric, got %v", notFound)
	}
}

func TestUnitFor(t *testing.T) {
	unit := metrics.UnitFor("llm.tokens.total")
	if unit != metrics.UnitTokens {
		t.Errorf("expected tokens, got %s", unit)
	}

	fallback := metrics.UnitFor("unknown_metric")
	if fallback != metrics.UnitCount {
		t.Errorf("expected fallback count, got %s", fallback)
	}
}

func TestCollector(t *testing.T) {
	m := metrics.New("run-1", "test", "demo")
	if m.RunID != "run-1" {
		t.Errorf("expected run-1, got %s", m.RunID)
	}
	if m.Value("mission.iterations") != 0 {
		t.Errorf("expected 0, got %f", m.Value("mission.iterations"))
	}

	m.Inc("mission.iterations", 1)
	m.Inc("mission.iterations", 2)
	if m.Value("mission.iterations") != 3 {
		t.Errorf("expected 3, got %f", m.Value("mission.iterations"))
	}

	m.Set("memory.recall.top_score", 0.95)
	if m.Value("memory.recall.top_score") != 0.95 {
		t.Errorf("expected 0.95, got %f", m.Value("memory.recall.top_score"))
	}

	metrics.SetGlobal(m)
	metrics.GInc("mission.iterations", 5)
	if m.Value("mission.iterations") != 8 {
		t.Errorf("expected 8, got %f", m.Value("mission.iterations"))
	}
	metrics.SetGlobal(nil)
}

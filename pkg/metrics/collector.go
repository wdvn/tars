package metrics

import (
	"sync"
)

// Metrics manages in-memory operational metrics for a specific command run.
type Metrics struct {
	RunID     string
	Command   string
	Subsystem string

	mu     sync.RWMutex
	values map[string]float64
}

// New creates an initialized Metrics instance.
func New(runID, command, subsystem string) *Metrics {
	return &Metrics{
		RunID:     runID,
		Command:   command,
		Subsystem: subsystem,
		values:    make(map[string]float64),
	}
}

// Inc increments a metric by delta.
func (m *Metrics) Inc(name string, delta float64) {
	if m == nil {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.values[name] += delta
}

// Add is an alias for Inc.
func (m *Metrics) Add(name string, delta float64) {
	m.Inc(name, delta)
}

// Set explicitly sets a metric gauge to value.
func (m *Metrics) Set(name string, value float64) {
	if m == nil {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.values[name] = value
}

// Value returns the recorded value or 0 if unobserved.
func (m *Metrics) Value(name string) float64 {
	if m == nil {
		return 0
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.values[name]
}

// Snapshot returns a copy of all recorded metric values.
func (m *Metrics) Snapshot() map[string]float64 {
	if m == nil {
		return make(map[string]float64)
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	cp := make(map[string]float64, len(m.values))
	for k, v := range m.values {
		cp[k] = v
	}
	return cp
}

// Global handle for cross-module metric instrumentation.
var (
	globalMu sync.RWMutex
	global   *Metrics
)

// SetGlobal sets the active global Metrics instance.
func SetGlobal(m *Metrics) {
	globalMu.Lock()
	defer globalMu.Unlock()
	global = m
}

// Global returns the active global Metrics instance.
func Global() *Metrics {
	globalMu.RLock()
	defer globalMu.RUnlock()
	return global
}

// GInc increments a metric on the global handle if set.
func GInc(name string, delta float64) {
	if g := Global(); g != nil {
		g.Inc(name, delta)
	}
}

// GSet sets a metric gauge on the global handle if set.
func GSet(name string, value float64) {
	if g := Global(); g != nil {
		g.Set(name, value)
	}
}

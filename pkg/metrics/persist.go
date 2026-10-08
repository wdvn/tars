package metrics

import (
	"time"
)

// Store defines persistence operations required for storing metrics runs.
type Store interface {
	QuerySQL(sql string) (string, error)
	BeginMetricRun(runID, command string, startedAt int64, metaJSON string) error
	FinishMetricRun(runID string, finishedAt int64) error
	WriteMetricSample(runID, metric string, value float64, unit, tagsJSON string, createdAt int64) error
}

// Flush persists in-memory counters to SQLite tables.
func Flush(m *Metrics, st Store) error {
	if m == nil || st == nil {
		return nil
	}

	now := time.Now().Unix()
	if err := st.BeginMetricRun(m.RunID, m.Command, now, "{}"); err != nil {
		return err
	}

	snapshot := m.Snapshot()
	for name, val := range snapshot {
		if val == 0 {
			continue
		}
		unit := UnitFor(name)
		_ = st.WriteMetricSample(m.RunID, name, val, unit.Name(), "{}", now)
	}

	return st.FinishMetricRun(m.RunID, now)
}

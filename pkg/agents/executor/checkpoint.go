package executor

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/wdvn/tars/pkg/memory"
	"github.com/wdvn/tars/pkg/types"
)

// PrepareStep prepares a checkpoint backup directory and records a pending checkpoint.
func PrepareStep(
	store *memory.Store,
	missionID string,
	stepIndex int,
	step types.ActionStep,
	repoRoot string,
	createdAt int64,
) (string, error) {
	backupDir := filepath.Join(repoRoot, ".tars", "checkpoints", missionID, fmt.Sprintf("step_%d", stepIndex))
	_ = os.MkdirAll(backupDir, 0755)

	metaJSON, _ := json.Marshal(map[string]any{
		"kind":    step.Kind.Name(),
		"payload": step.Payload,
	})

	err := store.UpsertExecutorCheckpoint(
		missionID,
		stepIndex,
		step.Kind.Name(),
		step.Payload,
		backupDir,
		string(metaJSON),
		createdAt,
	)
	if err != nil {
		return "", err
	}

	return backupDir, nil
}

// CompleteStep updates checkpoint status to completed or failed.
func CompleteStep(
	store *memory.Store,
	missionID string,
	stepIndex int,
	success bool,
	resultJSON string,
) error {
	status := "completed"
	if !success {
		status = "failed"
	}
	return store.FinishExecutorCheckpoint(missionID, stepIndex, status, resultJSON)
}

// RollbackStep marks the checkpoint as rolled back.
func RollbackStep(
	store *memory.Store,
	missionID string,
	stepIndex int,
	repoRoot string,
) error {
	return store.MarkExecutorCheckpointRolledBack(missionID, stepIndex)
}

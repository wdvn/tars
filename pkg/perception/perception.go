package perception

import (
	"encoding/json"

	"github.com/wdvn/tars/pkg/metrics"
)

type FileEvidence struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

type EvidenceSnapshot struct {
	Files []FileEvidence `json:"files"`
}

// GatherEvidence aggregates file contents from target paths into JSON format.
func GatherEvidence(root string, paths []string) (string, error) {
	var ev EvidenceSnapshot

	for _, p := range paths {
		content, err := ReadRelative(root, p, 16384)
		if err != nil {
			continue
		}
		metrics.GInc("perception.files.read", 1)
		metrics.GInc("perception.bytes.read", float64(len(content)))

		ev.Files = append(ev.Files, FileEvidence{
			Path:    p,
			Content: content,
		})
	}

	data, err := json.Marshal(ev)
	if err != nil {
		return "{}", err
	}
	return string(data), nil
}

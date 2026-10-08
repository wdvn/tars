package perception

import (
	"fmt"
	"os/exec"

	"github.com/wdvn/tars/pkg/metrics"
)

// Search searches for pattern in root using ripgrep or fallback grep.
func Search(root, pattern string, maxLines int) (string, error) {
	if maxLines <= 0 {
		maxLines = 10
	}

	cmdStr := fmt.Sprintf(
		"cd '%s' && (command -v rg >/dev/null && rg -n --max-count %d '%s' . || grep -rn --include='*.*' -m %d '%s' . 2>/dev/null) | head -%d",
		root, maxLines, pattern, maxLines, pattern, maxLines,
	)

	cmd := exec.Command("bash", "-c", cmdStr)
	out, err := cmd.Output()
	// rg/grep return 1 on no matches, which is not an error
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			out = []byte{}
		} else {
			return "", err
		}
	}

	metrics.GInc("perception.grep.queries", 1)
	metrics.GInc("perception.grep.bytes", float64(len(out)))

	return string(out), nil
}

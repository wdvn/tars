// Package perception provides codebase evidence gathering via safe file reads and grep.
package perception

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// ReadRelative safely reads a file relative to root, rejecting path traversals.
func ReadRelative(root, relPath string, maxBytes int) (string, error) {
	if strings.Contains(relPath, "..") {
		return "", fmt.Errorf("path traversal forbidden: %s", relPath)
	}

	fullPath := filepath.Join(root, relPath)
	f, err := os.Open(fullPath)
	if err != nil {
		return "", err
	}
	defer f.Close()

	if maxBytes <= 0 {
		maxBytes = 32768
	}

	lr := io.LimitReader(f, int64(maxBytes))
	data, err := io.ReadAll(lr)
	if err != nil {
		return "", err
	}

	return string(data), nil
}

// ListGlob finds matching files in root according to pattern.
func ListGlob(root, pattern string) ([]string, error) {
	var matches []string
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return nil
		}
		matched, _ := filepath.Match(pattern, rel)
		if matched {
			matches = append(matches, rel)
			if len(matches) >= 50 {
				return filepath.SkipAll
			}
		}
		return nil
	})
	return matches, err
}

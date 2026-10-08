package llm

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
)

// DotEnv parses environment variable files.
type DotEnv struct {
	values map[string]string
}

// NewDotEnv loads environment variables from standard locations.
// Search order: TARS_ENV_FILE, ./.env, ~/.tars/.env.
// Unset keys only (existing shell environment variables take precedence).
func NewDotEnv() *DotEnv {
	d := &DotEnv{values: make(map[string]string)}

	if explicit := os.Getenv("TARS_ENV_FILE"); explicit != "" {
		d.ingestFile(explicit)
	}

	d.ingestFile(".env")

	if home, err := os.UserHomeDir(); err == nil && home != "" {
		d.ingestFile(filepath.Join(home, ".tars", ".env"))
	}

	return d
}

// IngestFile reads and parses a single .env file into the map.
func (d *DotEnv) ingestFile(path string) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		k, v, ok := ParseDotEnvLine(line)
		if ok && k != "" {
			if _, exists := d.values[k]; !exists {
				// Only set if not already in system environment
				if os.Getenv(k) == "" {
					d.values[k] = v
				}
			}
		}
	}
}

// Get returns the value of a key from dotenv or system environment.
func (d *DotEnv) Get(key string) (string, bool) {
	if sys := os.Getenv(key); sys != "" {
		return sys, true
	}
	v, ok := d.values[key]
	return v, ok
}

// ParseDotEnvLine parses a single key=value line, handling comments and quotes.
func ParseDotEnvLine(line string) (key, val string, ok bool) {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" || strings.HasPrefix(trimmed, "#") {
		return "", "", false
	}

	if strings.HasPrefix(trimmed, "export ") {
		trimmed = strings.TrimSpace(strings.TrimPrefix(trimmed, "export "))
	}

	idx := strings.Index(trimmed, "=")
	if idx == -1 {
		return "", "", false
	}

	k := strings.TrimSpace(trimmed[:idx])
	v := strings.TrimSpace(trimmed[idx+1:])

	// Handle quotes
	if len(v) >= 2 {
		if (v[0] == '"' && v[len(v)-1] == '"') || (v[0] == '\'' && v[len(v)-1] == '\'') {
			v = v[1 : len(v)-1]
		}
	} else if len(v) > 0 && (v[0] == '"' || v[0] == '\'') {
		v = strings.Trim(v, "\"'")
	}

	return k, v, true
}

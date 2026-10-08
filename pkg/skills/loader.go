package skills

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// DefaultDirs returns default search paths for skills.
func DefaultDirs() []string {
	return []string{"skills", ".cursor/skills-cursor"}
}

// SearchDirs returns configured skill search roots.
func SearchDirs() []string {
	if val := os.Getenv("TARS_SKILLS_DIR"); val != "" {
		var res []string
		for _, part := range strings.Split(val, ":") {
			trimmed := strings.TrimSpace(part)
			if trimmed != "" {
				res = append(res, trimmed)
			}
		}
		if len(res) > 0 {
			return res
		}
	}
	return DefaultDirs()
}

// ListSkills returns a JSON string with array of discovered skill names.
func ListSkills() (string, error) {
	roots := SearchDirs()
	seen := make(map[string]bool)
	var names []string

	for _, root := range roots {
		_ = filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
			if err != nil || info == nil {
				return nil
			}
			if strings.EqualFold(info.Name(), "SKILL.md") {
				dir := filepath.Dir(path)
				skillName := filepath.Base(dir)
				if !seen[skillName] {
					seen[skillName] = true
					names = append(names, skillName)
				}
			}
			return nil
		})
	}

	data, err := json.Marshal(map[string][]string{"skills": names})
	if err != nil {
		return `{"skills":[]}`, err
	}
	return string(data), nil
}

// LoadSkill loads the SKILL.md content for a named skill.
func LoadSkill(name string) (string, error) {
	roots := SearchDirs()
	for _, root := range roots {
		candidate := filepath.Join(root, name, "SKILL.md")
		if data, err := os.ReadFile(candidate); err == nil {
			return string(data), nil
		}
	}
	return "", fmt.Errorf("skill not found: %s", name)
}

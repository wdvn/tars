package mcp

import "strings"

// ToolRef parses namespaced or plain tool identifiers.
type ToolRef struct {
	Server string
	Tool   string
}

// ParseToolRef parses "server__tool" or "tool".
func ParseToolRef(raw string) ToolRef {
	if idx := strings.Index(raw, "__"); idx != -1 {
		return ToolRef{
			Server: raw[:idx],
			Tool:   raw[idx+2:],
		}
	}
	return ToolRef{
		Server: "",
		Tool:   raw,
	}
}

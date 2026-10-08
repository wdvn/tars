package memory

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/wdvn/tars/pkg/llm"
	"github.com/wdvn/tars/pkg/session"
)

// ContextConfig governs working memory and context window assembly.
type ContextConfig struct {
	RawTurns             int
	SessionPool          int
	SessionRecallK       int
	EpisodicRecallK      int
	MaxContextChars      int
	SummaryTriggerTurns  int
	MaxSummaryChars      int
}

// DefaultContextConfig returns standard memory controller configuration.
func DefaultContextConfig() ContextConfig {
	return ContextConfig{
		RawTurns:            6,
		SessionPool:         24,
		SessionRecallK:      3,
		EpisodicRecallK:     2,
		MaxContextChars:     24000,
		SummaryTriggerTurns: 12,
		MaxSummaryChars:     4000,
	}
}

// LoadContextConfig loads configuration with environment variable overrides.
func LoadContextConfig() ContextConfig {
	cfg := DefaultContextConfig()

	if v := os.Getenv("TARS_SESSION_RAW_TURNS"); v != "" {
		if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && n > 0 {
			cfg.RawTurns = n
		}
	}
	if v := os.Getenv("TARS_SESSION_POOL"); v != "" {
		if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && n > 0 {
			cfg.SessionPool = n
		}
	}
	if v := os.Getenv("TARS_SESSION_RECALL_K"); v != "" {
		if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && n > 0 {
			cfg.SessionRecallK = n
		}
	}
	if v := os.Getenv("TARS_EPISODIC_RECALL_K"); v != "" {
		if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && n > 0 {
			cfg.EpisodicRecallK = n
		}
	}
	if v := os.Getenv("TARS_CONTEXT_MAX_CHARS"); v != "" {
		if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && n > 0 {
			cfg.MaxContextChars = n
		}
	}

	return cfg
}

// ContextPack holds the assembled prompt and message array ready for the LLM.
type ContextPack struct {
	System   string
	Messages []llm.Message
}

// AssembleChatContext compiles the working window and semantic recall blocks.
func AssembleChatContext(
	store *Store,
	sess *session.Session,
	query string,
	baseSystem string,
	cfg ContextConfig,
) (*ContextPack, error) {
	poolLimit := cfg.SessionPool
	if cfg.RawTurns > poolLimit {
		poolLimit = cfg.RawTurns
	}

	turns, err := sess.LoadRecentTurns(poolLimit)
	if err != nil {
		turns = nil
	}

	summary, _ := sess.Summary()

	episodic, err := Recall(store, query, cfg.EpisodicRecallK)
	if err != nil {
		episodic = nil
	}

	var sb strings.Builder
	sb.WriteString(baseSystem)

	if summary != "" {
		sb.WriteString("\n\n[session_summary]\n")
		sb.WriteString(summary)
	}

	if len(episodic) > 0 {
		sb.WriteString("\n\n[episodic_recall]\n")
		for _, h := range episodic {
			sb.WriteString(fmt.Sprintf("- (score %.3f) %s\n", h.Score, h.Content))
		}
	}

	// Working window of raw turns
	startIdx := 0
	if len(turns) > cfg.RawTurns {
		startIdx = len(turns) - cfg.RawTurns
	}
	rawWindow := turns[startIdx:]

	messages := make([]llm.Message, 0, len(rawWindow)+1)
	for _, t := range rawWindow {
		messages = append(messages, session.ToLLMMessage(t))
	}
	messages = append(messages, llm.Message{Role: "user", Content: query})

	return &ContextPack{
		System:   sb.String(),
		Messages: messages,
	}, nil
}

// ManageSessionSummary checks if turns exceed threshold and compresses old turns.
func ManageSessionSummary(sess *session.Session, cfg ContextConfig) error {
	count, err := sess.CountTurns()
	if err != nil || count < cfg.SummaryTriggerTurns {
		return nil
	}

	turns, err := sess.LoadRecentTurns(count)
	if err != nil || len(turns) <= cfg.RawTurns {
		return nil
	}

	// Summarize turns older than raw turns
	olderTurns := turns[:len(turns)-cfg.RawTurns]
	var sb strings.Builder
	for _, t := range olderTurns {
		sb.WriteString(fmt.Sprintf("%s: %s\n", t.Role, t.Content))
	}

	summary := sb.String()
	if len(summary) > cfg.MaxSummaryChars {
		summary = summary[len(summary)-cfg.MaxSummaryChars:]
	}

	return sess.SetSummary(summary)
}

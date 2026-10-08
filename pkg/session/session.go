package session

import (
	"fmt"
	"strings"
	"time"

	"github.com/wdvn/tars/pkg/metrics"
)

// Store defines database operations required by Session.
type Store interface {
	CreateSession(sessionID string, createdAt int64) error
	AppendSessionTurn(sessionID, role, content string, createdAt int64) error
	LoadSessionTurnsJSON(sessionID string, limit int) (string, error)
	GetSessionSummary(sessionID string) (string, error)
	SetSessionSummary(sessionID, summary string) error
	CountSessionTurns(sessionID string) (int, error)
}

// Session manages conversation turns and rolling summary for a given session ID.
type Session struct {
	ID    string
	store Store
}

// NewSession creates or reopens a session.
func NewSession(store Store, id string) (*Session, error) {
	now := time.Now().Unix()
	if err := store.CreateSession(id, now); err != nil {
		return nil, err
	}
	return &Session{
		ID:    id,
		store: store,
	}, nil
}

// AppendOperator records an operator message turn.
func (s *Session) AppendOperator(content string) error {
	now := time.Now().Unix()
	if err := s.store.AppendSessionTurn(s.ID, "operator", content, now); err != nil {
		return err
	}
	metrics.GInc("session.turns.total", 1)
	metrics.GInc("session.turns.operator", 1)
	return nil
}

// AppendAgent records an agent response turn.
func (s *Session) AppendAgent(agent, content string) error {
	now := time.Now().Unix()
	if err := s.store.AppendSessionTurn(s.ID, agent, content, now); err != nil {
		return err
	}
	metrics.GInc("session.turns.total", 1)
	metrics.GInc("session.turns.agent", 1)
	return nil
}

// LoadRecentTurns loads the recent turns for this session as Turn structs.
func (s *Session) LoadRecentTurns(limit int) ([]Turn, error) {
	blob, err := s.store.LoadSessionTurnsJSON(s.ID, limit)
	if err != nil {
		return nil, err
	}
	return ParseTurnsJSON(blob)
}

// RecentContext returns a concatenated string representation of recent turns.
func (s *Session) RecentContext(limit int) (string, error) {
	turns, err := s.LoadRecentTurns(limit)
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	for _, t := range turns {
		sb.WriteString(fmt.Sprintf("[%s] %s\n", t.Role, t.Content))
	}
	return sb.String(), nil
}

// Summary returns the rolling summary.
func (s *Session) Summary() (string, error) {
	return s.store.GetSessionSummary(s.ID)
}

// SetSummary updates the rolling summary.
func (s *Session) SetSummary(summary string) error {
	return s.store.SetSessionSummary(s.ID, summary)
}

// CountTurns returns the total number of turns in the session.
func (s *Session) CountTurns() (int, error) {
	return s.store.CountSessionTurns(s.ID)
}

// Package types defines shared types across all TARS subsystems: agents, phases, mission context, and action contracts.
package types

import "fmt"

// Agent represents one of the tri-agent crew members.
type Agent string

const (
	AgentAnalyst  Agent = "analyst"
	AgentExecutor Agent = "executor"
	AgentMonitor  Agent = "monitor"
)

// Name returns the stable lowercase tag for logs, metrics, and SQLite artifact rows.
func (a Agent) Name() string {
	return string(a)
}

// Phase represents an OODA cognitive phase.
type Phase string

const (
	PhaseOrient Phase = "orient"
	PhaseAssess Phase = "assess"
	PhasePlan   Phase = "plan"
	PhaseAct    Phase = "act"
	PhaseVerify Phase = "verify"
)

// Name returns the OODA phase label used in mission loop transitions and stored artifacts.
func (p Phase) Name() string {
	return string(p)
}

// MissionStatus represents the current lifecycle state of a mission.
type MissionStatus string

const (
	StatusOrient  MissionStatus = "orient"
	StatusAssess  MissionStatus = "assess"
	StatusPlan    MissionStatus = "plan"
	StatusAct     MissionStatus = "act"
	StatusVerify  MissionStatus = "verify"
	StatusDone    MissionStatus = "done"
	StatusBlocked MissionStatus = "blocked"
)

// Name returns the status name.
func (s MissionStatus) Name() string {
	return string(s)
}

// Priority represents scheduling hints.
type Priority string

const (
	PriorityCritical   Priority = "critical"
	PriorityNormal     Priority = "normal"
	PriorityBackground Priority = "background"
)

// Name returns the priority name.
func (p Priority) Name() string {
	return string(p)
}

// MissionContext encapsulates mission execution state and evidence.
type MissionContext struct {
	MissionID string        `json:"mission_id"`
	Goal      string        `json:"goal"`
	Phase     Phase         `json:"phase"`
	Status    MissionStatus `json:"status"`
	Priority  Priority      `json:"priority"`
	// Evidence is a JSON blob containing perception / recall evidence for reasoning blocks.
	Evidence  string        `json:"evidence"`
}

// BlockResult is the output of an Analyst reasoning block.
type BlockResult struct {
	Kind        string `json:"kind"`
	PayloadJSON string `json:"payload_json"`
}

// ActionKind represents the dispatcher key for Executor actions.
type ActionKind string

const (
	ActionShell    ActionKind = "shell"
	ActionFileEdit ActionKind = "file_edit"
	ActionGit      ActionKind = "git"
	ActionVerify   ActionKind = "verify"
	ActionMCP      ActionKind = "mcp"
	ActionSkill    ActionKind = "skill"
)

// Name returns the action kind name.
func (k ActionKind) Name() string {
	return string(k)
}

// ActionStep is a single executable step in an approved plan.
type ActionStep struct {
	Kind    ActionKind `json:"kind"`
	Payload string     `json:"payload"`
}

// Action represents an action request to be evaluated or executed.
type Action struct {
	Kind    ActionKind `json:"kind"`
	Payload string     `json:"payload"`
}

// ApprovedPlan is passed from Analyst to Executor.
type ApprovedPlan struct {
	MissionID string       `json:"mission_id"`
	Steps     []ActionStep `json:"steps"`
	Rollback  string       `json:"rollback,omitempty"`
}

// ActionResult records the execution output of a single step.
type ActionResult struct {
	StepIndex int        `json:"step_index"`
	Kind      ActionKind `json:"kind"`
	Success   bool       `json:"success"`
	Stdout    string     `json:"stdout"`
	Stderr    string     `json:"stderr"`
	ExitCode  int        `json:"exit_code"`
}

// BlockedAction records an action denied by Safety Guard.
type BlockedAction struct {
	StepIndex   int    `json:"step_index"`
	Boundary    string `json:"boundary"`
	Reason      string `json:"reason"`
	Alternative string `json:"alternative"`
}

// ExecuteOutcome encapsulates the overall result of plan execution.
type ExecuteOutcome struct {
	Completed []ActionResult
	Blocked   *BlockedAction
}

// Handoff is the summary passed to operator on verify pass.
type Handoff struct {
	SummaryJSON string `json:"summary_json"`
}

// LoopBack details when verification fails and triggers an OODA loop-back.
type LoopBack struct {
	TargetPhase Phase  `json:"target_phase"`
	Reason      string `json:"reason"`
	DetailJSON  string `json:"detail_json"`
}

// VerifyOutcome represents the result of the Monitor verification.
type VerifyOutcome struct {
	Pass *Handoff
	Fail *LoopBack
}

// Common error definitions
var (
	ErrInvalidInput       = fmt.Errorf("invalid input")
	ErrLLMFailed          = fmt.Errorf("llm failed")
	ErrSchemaViolation    = fmt.Errorf("schema violation")
	ErrStorageUnavailable = fmt.Errorf("storage unavailable")
	ErrActionFailed       = fmt.Errorf("action failed")
	ErrInvalidPlan        = fmt.Errorf("invalid plan")
	ErrVerifyFailed       = fmt.Errorf("verify failed")
)

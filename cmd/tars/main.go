package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/wdvn/tars/pkg/core"
	"github.com/wdvn/tars/pkg/llm"
	"github.com/wdvn/tars/pkg/mcp"
	"github.com/wdvn/tars/pkg/memory"
	"github.com/wdvn/tars/pkg/memory/embed"
	"github.com/wdvn/tars/pkg/metrics"
	"github.com/wdvn/tars/pkg/perception"
	"github.com/wdvn/tars/pkg/session"
	"github.com/wdvn/tars/pkg/skills"
	"github.com/wdvn/tars/pkg/stream"
	"github.com/wdvn/tars/pkg/types"
)

func main() {
	args := os.Args[1:]

	if len(args) > 0 {
		switch args[0] {
		case "chat":
			runChat()
			return
		case "report":
			isJSON := len(args) > 1 && args[1] == "--json"
			runReport(isJSON)
			return
		case "embed":
			if len(args) > 1 && args[1] == "pull" {
				runEmbedPull()
				return
			}
		}
	}

	runDemo()
}

func initMetrics(command string) *metrics.Metrics {
	runID := fmt.Sprintf("run-%s-%x", command, time.Now().UnixNano()&0xffffffff)
	m := metrics.New(runID, command, "tars")
	metrics.SetGlobal(m)
	return m
}

func finishMetrics(store *memory.Store, m *metrics.Metrics, w io.Writer, isJSON bool) {
	if m == nil || store == nil {
		return
	}
	_ = metrics.Flush(m, store)
	dbTotals, _ := metrics.LoadDbTotals(store)

	if isJSON {
		_ = metrics.PrintJSON(w, m, dbTotals)
		_, _ = fmt.Fprintln(w)
	} else {
		_ = metrics.PrintHuman(w, m, dbTotals)
		_ = metrics.PrintHistory(store, w)
	}
	metrics.SetGlobal(nil)
}

func runReport(isJSON bool) {
	store := memory.NewStore(memory.DefaultDBPath)
	_ = store.ApplySchema()

	runID := fmt.Sprintf("run-query-%x", time.Now().UnixNano()&0xffffffff)
	m := metrics.New(runID, "report", "query")
	dbTotals, _ := metrics.LoadDbTotals(store)

	if isJSON {
		_ = metrics.PrintJSON(os.Stdout, m, dbTotals)
		fmt.Println()
	} else {
		fmt.Println("T.A.R.S. metrics catalog (registry — baseline zeros for query-only run)")
		fmt.Println()
		_ = metrics.PrintHuman(os.Stdout, m, dbTotals)
		_ = metrics.PrintHistory(store, os.Stdout)
	}
}

func runEmbedPull() {
	cfg := embed.LoadConfig()
	if cfg.ResolvedProvider() != "ollama" {
		_, _ = fmt.Fprintln(os.Stderr, "TARS_EMBED_PROVIDER must be ollama (or set TARS_EMBED_MODEL)")
		os.Exit(1)
	}

	if err := embed.PullModel(cfg.OllamaHost, cfg.Model); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "failed to pull embedding model %s: %v\n", cfg.Model, err)
		os.Exit(1)
	}
	fmt.Printf("Pulled embedding model: %s @ %s\n", cfg.Model, cfg.OllamaHost)
}

func completeStreamWithFallback(
	ctx context.Context,
	w io.Writer,
	provider *llm.Provider,
	req llm.CompletionRequest,
	sink stream.Sink,
) (llm.CompletionResponse, error) {
	resp, err := (*provider).CompleteStream(ctx, req, sink)
	if err != nil {
		_, _ = fmt.Fprintf(w, "  stream failed (%v) — stub fallback\n", err)
		stub := llm.InstrumentProvider(llm.NewStubProvider())
		*provider = stub
		return (*provider).CompleteStream(ctx, req, sink)
	}
	return resp, nil
}

func runDemo() {
	ctx := context.Background()
	store := memory.NewStore(memory.DefaultDBPath)
	_ = store.ApplySchema()

	missionID := "demo-runtime"
	sink := stream.ResolveStdout()

	mState := initMetrics("demo")
	defer finishMetrics(store, mState, os.Stdout, false)

	fmt.Print("tars runtime demo — streaming · perception · recall · session · loop\n\n")

	// [1] Streaming LLM
	fmt.Print("[1] Streaming LLM\n")
	llmProv, kindName, _ := llm.Resolve(ctx)
	instrumentedLLM := llm.InstrumentProvider(llmProv)
	fmt.Printf("  provider: %s\n", kindName)

	systemPrompt := "T.A.R.S."
	if rc := llm.RuntimeConfig(); rc != nil && rc.SystemPrompt != "" {
		systemPrompt = rc.SystemPrompt
	}

	streamReq := llm.CompletionRequest{
		Config:   llm.RequestConfig{MaxTokens: 4096},
		System:   systemPrompt,
		Messages: []llm.Message{{Role: "user", Content: "status report"}},
	}

	streamResp, _ := completeStreamWithFallback(ctx, os.Stdout, &instrumentedLLM, streamReq, sink)
	fmt.Printf("\n  tokens: %d\n\n", streamResp.TokensUsed)

	// [2] Codebase perception
	fmt.Print("[2] Codebase perception\n")
	evidence, _ := perception.GatherEvidence(".", []string{"build.zig", "src/root.zig", "go.mod"})
	fmt.Printf("  evidence bytes: %d\n", len(evidence))

	grepHits, _ := perception.Search(".", "MissionContext", 5)
	fmt.Printf("  grep MissionContext: %d byte(s)\n\n", len(grepHits))

	// [3] Episodic memory + semantic recall
	fmt.Print("[3] Episodic memory + semantic recall\n")
	_, _ = embed.Resolve(ctx)
	fmt.Printf("  embed: %s dim=%d\n", embed.LoadConfig().ResolvedProvider(), embed.Dimension())

	_ = core.WriteEpisodeFromOutcome(store, missionID, "analyst", "Tri-agent skeleton uses ORIENT ASSESS PLAN ACT VERIFY phases", []string{"architecture", "demo"})
	_ = core.WriteEpisodeFromOutcome(store, missionID, "monitor", "Verify phase checks executor output and publishes handoff", []string{"verify"})

	hits, _ := memory.Recall(store, "verify handoff monitor", 2)
	for _, h := range hits {
		contentSnippet := h.Content
		if len(contentSnippet) > 60 {
			contentSnippet = contentSnippet[:60]
		}
		fmt.Printf("  recall score=%.3f: %s\n", h.Score, contentSnippet)
	}
	fmt.Println()

	// [4] Multi-turn session
	fmt.Print("[4] Multi-turn session\n")
	sess, err := session.NewSession(store, missionID)
	if err == nil {
		_ = sess.AppendOperator("What is the mission loop?")
		_ = sess.AppendAgent("analyst", "ORIENT → ASSESS → PLAN → ACT → VERIFY with loop-back.")
		ctxLines, _ := sess.RecentContext(10)
		fmt.Printf("  session %s: %d byte(s) context\n\n", sess.ID, len(ctxLines))
	}

	// [5] MCP bridge
	fmt.Print("[5] MCP bridge (JSON-RPC)\n")
	if client := mcp.ClientFromEnv(); client != nil {
		tools, err := client.ListTools()
		if err != nil {
			tools = mcp.StubCall("list")
		}
		fmt.Printf("  MCP tools/list: %d byte(s)\n\n", len(tools))
	} else {
		stub := mcp.StubCall("filesystem__read")
		fmt.Printf("  %s (set TARS_MCP_CMD for live JSON-RPC MCP)\n\n", stub)
	}

	// [5b] Skills
	fmt.Print("[5b] Skills (SKILL.md)\n")
	skillList, _ := skills.ListSkills()
	fmt.Printf("  %s\n\n", skillList)

	// [6] Autonomous loop
	fmt.Print("[6] Autonomous loop\n")
	mctx := core.DefaultContext(missionID, "Runtime capability demo")
	mctx.Evidence = evidence

	plan := types.ApprovedPlan{
		MissionID: missionID,
		Steps: []types.ActionStep{
			{Kind: types.ActionShell, Payload: "echo tars-loop-ok"},
			{Kind: types.ActionSkill, Payload: "list"},
			{Kind: types.ActionMCP, Payload: `filesystem__read:{"path":"go.mod"}`},
			{Kind: types.ActionGit, Payload: "status --short"},
		},
		Rollback: "echo tars-plan-rollback-ok",
	}

	loopResult, _ := core.RunAutonomous(ctx, store, instrumentedLLM, sink, core.LoopConfig{
		MaxIterations:   6,
		VerifyCommands:  []string{"test -f go.mod"},
		PerceptionPaths: []string{"go.mod"},
		RepoRoot:        ".",
	}, &mctx, &plan)

	fmt.Printf("  iterations: %d, status: %s\n", loopResult.Iterations, loopResult.FinalStatus.Name())
	if loopResult.LastVerify != nil {
		if loopResult.LastVerify.Pass != nil {
			fmt.Print("  verify: PASS\n")
		} else if loopResult.LastVerify.Fail != nil {
			fmt.Printf("  verify: FAIL → %s\n", loopResult.LastVerify.Fail.Reason)
		}
	}

	fmt.Print("\n[7] Operational metrics\n")
}

func runChat() {
	ctx := context.Background()
	store := memory.NewStore(memory.DefaultDBPath)
	_ = store.ApplySchema()

	mState := initMetrics("chat")
	defer finishMetrics(store, mState, os.Stdout, false)

	_, _ = embed.Resolve(ctx)

	sess, err := session.NewSession(store, "chat")
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to initialize chat session: %v\n", err)
		return
	}

	llmProv, kindName, _ := llm.Resolve(ctx)
	instrumentedLLM := llm.InstrumentProvider(llmProv)
	sink := stream.ResolveStdout()

	systemPrompt := "T.A.R.S. crew analyst"
	if rc := llm.RuntimeConfig(); rc != nil && rc.SystemPrompt != "" {
		systemPrompt = rc.SystemPrompt
	}

	ctxCfg := memory.LoadContextConfig()

	fmt.Printf("T.A.R.S. chat (%s, session %s). Empty line to exit.\n> ", kindName, sess.ID)

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			break
		}

		_ = sess.AppendOperator(line)

		trace := stream.BeginStepTrace(sink, "memory: assemble context")
		pack, err := memory.AssembleChatContext(store, sess, line, systemPrompt, ctxCfg)
		if err != nil {
			fmt.Fprintf(os.Stderr, "context error: %v\n", err)
			continue
		}
		if trace != nil {
			trace.End(fmt.Sprintf("%d msgs, %d system chars", len(pack.Messages), len(pack.System)))
		}

		turn, err := core.RunTurn(ctx, store, sess, instrumentedLLM, sink, line, pack, core.DefaultChatConfig())
		if err != nil {
			fmt.Fprintf(os.Stderr, "\nturn error: %v\n", err)
			continue
		}

		if !turn.Streamed {
			fmt.Printf("\n%s\n", turn.Response)
		}

		_ = sess.AppendAgent("analyst", turn.Response)
		_ = memory.ManageSessionSummary(sess, ctxCfg)
		fmt.Print("\n> ")
	}

	fmt.Print("\n--- metrics ---\n")
}

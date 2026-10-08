package mcp

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/wdvn/tars/pkg/metrics"
)

// Client interacts with an external MCP server via stdio JSON-RPC.
type Client struct {
	cmdStr string
}

// ClientFromEnv checks if TARS_MCP_CMD is defined and creates a Client.
func ClientFromEnv() *Client {
	cmd := strings.TrimSpace(os.Getenv("TARS_MCP_CMD"))
	if cmd == "" {
		return nil
	}
	return &Client{cmdStr: cmd}
}

// CallTool executes an MCP tool by name.
func (c *Client) CallTool(name string, argsJSON string) (string, error) {
	metrics.GInc("mcp.tool.calls", 1)
	metrics.GInc("mcp.rpc.requests", 1)

	ref := ParseToolRef(name)

	var argsMap map[string]any
	if argsJSON != "" {
		_ = json.Unmarshal([]byte(argsJSON), &argsMap)
	}

	params := map[string]any{
		"name":      ref.Tool,
		"arguments": argsMap,
	}

	reqBytes, err := BuildRequest(1, "tools/call", params)
	if err != nil {
		metrics.GInc("mcp.tool.errors", 1)
		return "", err
	}

	resp, err := c.execRPC(reqBytes)
	if err != nil {
		metrics.GInc("mcp.tool.errors", 1)
		return "", err
	}

	return ExtractToolText(resp.Result)
}

// ListTools queries available tools on the MCP server.
func (c *Client) ListTools() (string, error) {
	metrics.GInc("mcp.rpc.requests", 1)

	reqBytes, err := BuildRequest(2, "tools/list", map[string]any{})
	if err != nil {
		return "", err
	}

	resp, err := c.execRPC(reqBytes)
	if err != nil {
		return "", err
	}

	return string(resp.Result), nil
}

func (c *Client) execRPC(reqBytes []byte) (*Response, error) {
	proc := exec.Command("bash", "-c", c.cmdStr)
	stdin, err := proc.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := proc.StdoutPipe()
	if err != nil {
		return nil, err
	}

	if err := proc.Start(); err != nil {
		return nil, err
	}
	defer func() {
		_ = proc.Process.Kill()
		_ = proc.Wait()
	}()

	// Handshake: initialize
	initBytes, _ := BuildRequest(0, "initialize", map[string]any{
		"protocolVersion": "2024-11-05",
		"clientInfo":      map[string]string{"name": "tars", "version": "0.1.0"},
		"capabilities":    map[string]any{},
	})
	if _, err := stdin.Write(initBytes); err != nil {
		return nil, err
	}

	reader := bufio.NewReader(stdout)
	_, _ = reader.ReadString('\n') // consume init resp

	// Send notification
	notif := `{"jsonrpc":"2.0","method":"notifications/initialized"}` + "\n"
	_, _ = stdin.Write([]byte(notif))

	// Send actual request
	if _, err := stdin.Write(reqBytes); err != nil {
		return nil, err
	}

	line, err := reader.ReadString('\n')
	if err != nil && err != io.EOF {
		return nil, err
	}

	var resp Response
	if err := json.Unmarshal([]byte(strings.TrimSpace(line)), &resp); err != nil {
		return nil, err
	}
	if resp.Error != nil {
		return nil, fmt.Errorf("mcp rpc error (%d): %s", resp.Error.Code, resp.Error.Message)
	}

	return &resp, nil
}

// StubCall returns mock responses when live MCP is unconfigured.
func StubCall(action string) string {
	if action == "list" {
		return `{"tools":[{"name":"filesystem__read","description":"Read file content"}]}`
	}
	return `{"status":"stub","note":"set TARS_MCP_CMD to enable live MCP tools"}`
}

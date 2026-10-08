package mcp

import (
	"encoding/json"
)

type Request struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      int             `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type Response struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      int             `json:"id"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *ResponseError  `json:"error,omitempty"`
}

type ResponseError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func BuildRequest(id int, method string, params any) ([]byte, error) {
	var raw json.RawMessage
	if params != nil {
		b, err := json.Marshal(params)
		if err != nil {
			return nil, err
		}
		raw = b
	}
	req := Request{
		JSONRPC: "2.0",
		ID:      id,
		Method:  method,
		Params:  raw,
	}
	data, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}
	return append(data, '\n'), nil
}

func ExtractToolText(resultRaw []byte) (string, error) {
	var res struct {
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(resultRaw, &res); err != nil {
		return string(resultRaw), nil
	}
	if len(res.Content) > 0 && res.Content[0].Text != "" {
		return res.Content[0].Text, nil
	}
	return string(resultRaw), nil
}

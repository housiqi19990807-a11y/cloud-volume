package main

import (
	"encoding/json"
	"fmt"
	"strings"
)

type bridgePayload struct {
	Ok     bool         `json:"ok"`
	Result any          `json:"result,omitempty"`
	Error  *bridgeError `json:"error,omitempty"`
}

type bridgeError struct {
	Message string `json:"message"`
}

// buildSuccessPayload keeps Flutter-side error handling uniform across bridge calls.
func buildSuccessPayload(result any) string {
	return mustMarshalJSON(bridgePayload{
		Ok:     true,
		Result: result,
	})
}

// buildErrorPayload mirrors the success envelope so Dart can decode one shape.
func buildErrorPayload(err error) string {
	return mustMarshalJSON(bridgePayload{
		Ok: false,
		Error: &bridgeError{
			Message: err.Error(),
		},
	})
}

func decodeArgs(args json.RawMessage, target any) error {
	raw := strings.TrimSpace(string(args))
	if raw == "" || raw == "null" {
		return nil
	}
	if err := json.Unmarshal(args, target); err != nil {
		return fmt.Errorf("parse bridge arguments: %w", err)
	}
	return nil
}

func mustMarshalJSON(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return string(data)
}

// dispatch_log.go forwards Flutter-side log lines into the shared bridge log file.
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
)

type flutterLogArgs struct {
	Message string `json:"message"`
	Level   string `json:"level"`
	Tag     string `json:"tag"`
}

// writeFlutterLog appends a tagged line via the standard log package (stderr + bridge log file).
func writeFlutterLog(args json.RawMessage) (any, error) {
	var input flutterLogArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	msg := strings.TrimSpace(input.Message)
	if msg == "" {
		return map[string]any{"ok": true}, nil
	}
	tag := strings.TrimSpace(input.Tag)
	if tag == "" {
		tag = "flutter"
	}
	level := normalizeFlutterLogLevel(input.Level)
	if level == "SILENT" {
		return map[string]any{"ok": true}, nil
	}
	prefix := fmt.Sprintf("[app/%s]", tag)
	log.Printf("%s %s %s", prefix, level, msg)
	return map[string]any{"ok": true}, nil
}

func normalizeFlutterLogLevel(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "silent":
		return "SILENT"
	case "error", "err":
		return "ERROR"
	case "debug":
		return "DEBUG"
	default:
		return "INFO"
	}
}

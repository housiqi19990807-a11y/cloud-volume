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
	level := strings.ToLower(strings.TrimSpace(input.Level))
	prefix := fmt.Sprintf("[app/%s]", tag)
	switch level {
	case "error", "err":
		log.Printf("%s ERROR %s", prefix, msg)
	case "warn", "warning":
		log.Printf("%s WARN %s", prefix, msg)
	default:
		log.Printf("%s %s", prefix, msg)
	}
	return map[string]any{"ok": true}, nil
}

// dispatch_log.go forwards Flutter-side log lines into the shared bridge log file.
package main

import (
	"encoding/json"
	"fmt"
	"strings"

	bridgelog "remote-storage/go/logging"
)

type flutterLogArgs struct {
	Message string `json:"message"`
	Level   string `json:"level"`
	Tag     string `json:"tag"`
}

type logLevelArgs struct {
	Level string `json:"level"`
}

// setLogLevel updates the process-wide backend filter used by bridge logging.
func setLogLevel(args json.RawMessage) (any, error) {
	var input logLevelArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	level := bridgelog.SetLevelString(input.Level)
	return map[string]any{"level": level.StorageValue()}, nil
}

// getLogLevel exposes the active backend filter to settings and diagnostics.
func getLogLevel() (any, error) {
	return map[string]any{"level": bridgelog.CurrentLevel().StorageValue()}, nil
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
	level := bridgelog.ParseLevel(input.Level, bridgelog.LevelInfo)
	if level == bridgelog.LevelSilent {
		return map[string]any{"ok": true}, nil
	}
	prefix := fmt.Sprintf("[app/%s]", tag)
	writeAppLine(level, "%s %s %s", prefix, level.Label(), msg)
	return map[string]any{"ok": true}, nil
}

func writeAppLine(level bridgelog.Level, format string, args ...any) {
	switch level {
	case bridgelog.LevelError:
		bridgelog.Errorf(format, args...)
	case bridgelog.LevelDebug:
		bridgelog.Debugf(format, args...)
	default:
		bridgelog.Infof(format, args...)
	}
}

// Package logging centralizes bridge log levels and filtering.
package logging

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"strings"
	"sync/atomic"
)

// Level controls how much backend and Flutter-forwarded diagnostics are kept.
type Level int32

const (
	LevelSilent Level = iota
	LevelError
	LevelInfo
	LevelDebug
)

var currentLevel atomic.Int32

func init() {
	currentLevel.Store(int32(LevelSilent))
}

// ParseLevel accepts persisted/UI values and falls back when the value is empty.
func ParseLevel(raw string, fallback Level) Level {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "silent", "off", "none":
		return LevelSilent
	case "error", "err":
		return LevelError
	case "info", "information":
		return LevelInfo
	case "debug", "trace":
		return LevelDebug
	default:
		return fallback
	}
}

// SetLevel updates the process-wide backend log filter immediately.
func SetLevel(level Level) {
	currentLevel.Store(int32(level))
}

// SetLevelString updates the filter from a bridge/UI payload and returns it.
func SetLevelString(raw string) Level {
	level := ParseLevel(raw, LevelInfo)
	SetLevel(level)
	return level
}

// CurrentLevel returns the process-wide backend log filter.
func CurrentLevel() Level {
	return Level(currentLevel.Load())
}

// StorageValue is the stable value shared with Flutter preferences and JSON.
func (l Level) StorageValue() string {
	switch l {
	case LevelSilent:
		return "silent"
	case LevelError:
		return "error"
	case LevelDebug:
		return "debug"
	default:
		return "info"
	}
}

// Label is the uppercase token written into log lines.
func (l Level) Label() string {
	return strings.ToUpper(l.StorageValue())
}

// Enabled reports whether a line at level should be emitted.
func Enabled(level Level) bool {
	current := CurrentLevel()
	// Backend failures are never discarded. Silent only suppresses routine
	// diagnostics; it must not turn a caught error into an invisible failure.
	return level == LevelError || (current != LevelSilent && level <= current)
}

// ConfigureOutput installs a filtering writer behind the standard logger.
func ConfigureOutput(sink io.Writer) {
	log.SetOutput(levelWriter{sink: sink})
}

// Debugf writes a debug backend line when the current level allows it.
func Debugf(format string, args ...any) {
	logWithLevel(LevelDebug, format, args...)
}

// Infof writes an informational backend line when the current level allows it.
func Infof(format string, args ...any) {
	logWithLevel(LevelInfo, format, args...)
}

// Errorf writes an error backend line when the current level allows it.
func Errorf(format string, args ...any) {
	logWithLevel(LevelError, format, args...)
}

func logWithLevel(level Level, format string, args ...any) {
	if !Enabled(level) {
		return
	}
	log.Printf("[%s] %s", level.Label(), fmt.Sprintf(format, args...))
}

type levelWriter struct {
	sink io.Writer
}

func (w levelWriter) Write(p []byte) (int, error) {
	if Enabled(classifyLine(p)) {
		if _, err := w.sink.Write(p); err != nil {
			return 0, err
		}
	}
	return len(p), nil
}

func classifyLine(line []byte) Level {
	upper := bytes.ToUpper(line)
	if bytes.Contains(upper, []byte("[DEBUG]")) || bytes.Contains(upper, []byte(" DEBUG ")) {
		return LevelDebug
	}
	if bytes.Contains(upper, []byte("[ERROR]")) || bytes.Contains(upper, []byte(" ERROR ")) {
		return LevelError
	}
	if looksErrorLike(upper) {
		return LevelError
	}
	return LevelInfo
}

func looksErrorLike(upper []byte) bool {
	return bytes.Contains(upper, []byte("ERROR")) ||
		bytes.Contains(upper, []byte("FAILED")) ||
		bytes.Contains(upper, []byte("FAILURE")) ||
		bytes.Contains(upper, []byte("WARNING")) ||
		bytes.Contains(upper, []byte("WARN"))
}

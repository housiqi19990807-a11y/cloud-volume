// Logging tests cover level parsing and output filtering for bridge logs.
package logging

import (
	"bytes"
	"log"
	"strings"
	"testing"
)

func TestParseLevel(t *testing.T) {
	tests := map[string]Level{
		"silent": LevelSilent,
		"ERROR":  LevelError,
		"info":   LevelInfo,
		"debug":  LevelDebug,
		"":       LevelDebug,
	}
	for input, want := range tests {
		if got := ParseLevel(input, LevelDebug); got != want {
			t.Fatalf("ParseLevel(%q) = %v, want %v", input, got, want)
		}
	}
}

func TestLevelWriterFiltersPlainInfo(t *testing.T) {
	var buf bytes.Buffer
	oldFlags := log.Flags()
	log.SetFlags(0)
	defer log.SetFlags(oldFlags)
	ConfigureOutput(&buf)
	SetLevel(LevelError)

	log.Print("[bridge/mount] start")
	log.Print("[bridge/mount] error opening bucket")

	output := buf.String()
	if strings.Contains(output, "start") {
		t.Fatalf("info line was not filtered: %q", output)
	}
	if !strings.Contains(output, "error opening bucket") {
		t.Fatalf("error-like line was filtered: %q", output)
	}
}

func TestDebugfHonorsLevel(t *testing.T) {
	var buf bytes.Buffer
	oldFlags := log.Flags()
	log.SetFlags(0)
	defer log.SetFlags(oldFlags)
	ConfigureOutput(&buf)

	SetLevel(LevelInfo)
	Debugf("hidden detail")
	if buf.Len() != 0 {
		t.Fatalf("debug line written at info level: %q", buf.String())
	}

	SetLevel(LevelDebug)
	Debugf("visible detail")
	if !strings.Contains(buf.String(), "visible detail") {
		t.Fatalf("debug line missing at debug level: %q", buf.String())
	}
}

func TestSilentLevelStillWritesErrors(t *testing.T) {
	var buf bytes.Buffer
	oldFlags := log.Flags()
	log.SetFlags(0)
	defer log.SetFlags(oldFlags)
	ConfigureOutput(&buf)
	SetLevel(LevelSilent)

	Infof("hidden routine detail")
	Errorf("visible failure")

	output := buf.String()
	if strings.Contains(output, "hidden routine detail") {
		t.Fatalf("info line was written at silent level: %q", output)
	}
	if !strings.Contains(output, "visible failure") {
		t.Fatalf("error line was filtered at silent level: %q", output)
	}
}

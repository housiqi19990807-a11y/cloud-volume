// Active mount count tests keep exit warnings aligned with live sessions.
package mount

import "testing"

func TestActiveMountCountOnlyIncludesLiveSessions(t *testing.T) {
	m := &manager{sessions: map[string]*mountSession{
		"live":     {mounted: true},
		"inactive": {mounted: false},
		"stopping": {mounted: true, stopping: true},
	}}

	if got := m.activeMountCount(); got != 1 {
		t.Fatalf("activeMountCount() = %d, want 1", got)
	}
}

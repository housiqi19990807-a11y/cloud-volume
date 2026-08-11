//go:build windows && cgo

package mount

import (
	"errors"
	"testing"
	"time"
)

func TestPlaceholderFetchGateCachesAndCoalesces(t *testing.T) {
	hydrator := &cloudFilesHydrator{
		placeholderInflight: map[string]*cloudFilesPlaceholderFetch{},
		placeholderFetched:  map[string]time.Time{},
	}

	shouldFetch, wait := hydrator.beginPlaceholderFetch(`C:\root`)
	if !shouldFetch || wait != nil {
		t.Fatalf("expected first fetch to proceed")
	}

	shouldFetch, wait = hydrator.beginPlaceholderFetch(`C:\root`)
	if shouldFetch || wait == nil {
		t.Fatalf("expected concurrent fetch to coalesce")
	}

	hydrator.finishPlaceholderFetch(`C:\root`, nil)

	shouldFetch, wait = hydrator.beginPlaceholderFetch(`C:\root`)
	if shouldFetch || wait != nil {
		t.Fatalf("expected recent fetch to use cache")
	}
}

func TestPlaceholderFetchGatePropagatesCoalescedFailure(t *testing.T) {
	hydrator := &cloudFilesHydrator{
		placeholderInflight: map[string]*cloudFilesPlaceholderFetch{},
		placeholderFetched:  map[string]time.Time{},
	}

	shouldFetch, wait := hydrator.beginPlaceholderFetch(`C:\root\docs`)
	if !shouldFetch || wait != nil {
		t.Fatal("expected first fetch to proceed")
	}
	shouldFetch, wait = hydrator.beginPlaceholderFetch(`C:\root\docs`)
	if shouldFetch || wait == nil {
		t.Fatal("expected second fetch to wait")
	}

	wantErr := errors.New("remote listing failed")
	hydrator.finishPlaceholderFetch(`C:\root\docs`, wantErr)
	<-wait.done
	if !errors.Is(wait.err, wantErr) {
		t.Fatalf("coalesced error = %v, want %v", wait.err, wantErr)
	}

	shouldFetch, wait = hydrator.beginPlaceholderFetch(`C:\root\docs`)
	if !shouldFetch || wait != nil {
		t.Fatal("failed fetch must not mark the directory as populated")
	}
}

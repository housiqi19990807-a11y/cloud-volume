// Failover pool unit tests cover server normalization, fallback error
// classification, and the ordered-upstream selection logic.
package s3

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/url"
	"testing"

	smithyhttp "github.com/aws/smithy-go/transport/http"
)

// stubHTTPStatusError builds a smithy ResponseError carrying the given status,
// which is what shouldFallbackS3 inspects via s3HTTPStatus.
func stubHTTPStatusError(status int) error {
	return &smithyhttp.ResponseError{
		Response: &smithyhttp.Response{
			Response: &http.Response{StatusCode: status},
		},
		Err: errors.New("stub"),
	}
}

func TestNormalizeS3Servers(t *testing.T) {
	got := normalizeS3Servers("A", "http://B/", "", "https://C", "http://B")
	want := []string{"http://A", "http://B", "https://C"}
	if len(got) != len(want) {
		t.Fatalf("got %v want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v want %v", got, want)
		}
	}
}

func TestShouldFallbackS3(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"nil", nil, false},
		{"canceled", context.Canceled, true},
		{"deadline", context.DeadlineExceeded, true},
		{"net error", &net.OpError{Err: errors.New("connection reset")}, true},
		{"url error", &url.Error{Op: "Get", URL: "http://x", Err: errors.New("EOF")}, true},
		{"http 503", stubHTTPStatusError(503), true},
		{"http 429", stubHTTPStatusError(429), true},
		{"http 404", stubHTTPStatusError(404), false},
		{"http 403", stubHTTPStatusError(403), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := shouldFallbackS3(tc.err); got != tc.want {
				t.Fatalf("got %v want %v", got, tc.want)
			}
		})
	}
}

func TestFailoverClientOrderedUpstreams(t *testing.T) {
	fc := &FailoverClient{defaultIdx: -1}
	fc.replaceUpstreams([]string{"http://gw1", "http://gw2", "http://gw3"})

	// Initially default is the first server.
	if fc.DefaultServer() != "http://gw1" {
		t.Fatalf("default = %s, want gw1", fc.DefaultServer())
	}

	// After setDefault(gw3), gw3 should be first in the ordered list.
	fc.setDefault("http://gw3")
	order := fc.orderedUpstreams()
	if len(order) != 3 || order[0].server != "http://gw3" {
		t.Fatalf("ordered upstreams = %v, want gw3 first", serversOf(order))
	}
}

// serversOf extracts the server names from an upstream slice (test helper).
func serversOf(upstreams []*upstreamS3) []string {
	out := make([]string, 0, len(upstreams))
	for _, u := range upstreams {
		out = append(out, u.server)
	}
	return out
}

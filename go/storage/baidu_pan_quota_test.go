// Baidu Pan quota tests pin the account-level request parameters and response mapping.
package storage

import (
	"io"
	"net/http"
	"strings"
	"testing"

	xpanauth "github.com/lfhy/xpan/auth"
	xpanclient "github.com/lfhy/xpan/client"
	xpantypes "github.com/lfhy/xpan/types"
)

type baiduPanQuotaRoundTripFunc func(*http.Request) (*http.Response, error)

func (fn baiduPanQuotaRoundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return fn(req)
}

func TestFetchBaiduPanQuotaRequestsCapacityDetails(t *testing.T) {
	transport := baiduPanQuotaRoundTripFunc(func(req *http.Request) (*http.Response, error) {
		query := req.URL.Query()
		if got := query.Get("access_token"); got != "test-access-token" {
			t.Fatalf("access_token = %q, want test token", got)
		}
		if got := query.Get("checkfree"); got != "1" {
			t.Fatalf("checkfree = %q, want 1", got)
		}
		if got := query.Get("checkexpire"); got != "1" {
			t.Fatalf("checkexpire = %q, want 1", got)
		}
		return &http.Response{
			StatusCode: http.StatusOK,
			Body: io.NopCloser(strings.NewReader(
				`{"total":1000,"used":250,"free":750,"expire":false}`,
			)),
			Header:  make(http.Header),
			Request: req,
		}, nil
	})
	state := baiduPanAuthState{
		accessToken:  "test-access-token",
		refreshToken: "test-refresh-token",
	}
	httpClient := newBaiduPanRetryHTTPClientWithCreds(
		&http.Client{Transport: transport},
		&xpantypes.Credentials{
			AccessToken:  state.accessToken,
			RefreshToken: state.refreshToken,
		},
	)
	client := xpanclient.NewWithClient(httpClient, &xpanauth.AuthEnv{
		AccessToken:  state.accessToken,
		RefreshToken: state.refreshToken,
	})

	quota, err := fetchBaiduPanQuota(client)
	if err != nil {
		t.Fatalf("fetchBaiduPanQuota returned error: %v", err)
	}
	if quota == nil || int64(quota.Total) != 1000 || int64(quota.Used) != 250 {
		t.Fatalf("quota = %#v, want total=1000 used=250", quota)
	}
}

// Baidu Pan quota tests pin the account-level request parameters and response mapping.
package storage

import (
	"errors"
	"io"
	"net/http"
	"runtime"
	"strings"
	"testing"

	xpanauth "github.com/lfhy/xpan/auth"
	xpanclient "github.com/lfhy/xpan/client"
	xpantypes "github.com/lfhy/xpan/types"

	storageconfig "remote-storage/go/config"
)

type baiduPanQuotaRoundTripFunc func(*http.Request) (*http.Response, error)

func (fn baiduPanQuotaRoundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return fn(req)
}

func TestBaiduPanQuotaLoggedOutErrorRefreshesToken(t *testing.T) {
	if !shouldRefreshBaiduPanToken(errors.New("用户未登录")) {
		t.Fatal("quota logged-out response must trigger an OAuth token refresh")
	}
}

func TestPersistBaiduPanStateUpdatesNonActiveProfile(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	if runtime.GOOS == "windows" {
		t.Setenv("USERPROFILE", home)
	}
	s3Config := storageconfig.DefaultConfig()
	s3Config.Endpoint = "https://s3.example.com"
	s3Config.AccessKeyID = "s3-access"
	s3Config.SecretAccessKey = "s3-secret"
	baiduConfig := baiduPanConfigFromAuth("Baidu Account", "old-access", "old-refresh")
	if err := storageconfig.SaveProfile("active-s3", s3Config); err != nil {
		t.Fatalf("save S3 profile: %v", err)
	}
	if err := storageconfig.SaveProfile("baidu", baiduConfig); err != nil {
		t.Fatalf("save Baidu profile: %v", err)
	}
	if err := storageconfig.SetActiveProfile("active-s3"); err != nil {
		t.Fatalf("set active profile: %v", err)
	}

	if err := persistBaiduPanState(baiduConfig, baiduPanAuthState{
		accessToken:  "new-access",
		refreshToken: "new-refresh",
	}); err != nil {
		t.Fatalf("persist Baidu state: %v", err)
	}

	updated, err := storageconfig.LoadProfile("baidu")
	if err != nil {
		t.Fatalf("load Baidu profile: %v", err)
	}
	if updated.AccessKeyID != "new-access" || updated.SecretAccessKey != "new-refresh" {
		t.Fatalf("Baidu tokens were not updated: %#v", updated)
	}
	activeS3, err := storageconfig.LoadProfile("active-s3")
	if err != nil {
		t.Fatalf("load active S3 profile: %v", err)
	}
	if activeS3.AccessKeyID != "s3-access" || activeS3.SecretAccessKey != "s3-secret" {
		t.Fatalf("active S3 profile was changed: %#v", activeS3)
	}
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

// Baidu OAuth helpers keep the local callback flow out of the bridge transport code.
package storage

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/google/uuid"
	xpanauth "github.com/lfhy/xpan/auth"
	xpanclient "github.com/lfhy/xpan/client"
	xpanuser "github.com/lfhy/xpan/user"

	storageconfig "remote-storage/go/config"
)

const baiduPanOAuthTimeout = 3 * time.Minute

type baiduPanOAuthResult struct {
	code string
	err  error
}

func AuthorizeBaiduPan(displayName string) (storageconfig.RemoteStorageConfig, error) {
	callbackID := uuid.NewString()
	callbackPath := "/oauth/baidu/callback/" + callbackID
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return storageconfig.RemoteStorageConfig{}, fmt.Errorf("listen oauth callback: %w", err)
	}
	defer listener.Close()

	redirectURL := fmt.Sprintf("http://%s%s", listener.Addr().String(), callbackPath)
	resultCh := make(chan baiduPanOAuthResult, 1)
	server := &http.Server{
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path != callbackPath {
				http.NotFound(w, r)
				return
			}
			if authErr := strings.TrimSpace(r.URL.Query().Get("error_description")); authErr != "" {
				writeBaiduPanOAuthPage(w, "百度网盘授权失败，可以关闭此页面返回应用。")
				select {
				case resultCh <- baiduPanOAuthResult{err: errors.New(authErr)}:
				default:
				}
				return
			}
			code := strings.TrimSpace(r.URL.Query().Get("code"))
			if code == "" {
				writeBaiduPanOAuthPage(w, "没有收到授权码，可以关闭此页面返回应用。")
				select {
				case resultCh <- baiduPanOAuthResult{err: fmt.Errorf("oauth callback missing code")}:
				default:
				}
				return
			}
			writeBaiduPanOAuthPage(w, "百度网盘授权成功，可以关闭此页面返回应用。")
			select {
			case resultCh <- baiduPanOAuthResult{code: code}:
			default:
			}
		}),
	}
	go func() {
		_ = server.Serve(listener)
	}()
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()

	authURL := baiduPanAuthURL(redirectURL)
	if err := openBaiduPanBrowser(authURL); err != nil {
		return storageconfig.RemoteStorageConfig{}, err
	}

	select {
	case result := <-resultCh:
		if result.err != nil {
			return storageconfig.RemoteStorageConfig{}, result.err
		}
		return exchangeBaiduPanCode(displayName, redirectURL, result.code)
	case <-time.After(baiduPanOAuthTimeout):
		return storageconfig.RemoteStorageConfig{}, fmt.Errorf("百度网盘授权 3 分钟内未完成，认证失败")
	}
}

func baiduPanAuthURL(redirectURL string) string {
	client := xpanclient.New()
	return client.GetAuthCodeURL(&xpanauth.AuthCodeReq{
		ClientId:    baiduPanClientID,
		RedirectUri: redirectURL,
	})
}

func exchangeBaiduPanCode(
	displayName string,
	redirectURL string,
	code string,
) (storageconfig.RemoteStorageConfig, error) {
	baiduPanSDKMu.Lock()
	defer baiduPanSDKMu.Unlock()

	client := xpanclient.New(&xpanauth.AuthEnv{
		ClientId:     baiduPanClientID,
		ClientSecret: baiduPanClientSecret,
		RedirectUri:  redirectURL,
	})
	token, err := client.GetToken(code, redirectURL)
	if err != nil {
		return storageconfig.RemoteStorageConfig{}, err
	}
	userInfo, err := xpanuser.GetUserInfo(&xpanuser.UserInfoReq{})
	if err != nil {
		return storageconfig.RemoteStorageConfig{}, err
	}
	label := strings.TrimSpace(displayName)
	if label == "" {
		label = strings.TrimSpace(userInfo.NetDiskName)
	}
	if label == "" {
		label = strings.TrimSpace(userInfo.BaiduName)
	}
	if label == "" {
		label = "百度网盘"
	}
	cfg := baiduPanConfigFromAuth(label, token.AccessToken, token.RefreshToken)
	rememberBaiduPanState(
		baiduPanSessionKeys(cfg, baiduPanAuthState{
			accessToken:  token.AccessToken,
			refreshToken: token.RefreshToken,
		}),
		baiduPanAuthState{
			accessToken:  token.AccessToken,
			refreshToken: token.RefreshToken,
		},
	)
	return cfg, nil
}

func openBaiduPanBrowser(targetURL string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", targetURL)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", targetURL)
	default:
		cmd = exec.Command("xdg-open", targetURL)
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("open browser for oauth: %w", err)
	}
	return nil
}

func writeBaiduPanOAuthPage(w http.ResponseWriter, message string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(`<!doctype html><html><body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;line-height:1.6;"><h2>` + message + `</h2></body></html>`))
}

// AWS SigV4 signing for FGW requests, migrated from jwanfs/pkg/sdk/s3/sign.go.
// This is a self-contained implementation (crypto/* + net/http only) so the
// SDK can talk to JWanFS gateways that require SigV4 without pulling in the
// AWS SDK.
package jwanfs

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/md5"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	neturl "net/url"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	signV4Algorithm = "AWS4-HMAC-SHA256"
	iso8601Format   = "20060102T150405Z"
	yyyymmdd        = "20060102"
	defaultRegion   = "us-east-1"
)

var (
	ignoredHeaders = map[string]bool{
		"Authorization":  true,
		"Content-Type":   true,
		"Content-Length": true,
		"User-Agent":     true,
	}
	reservedObjectNames = regexp.MustCompile(`^[a-zA-Z0-9-_.~/]+$`)
)

// NewFGWAPI builds the fgwapi=? query URL for the given FGW route and optional
// extra query values.
func NewFGWAPI(endpoint string, fgwapi string, query ...neturl.Values) (*neturl.URL, error) {
	if fgwapi == "" {
		return nil, fmt.Errorf("fgwapi not found")
	}

	values := cloneQueryValues(query...)
	values.Add("fgwapi", fgwapi)

	baseURL := endpoint
	if !strings.HasPrefix(baseURL, "http://") && !strings.HasPrefix(baseURL, "https://") {
		baseURL = "http://" + baseURL
	}
	baseURL = strings.TrimSuffix(baseURL, "/") + "/?" + values.Encode()
	return neturl.Parse(baseURL)
}

// NewFGWAPIFromClient builds an FGW URL using the client's current default server.
func (c *Client) NewFGWAPI(fgwapi string, query ...neturl.Values) (*neturl.URL, error) {
	server := c.DefaultServer()
	if server == "" {
		return nil, ErrNoAvailableUpstreams
	}
	return NewFGWAPI(server, fgwapi, query...)
}

// NewSignedRequestV4 creates an *http.Request with an AWS SigV4 Authorization
// header for the given access/secret keys.
func NewSignedRequestV4(ctx context.Context, method, urlStr string, body []byte, accessKey, secretKey string) (*http.Request, error) {
	if method == "" {
		method = http.MethodPost
	}
	if ctx == nil {
		ctx = context.Background()
	}

	reader := bytes.NewReader(body)
	req, err := http.NewRequestWithContext(ctx, method, urlStr, reader)
	if err != nil {
		return nil, err
	}

	hashedPayload := sha256Hex(body)
	req.Header.Set("x-amz-content-sha256", hashedPayload)
	req.ContentLength = int64(len(body))
	if len(body) > 0 {
		req.Header.Set("Content-Md5", md5Base64(body))
	}

	if err := SignRequestV4(req, accessKey, secretKey); err != nil {
		return nil, err
	}
	return req, nil
}

// SignRequestV4 computes and attaches the SigV4 Authorization header to req.
func SignRequestV4(req *http.Request, accessKey, secretKey string) error {
	hashedPayload := req.Header.Get("x-amz-content-sha256")
	if hashedPayload == "" {
		return errors.New("invalid hashed payload")
	}

	currTime := time.Now().UTC()
	req.Header.Set("x-amz-date", currTime.Format(iso8601Format))

	headerMap := make(map[string][]string)
	for k, vv := range req.Header {
		if _, ok := ignoredHeaders[http.CanonicalHeaderKey(k)]; !ok {
			headerMap[strings.ToLower(k)] = vv
		}
	}

	headers := []string{"host"}
	for k := range headerMap {
		headers = append(headers, k)
	}
	sort.Strings(headers)

	var buf bytes.Buffer
	for _, k := range headers {
		buf.WriteString(k)
		buf.WriteByte(':')
		if k == "host" {
			buf.WriteString(req.URL.Host)
			buf.WriteByte('\n')
			continue
		}
		for idx, v := range headerMap[k] {
			if idx > 0 {
				buf.WriteByte(',')
			}
			buf.WriteString(v)
		}
		buf.WriteByte('\n')
	}
	canonicalHeaders := buf.String()
	signedHeaders := strings.Join(headers, ";")

	req.URL.RawQuery = strings.ReplaceAll(req.URL.Query().Encode(), "+", "%20")
	canonicalRequest := strings.Join([]string{
		req.Method,
		encodePathV4(req.URL.Path),
		req.URL.RawQuery,
		canonicalHeaders,
		signedHeaders,
		hashedPayload,
	}, "\n")

	scope := strings.Join([]string{
		currTime.Format(yyyymmdd),
		defaultRegion,
		"s3",
		"aws4_request",
	}, "/")
	stringToSign := signV4Algorithm + "\n" + currTime.Format(iso8601Format) + "\n" + scope + "\n" + sha256Hex([]byte(canonicalRequest))

	date := hmacSHA256([]byte("AWS4"+secretKey), []byte(currTime.Format(yyyymmdd)))
	region := hmacSHA256(date, []byte(defaultRegion))
	service := hmacSHA256(region, []byte("s3"))
	signingKey := hmacSHA256(service, []byte("aws4_request"))
	signature := hex.EncodeToString(hmacSHA256(signingKey, []byte(stringToSign)))

	auth := strings.Join([]string{
		signV4Algorithm + " Credential=" + accessKey + "/" + scope,
		"SignedHeaders=" + signedHeaders,
		"Signature=" + signature,
	}, ", ")
	req.Header.Set("Authorization", auth)
	return nil
}

// parseServerURL parses an endpoint into host + scheme-is-https.
func parseServerURL(server string) (host string, secure bool, err error) {
	info, err := neturl.Parse(server)
	if err != nil {
		return "", false, err
	}
	return info.Host, strings.EqualFold(info.Scheme, "https"), nil
}

func cloneQueryValues(query ...neturl.Values) neturl.Values {
	dst := neturl.Values{}
	if len(query) == 0 || query[0] == nil {
		return dst
	}
	for key, values := range query[0] {
		copied := make([]string, len(values))
		copy(copied, values)
		dst[key] = copied
	}
	return dst
}

func md5Base64(data []byte) string {
	sum := md5.Sum(data)
	return base64.StdEncoding.EncodeToString(sum[:])
}

func sha256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func hmacSHA256(key, data []byte) []byte {
	hash := hmac.New(sha256.New, key)
	hash.Write(data)
	return hash.Sum(nil)
}

func encodePathV4(pathName string) string {
	if reservedObjectNames.MatchString(pathName) {
		return pathName
	}
	var encoded string
	for _, s := range pathName {
		if 'A' <= s && s <= 'Z' || 'a' <= s && s <= 'z' || '0' <= s && s <= '9' {
			encoded += string(s)
			continue
		}
		switch s {
		case '-', '_', '.', '~', '/':
			encoded += string(s)
		default:
			size := utf8.RuneLen(s)
			if size < 0 {
				return pathName
			}
			buf := make([]byte, size)
			utf8.EncodeRune(buf, s)
			for _, b := range buf {
				encoded += "%" + strings.ToUpper(hex.EncodeToString([]byte{b}))
			}
		}
	}
	return encoded
}

// stringPtr returns a *string for non-empty v, nil otherwise (FGW input builder).
func stringPtr(v string) *string {
	if v == "" {
		return nil
	}
	return &v
}

// readCloserCopy is a tiny helper to drain a body into a byte slice.
func readCloserCopy(r io.ReadCloser) ([]byte, error) {
	defer r.Close()
	return io.ReadAll(r)
}


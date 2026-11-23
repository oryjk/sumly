package minio

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

const (
	DefaultBucket      = "sumly"
	DefaultRegion      = "us-east-1"
	defaultHTTPTimeout = 15 * time.Second
	emptyPayloadSHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
)

type Config struct {
	Endpoint   string
	AccessKey  string
	SecretKey  string
	Bucket     string
	Region     string
	HTTPClient *http.Client
	Now        func() time.Time
}

// Client 使用 Go 标准库实现 MinIO S3 Path-Style + AWS Signature V4 读写。
type Client struct {
	endpoint  string
	accessKey string
	secretKey string
	bucket    string
	region    string
	http      *http.Client
	now       func() time.Time
}

func NewClient(cfg Config) *Client {
	endpoint := strings.TrimRight(strings.TrimSpace(cfg.Endpoint), "/")
	if endpoint != "" && !strings.Contains(endpoint, "://") {
		endpoint = "https://" + endpoint
	}
	bucket := strings.TrimSpace(cfg.Bucket)
	if bucket == "" {
		bucket = DefaultBucket
	}
	region := strings.TrimSpace(cfg.Region)
	if region == "" {
		region = DefaultRegion
	}
	httpClient := cfg.HTTPClient
	if httpClient == nil {
		httpClient = &http.Client{Timeout: defaultHTTPTimeout}
	}
	nowFn := cfg.Now
	if nowFn == nil {
		nowFn = time.Now
	}
	return &Client{
		endpoint:  endpoint,
		accessKey: strings.TrimSpace(cfg.AccessKey),
		secretKey: strings.TrimSpace(cfg.SecretKey),
		bucket:    bucket,
		region:    region,
		http:      httpClient,
		now:       nowFn,
	}
}

func (c *Client) IsConfigured() bool {
	return c != nil && c.endpoint != "" && c.accessKey != "" && c.secretKey != "" && c.bucket != ""
}

func (c *Client) PutObject(ctx context.Context, objectKey string, contentType string, data []byte) error {
	if !c.IsConfigured() {
		return fmt.Errorf("minio client is not configured")
	}
	reqURL, canonicalURI, err := c.buildObjectURL(objectKey)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPut, reqURL.String(), bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("create minio put request: %w", err)
	}
	req.Host = reqURL.Host
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}

	payloadHash := sha256Hex(data)
	c.signRequest(req, canonicalURI, payloadHash, c.now().UTC())

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("minio put request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		errBody, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return fmt.Errorf("minio put failed: status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(errBody)))
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	return nil
}

func (c *Client) GetObject(ctx context.Context, objectKey string) (ports.ObjectStream, error) {
	if !c.IsConfigured() {
		return ports.ObjectStream{}, fmt.Errorf("minio client is not configured")
	}
	reqURL, canonicalURI, err := c.buildObjectURL(objectKey)
	if err != nil {
		return ports.ObjectStream{}, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL.String(), nil)
	if err != nil {
		return ports.ObjectStream{}, fmt.Errorf("create minio get request: %w", err)
	}
	req.Host = reqURL.Host

	c.signRequest(req, canonicalURI, emptyPayloadSHA256, c.now().UTC())

	resp, err := c.http.Do(req)
	if err != nil {
		return ports.ObjectStream{}, fmt.Errorf("minio get request failed: %w", err)
	}
	if resp.StatusCode == http.StatusNotFound {
		resp.Body.Close()
		return ports.ObjectStream{}, sharederror.ErrNotFound
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		errBody, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		resp.Body.Close()
		return ports.ObjectStream{}, fmt.Errorf("minio get failed: status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(errBody)))
	}

	return ports.ObjectStream{
		Body:          resp.Body,
		ContentType:   resp.Header.Get("Content-Type"),
		ContentLength: resp.ContentLength,
	}, nil
}

func (c *Client) buildObjectURL(objectKey string) (*url.URL, string, error) {
	base, err := url.Parse(c.endpoint)
	if err != nil || base.Scheme == "" || base.Host == "" {
		return nil, "", fmt.Errorf("invalid minio endpoint")
	}
	cleanKey := strings.TrimLeft(objectKey, "/")
	basePath := strings.TrimRight(base.Path, "/")

	segments := make([]string, 0, 4)
	if basePath != "" {
		for _, seg := range strings.Split(strings.TrimLeft(basePath, "/"), "/") {
			if seg != "" {
				segments = append(segments, awsURIEncodeSegment(seg))
			}
		}
	}
	segments = append(segments, awsURIEncodeSegment(c.bucket))
	for _, seg := range strings.Split(cleanKey, "/") {
		segments = append(segments, awsURIEncodeSegment(seg))
	}

	canonicalURI := "/" + strings.Join(segments, "/")
	fullURL := &url.URL{
		Scheme:  base.Scheme,
		Host:    base.Host,
		Path:    "/" + strings.TrimLeft(basePath+"/"+c.bucket+"/"+cleanKey, "/"),
		RawPath: canonicalURI,
	}
	return fullURL, canonicalURI, nil
}

func (c *Client) signRequest(req *http.Request, canonicalURI string, payloadHash string, now time.Time) {
	amzDate := now.UTC().Format("20060102T150405Z")
	dateStamp := now.UTC().Format("20060102")

	req.Header.Set("x-amz-date", amzDate)
	req.Header.Set("x-amz-content-sha256", payloadHash)

	headersToSign := map[string]string{
		"host":                 strings.ToLower(req.Host),
		"x-amz-content-sha256": payloadHash,
		"x-amz-date":           amzDate,
	}
	if ct := strings.TrimSpace(req.Header.Get("Content-Type")); ct != "" {
		headersToSign["content-type"] = ct
	}

	headerNames := make([]string, 0, len(headersToSign))
	for k := range headersToSign {
		headerNames = append(headerNames, k)
	}
	sort.Strings(headerNames)

	var canonicalHeaders strings.Builder
	for _, name := range headerNames {
		canonicalHeaders.WriteString(name)
		canonicalHeaders.WriteByte(':')
		canonicalHeaders.WriteString(headersToSign[name])
		canonicalHeaders.WriteByte('\n')
	}
	signedHeaders := strings.Join(headerNames, ";")

	canonicalRequest := strings.Join([]string{
		req.Method,
		canonicalURI,
		"", // path-style PUT/GET 无查询参数
		canonicalHeaders.String(),
		signedHeaders,
		payloadHash,
	}, "\n")

	credentialScope := fmt.Sprintf("%s/%s/s3/aws4_request", dateStamp, c.region)
	stringToSign := strings.Join([]string{
		"AWS4-HMAC-SHA256",
		amzDate,
		credentialScope,
		sha256Hex([]byte(canonicalRequest)),
	}, "\n")

	signingKey := deriveSigningKey(c.secretKey, dateStamp, c.region, "s3")
	signature := hex.EncodeToString(hmacSHA256(signingKey, stringToSign))

	authHeader := fmt.Sprintf(
		"AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s",
		c.accessKey,
		credentialScope,
		signedHeaders,
		signature,
	)
	req.Header.Set("Authorization", authHeader)
}

func deriveSigningKey(secretKey, dateStamp, region, service string) []byte {
	kDate := hmacSHA256([]byte("AWS4"+secretKey), dateStamp)
	kRegion := hmacSHA256(kDate, region)
	kService := hmacSHA256(kRegion, service)
	return hmacSHA256(kService, "aws4_request")
}

func hmacSHA256(key []byte, message string) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(message))
	return mac.Sum(nil)
}

func sha256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func awsURIEncodeSegment(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		ch := s[i]
		if (ch >= 'A' && ch <= 'Z') ||
			(ch >= 'a' && ch <= 'z') ||
			(ch >= '0' && ch <= '9') ||
			ch == '-' || ch == '_' || ch == '.' || ch == '~' {
			b.WriteByte(ch)
		} else {
			fmt.Fprintf(&b, "%%%02X", ch)
		}
	}
	return b.String()
}

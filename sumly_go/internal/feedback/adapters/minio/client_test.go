package minio

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

func TestSigV4DeterministicSigning(t *testing.T) {
	fixedTime := time.Date(2026, 11, 23, 12, 34, 56, 0, time.UTC)
	client := NewClient(Config{
		Endpoint:  "https://minio.example.com",
		AccessKey: "AKIAEXAMPLE",
		SecretKey: "SECRETEXAMPLEKEY",
		Bucket:    "sumly",
		Region:    "us-east-1",
		Now:       func() time.Time { return fixedTime },
	})

	reqURL, canonicalURI, err := client.buildObjectURL("feedback/20261123/test_img.jpg")
	if err != nil {
		t.Fatalf("buildObjectURL: %v", err)
	}
	if canonicalURI != "/sumly/feedback/20261123/test_img.jpg" {
		t.Fatalf("canonicalURI=%q", canonicalURI)
	}

	req, err := http.NewRequest(http.MethodGet, reqURL.String(), nil)
	if err != nil {
		t.Fatalf("NewRequest: %v", err)
	}
	req.Host = reqURL.Host
	client.signRequest(req, canonicalURI, emptyPayloadSHA256, fixedTime)

	if got := req.Header.Get("x-amz-date"); got != "20261123T123456Z" {
		t.Fatalf("x-amz-date=%q", got)
	}
	if got := req.Header.Get("x-amz-content-sha256"); got != emptyPayloadSHA256 {
		t.Fatalf("x-amz-content-sha256=%q", got)
	}
	auth := req.Header.Get("Authorization")
	wantPrefix := "AWS4-HMAC-SHA256 Credential=AKIAEXAMPLE/20261123/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature="
	if !strings.HasPrefix(auth, wantPrefix) {
		t.Fatalf("Authorization=%q want prefix %q", auth, wantPrefix)
	}
	sig := strings.TrimPrefix(auth, wantPrefix)
	if len(sig) != 64 {
		t.Fatalf("expected 64-char hex signature, got %q", sig)
	}

	// Re-verify expected signature independently
	canonicalRequest := strings.Join([]string{
		"GET",
		"/sumly/feedback/20261123/test_img.jpg",
		"",
		"host:minio.example.com\nx-amz-content-sha256:" + emptyPayloadSHA256 + "\nx-amz-date:20261123T123456Z\n",
		"host;x-amz-content-sha256;x-amz-date",
		emptyPayloadSHA256,
	}, "\n")
	sts := strings.Join([]string{
		"AWS4-HMAC-SHA256",
		"20261123T123456Z",
		"20261123/us-east-1/s3/aws4_request",
		sha256Hex([]byte(canonicalRequest)),
	}, "\n")
	wantSig := bytes.NewBuffer(nil)
	_ = wantSig
	expected := deriveSigningKey("SECRETEXAMPLEKEY", "20261123", "us-east-1", "s3")
	if got := hmacSHA256(expected, sts); sig != strings.ToLower(sha256HexOrRaw(got)) {
		t.Fatalf("signature mismatch: got=%s", sig)
	}
}

func sha256HexOrRaw(b []byte) string {
	const hexChars = "0123456789abcdef"
	out := make([]byte, len(b)*2)
	for i, v := range b {
		out[i*2] = hexChars[v>>4]
		out[i*2+1] = hexChars[v&0x0f]
	}
	return string(out)
}

func TestClientPutAndGetObjectWithHTTPTest(t *testing.T) {
	var mu sync.Mutex
	objects := make(map[string]struct {
		contentType string
		data        []byte
	})

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(auth, "AWS4-HMAC-SHA256 Credential=test-ak/") {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte("missing sigv4 auth"))
			return
		}
		if r.Header.Get("x-amz-date") == "" || r.Header.Get("x-amz-content-sha256") == "" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		switch r.Method {
		case http.MethodPut:
			body, err := io.ReadAll(r.Body)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			if r.Header.Get("x-amz-content-sha256") != sha256Hex(body) {
				w.WriteHeader(http.StatusBadRequest)
				_, _ = w.Write([]byte("payload hash mismatch"))
				return
			}
			mu.Lock()
			objects[r.URL.Path] = struct {
				contentType string
				data        []byte
			}{contentType: r.Header.Get("Content-Type"), data: body}
			mu.Unlock()
			w.WriteHeader(http.StatusOK)

		case http.MethodGet:
			mu.Lock()
			obj, ok := objects[r.URL.Path]
			mu.Unlock()
			if !ok {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			w.Header().Set("Content-Type", obj.contentType)
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(obj.data)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	client := NewClient(Config{
		Endpoint:   server.URL,
		AccessKey:  "test-ak",
		SecretKey:  "test-sk",
		Bucket:     "sumly",
		Region:     "us-east-1",
		HTTPClient: server.Client(),
	})
	if !client.IsConfigured() {
		t.Fatal("expected client to be configured")
	}

	payload := []byte{0xFF, 0xD8, 0xFF, 0xE0, 0x11, 0x22, 0x33}
	key := "feedback/20261123/sample.jpg"
	if err := client.PutObject(context.Background(), key, "image/jpeg", payload); err != nil {
		t.Fatalf("PutObject failed: %v", err)
	}

	stream, err := client.GetObject(context.Background(), key)
	if err != nil {
		t.Fatalf("GetObject failed: %v", err)
	}
	defer stream.Body.Close()
	gotData, err := io.ReadAll(stream.Body)
	if err != nil {
		t.Fatalf("ReadAll: %v", err)
	}
	if !bytes.Equal(gotData, payload) || stream.ContentType != "image/jpeg" {
		t.Fatalf("got data=%x ct=%q want %x image/jpeg", gotData, stream.ContentType, payload)
	}

	// Missing object returns sharederror.ErrNotFound
	if _, err := client.GetObject(context.Background(), "feedback/20261123/missing.jpg"); !errors.Is(err, sharederror.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}

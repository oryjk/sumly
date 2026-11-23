package feishu

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/domain"
)

func TestNotifierSendsInteractiveCardPayload(t *testing.T) {
	var receivedBody []byte
	var receivedContentType string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedContentType = r.Header.Get("Content-Type")
		receivedBody, _ = io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"code":0,"msg":"success"}`))
	}))
	defer server.Close()

	notifier := NewNotifier(server.URL, server.Client())
	err := notifier.NotifyNewFeedback(context.Background(), domain.Feedback{
		ID:               42,
		Category:         domain.CategoryBug,
		Content:          "持仓页面下拉刷新后价格闪烁",
		Contact:          "user@example.com",
		AppVersion:       "1.3.0",
		BuildNumber:      "108",
		IOSVersion:       "18.1",
		DeviceModel:      "iPhone16,2",
		MarketMode:       "domestic",
		CloudSyncEnabled: true,
		Attachments: []domain.Attachment{
			{ObjectKey: "feedback/20261123/a1.jpg", URL: "https://oryjk.cn/sumly/api/v1/app/feedback/attachments/20261123/a1.jpg"},
		},
	})
	if err != nil {
		t.Fatalf("NotifyNewFeedback failed: %v", err)
	}

	if !strings.Contains(receivedContentType, "application/json") {
		t.Fatalf("unexpected content-type: %q", receivedContentType)
	}

	var parsed map[string]any
	if err := json.Unmarshal(receivedBody, &parsed); err != nil {
		t.Fatalf("unmarshal payload: %v", err)
	}
	if parsed["msg_type"] != "interactive" {
		t.Fatalf("msg_type=%v want interactive", parsed["msg_type"])
	}
	bodyStr := string(receivedBody)
	for _, want := range []string{
		"#42",
		"问题反馈",
		"持仓页面下拉刷新后价格闪烁",
		"user@example.com",
		"1.3.0 (108)",
		"iPhone16,2 · iOS 18.1",
		"https://oryjk.cn/sumly/api/v1/app/feedback/attachments/20261123/a1.jpg",
		"https://oryjk.cn/sumly/admin/",
	} {
		if !strings.Contains(bodyStr, want) {
			t.Fatalf("payload missing %q: %s", want, bodyStr)
		}
	}
}

func TestNotifierHandlesErrorResponsesAndUnconfiguredNoop(t *testing.T) {
	noop := NewNotifier("", nil)
	if err := noop.NotifyNewFeedback(context.Background(), domain.Feedback{ID: 1}); err != nil {
		t.Fatalf("unconfigured notifier should be no-op, got %v", err)
	}

	apiErrServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"code":19021,"msg":"sign match fail"}`))
	}))
	defer apiErrServer.Close()

	notifier := NewNotifier(apiErrServer.URL, apiErrServer.Client())
	if err := notifier.NotifyNewFeedback(context.Background(), domain.Feedback{ID: 1, Category: domain.CategoryOther, Content: "hello world"}); err == nil {
		t.Fatal("expected error for non-zero feishu code")
	}
}

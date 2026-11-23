package feishu

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/feedback/domain"
)

const (
	AdminPortalURL     = "https://oryjk.cn/sumly/admin/"
	defaultHTTPTimeout = 8 * time.Second
)

// Notifier 通过飞书自定义机器人 Webhook 发送用户反馈交互式卡片。
type Notifier struct {
	webhookURL string
	adminURL   string
	http       *http.Client
}

func NewNotifier(webhookURL string, httpClient *http.Client) *Notifier {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: defaultHTTPTimeout}
	}
	return &Notifier{
		webhookURL: strings.TrimSpace(webhookURL),
		adminURL:   AdminPortalURL,
		http:       httpClient,
	}
}

func (n *Notifier) IsConfigured() bool {
	return n != nil && n.webhookURL != ""
}

func (n *Notifier) NotifyNewFeedback(ctx context.Context, item domain.Feedback) error {
	if !n.IsConfigured() {
		return nil
	}
	payload := BuildCardPayload(item, n.adminURL)
	raw, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal feishu card payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, n.webhookURL, bytes.NewReader(raw))
	if err != nil {
		return fmt.Errorf("create feishu webhook request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := n.http.Do(req)
	if err != nil {
		return fmt.Errorf("send feishu webhook request: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("feishu webhook returned http %d", resp.StatusCode)
	}
	if len(bytes.TrimSpace(body)) > 0 {
		var result struct {
			Code       int    `json:"code"`
			Msg        string `json:"msg"`
			StatusCode int    `json:"StatusCode"`
			StatusMsg  string `json:"StatusMessage"`
		}
		if err := json.Unmarshal(body, &result); err == nil {
			if result.Code != 0 {
				return fmt.Errorf("feishu webhook api error code=%d msg=%s", result.Code, result.Msg)
			}
			if result.StatusCode != 0 {
				return fmt.Errorf("feishu webhook status error code=%d msg=%s", result.StatusCode, result.StatusMsg)
			}
		}
	}
	return nil
}

type CardPayload struct {
	MsgType string `json:"msg_type"`
	Card    Card   `json:"card"`
}

type Card struct {
	Config   CardConfig `json:"config"`
	Header   CardHeader `json:"header"`
	Elements []any      `json:"elements"`
}

type CardConfig struct {
	WideScreenMode bool `json:"wide_screen_mode"`
}

type CardHeader struct {
	Template string   `json:"template"`
	Title    CardText `json:"title"`
}

type CardText struct {
	Tag     string `json:"tag"`
	Content string `json:"content"`
}

type CardDivElement struct {
	Tag    string      `json:"tag"`
	Text   *CardText   `json:"text,omitempty"`
	Fields []CardField `json:"fields,omitempty"`
}

type CardField struct {
	IsShort bool     `json:"is_short"`
	Text    CardText `json:"text"`
}

type CardActionElement struct {
	Tag     string       `json:"tag"`
	Actions []CardButton `json:"actions"`
}

type CardButton struct {
	Tag  string   `json:"tag"`
	Type string   `json:"type"`
	Text CardText `json:"text"`
	URL  string   `json:"url"`
}

func BuildCardPayload(item domain.Feedback, adminURL string) CardPayload {
	if strings.TrimSpace(adminURL) == "" {
		adminURL = AdminPortalURL
	}
	catLabel := domain.CategoryLabel(item.Category)
	contact := item.Contact
	if contact == "" {
		contact = "未填写"
	}

	versionText := formatAppVersion(item.AppVersion, item.BuildNumber)
	deviceText := formatDeviceInfo(item.DeviceModel, item.IOSVersion)

	elements := []any{
		CardDivElement{
			Tag: "div",
			Fields: []CardField{
				{
					IsShort: true,
					Text:    CardText{Tag: "lark_md", Content: fmt.Sprintf("**反馈编号**\n#%d", item.ID)},
				},
				{
					IsShort: true,
					Text:    CardText{Tag: "lark_md", Content: fmt.Sprintf("**分类标签**\n%s (%s)", catLabel, item.Category)},
				},
				{
					IsShort: true,
					Text:    CardText{Tag: "lark_md", Content: fmt.Sprintf("**联系方式**\n%s", contact)},
				},
				{
					IsShort: true,
					Text:    CardText{Tag: "lark_md", Content: fmt.Sprintf("**App 版本**\n%s", versionText)},
				},
				{
					IsShort: true,
					Text:    CardText{Tag: "lark_md", Content: fmt.Sprintf("**机型 / iOS 版本**\n%s", deviceText)},
				},
				{
					IsShort: true,
					Text:    CardText{Tag: "lark_md", Content: fmt.Sprintf("**行情模式 / 云同步**\n%s", formatModeAndSync(item.MarketMode, item.CloudSyncEnabled))},
				},
			},
		},
		CardDivElement{
			Tag:  "div",
			Text: &CardText{Tag: "lark_md", Content: fmt.Sprintf("**反馈内容**\n%s", item.Content)},
		},
	}

	if len(item.Attachments) > 0 {
		links := make([]string, 0, len(item.Attachments))
		for i, att := range item.Attachments {
			links = append(links, fmt.Sprintf("[截图 %d](%s)", i+1, att.URL))
		}
		elements = append(elements, CardDivElement{
			Tag:  "div",
			Text: &CardText{Tag: "lark_md", Content: "**附件截图**\n" + strings.Join(links, "  ")},
		})
	}

	elements = append(elements, CardActionElement{
		Tag: "action",
		Actions: []CardButton{
			{
				Tag:  "button",
				Type: "primary",
				Text: CardText{Tag: "plain_text", Content: "打开管理后台处理"},
				URL:  adminURL,
			},
		},
	})

	return CardPayload{
		MsgType: "interactive",
		Card: Card{
			Config: CardConfig{WideScreenMode: true},
			Header: CardHeader{
				Template: headerTemplateForCategory(item.Category),
				Title: CardText{
					Tag:     "plain_text",
					Content: fmt.Sprintf("【记金用户反馈】#%d · %s", item.ID, catLabel),
				},
			},
			Elements: elements,
		},
	}
}

func headerTemplateForCategory(cat domain.Category) string {
	switch cat {
	case domain.CategoryBug:
		return "red"
	case domain.CategoryData:
		return "orange"
	case domain.CategorySuggestion:
		return "blue"
	default:
		return "grey"
	}
}

func formatAppVersion(version, build string) string {
	switch {
	case version != "" && build != "":
		return fmt.Sprintf("%s (%s)", version, build)
	case version != "":
		return version
	case build != "":
		return "build " + build
	default:
		return "未知"
	}
}

func formatDeviceInfo(model, iosVersion string) string {
	parts := make([]string, 0, 2)
	if model != "" {
		parts = append(parts, model)
	}
	if iosVersion != "" {
		if strings.HasPrefix(strings.ToLower(iosVersion), "ios") {
			parts = append(parts, iosVersion)
		} else {
			parts = append(parts, "iOS "+iosVersion)
		}
	}
	if len(parts) == 0 {
		return "未知"
	}
	return strings.Join(parts, " · ")
}

func formatModeAndSync(marketMode string, cloudSync bool) string {
	mode := marketMode
	if mode == "" {
		mode = "未上报"
	}
	syncLabel := "本地模式"
	if cloudSync {
		syncLabel = "云同步已开"
	}
	return mode + " · " + syncLabel
}

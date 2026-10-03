package application

import (
	"context"
	"strings"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
)

// WechatSubject 以 appid + openid 编码微信身份。
// 同一 openid 在不同小程序下并不相同，缺少 appid 会造成跨应用误绑定。
func WechatSubject(appID, openID string) string {
	return "wechat:" + appID + ":" + openID
}

// WechatSessions 用微信 code 换取身份，并签发与手机号/邮箱同结构的会话。
// 旧 /auth/wechat/login 签发的 24 小时 JWT 不能刷新或注销，因此小程序
// 需要这条统一会话链路；两条链路共用同一身份解析，不会创建两个账户。
type WechatSessions struct {
	Wechat ports.WechatGateway
	Store  ports.NativeStore
	Crypto ports.Cryptography
	Tokens ports.NativeTokens
	// Sessions 复用原生会话的签发与轮换逻辑。
	Sessions Sessions
	// AppID 为当前配置的小程序 appid；为空时视为未配置。
	AppID string
	// LegacyAppID 为已确认归属的旧 appid。只有与 AppID 相同时才迁移旧身份；
	// 不确认归属时保持旧身份原样，不做猜测性关联。
	LegacyAppID string
}

// Enabled 报告微信登录是否可用。
func (w WechatSessions) Enabled() bool { return strings.TrimSpace(w.AppID) != "" }

// Login 用 js_code 换取 openid，关联或迁移身份后签发会话。
func (w WechatSessions) Login(ctx context.Context, code string) (domain.LoginResult, error) {
	code = strings.TrimSpace(code)
	if code == "" {
		return domain.LoginResult{}, domain.ErrInvalid
	}
	if !w.Enabled() {
		return domain.LoginResult{}, domain.ErrUnavailable
	}

	identity, err := w.Wechat.ExchangeCode(ctx, code)
	if err != nil {
		return domain.LoginResult{}, err
	}
	openID := strings.TrimSpace(identity.OpenID)
	if openID == "" {
		// 上游返回空身份时不得创建账户
		return domain.LoginResult{}, domain.ErrCredentials
	}

	session, refresh := w.Sessions.New()
	user, err := w.Store.LoginWechat(ctx, w.AppID, w.LegacyAppID, openID, session)
	if err != nil {
		return domain.LoginResult{}, err
	}
	if user.Status != "active" {
		return domain.LoginResult{}, domain.ErrCredentials
	}

	session.UserID = user.ID
	session.Provider = user.Provider
	access, err := w.Tokens.IssueNative(ctx, session)
	if err != nil {
		return domain.LoginResult{}, err
	}
	// 响应只含会话与用户，不回传 openid 或 session_key。
	return domain.LoginResult{Token: access, RefreshToken: refresh, ExpiresIn: 900, User: user}, nil
}

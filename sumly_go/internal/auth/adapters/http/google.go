package authhttp

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	sharedhttp "gitee.com/oryjk/sumly/sumly_go/internal/shared/http"
	"github.com/gin-gonic/gin"
)

type googleTokenRequest struct {
	ChallengeID   string `json:"challenge_id"`
	IdentityToken string `json:"identity_token"`
}

type linkedEmailCodeRequest struct {
	Email string `json:"email"`
}

type linkedEmailRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Code     string `json:"code"`
}

func (h *NativeHandler) registerGoogleRoutes(g *gin.RouterGroup) {
	g.POST("/auth/google/challenge", nativeJSONEndpoint(false, func(ctx context.Context, token, ip string, _ struct{}) (any, error) {
		return h.accounts.GoogleChallenge(ctx, token, ip)
	}))
	g.POST("/auth/google/login", nativeJSONEndpoint(false, func(ctx context.Context, _, ip string, req googleTokenRequest) (any, error) {
		return h.accounts.GoogleLogin(ctx, req.ChallengeID, req.IdentityToken, ip)
	}))
	g.POST("/auth/google/link", nativeJSONEndpoint(true, func(ctx context.Context, token, ip string, req googleTokenRequest) (any, error) {
		return struct{}{}, h.accounts.LinkGoogle(ctx, token, req.ChallengeID, req.IdentityToken, ip)
	}))
	g.POST("/auth/google/reauthenticate/challenge", nativeJSONEndpoint(true, func(ctx context.Context, token, ip string, _ struct{}) (any, error) {
		return h.accounts.GoogleReauthenticateChallenge(ctx, token, ip)
	}))
	g.POST("/auth/google/reauthenticate", nativeJSONEndpoint(true, func(ctx context.Context, token, ip string, req googleTokenRequest) (any, error) {
		return h.accounts.GoogleReauthenticate(ctx, token, req.ChallengeID, req.IdentityToken, ip)
	}))
	g.POST("/auth/email/link/code", nativeJSONEndpoint(true, func(ctx context.Context, token, ip string, req linkedEmailCodeRequest) (any, error) {
		return gin.H{"retry_after": 60, "expires_in": 300}, h.accounts.SendLinkedEmailCode(ctx, token, req.Email, ip)
	}))
	g.POST("/auth/email/link", nativeJSONEndpoint(true, func(ctx context.Context, token, ip string, req linkedEmailRequest) (any, error) {
		return struct{}{}, h.accounts.LinkEmail(ctx, token, req.Email, req.Password, req.Code, ip)
	}))
}

func nativeJSONEndpoint[T any](requireBearer bool, handle func(context.Context, string, string, T) (any, error)) gin.HandlerFunc {
	return func(c *gin.Context) {
		authorization := c.GetHeader("Authorization")
		token, hasToken := bearerToken(authorization)
		if !hasToken && (requireBearer || authorization != "") {
			nativeError(c, domain.ErrCredentials)
			return
		}
		ctx, cancel := context.WithTimeout(c.Request.Context(), 20*time.Second)
		defer cancel()
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 32768)
		decoder := json.NewDecoder(c.Request.Body)
		decoder.DisallowUnknownFields()
		var req *T
		if err := decoder.Decode(&req); err != nil || req == nil {
			nativeError(c, domain.ErrInvalid)
			return
		}
		if err := decoder.Decode(new(any)); err != io.EOF {
			nativeError(c, domain.ErrInvalid)
			return
		}
		data, err := handle(ctx, token, c.ClientIP(), *req)
		if err != nil {
			nativeError(c, err)
			return
		}
		c.JSON(http.StatusOK, sharedhttp.Success(data))
	}
}

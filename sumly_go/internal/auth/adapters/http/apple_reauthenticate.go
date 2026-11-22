package authhttp

import (
	"context"

	"github.com/gin-gonic/gin"
)

type appleReauthenticationRequest struct {
	ChallengeID       string `json:"challenge_id"`
	IdentityToken     string `json:"identity_token"`
	AuthorizationCode string `json:"authorization_code"`
}

func (h *NativeHandler) registerAppleReauthenticationRoutes(g *gin.RouterGroup) {
	g.POST("/auth/apple/reauthenticate/challenge", nativeJSONEndpoint(true, func(ctx context.Context, token, ip string, _ struct{}) (any, error) {
		return h.accounts.AppleReauthenticateChallenge(ctx, token, ip)
	}))
	g.POST("/auth/apple/reauthenticate", nativeJSONEndpoint(true, func(ctx context.Context, token, ip string, req appleReauthenticationRequest) (any, error) {
		return h.accounts.AppleReauthenticate(ctx, token, req.ChallengeID, req.IdentityToken, req.AuthorizationCode, ip)
	}))
}

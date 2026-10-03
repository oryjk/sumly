package holdingshttp

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"reflect"
	"strings"

	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/holdings/domain"
	api "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	auth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	errs "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	envelope "gitee.com/oryjk/sumly/sumly_go/internal/shared/http"
	"github.com/gin-gonic/gin"
)

type Holdings interface {
	Get(context.Context, auth.Actor) (domain.Snapshot, error)
	Put(context.Context, auth.Actor, int64, domain.Document) (domain.Snapshot, error)
}
type Handler struct{ holdings Holdings }

func NewHandler(s Holdings) *Handler { return &Handler{s} }
func (h *Handler) RegisterAppRoutes(g *gin.RouterGroup) {
	g.GET("/holdings", h.Get)
	g.PUT("/holdings", h.Put)
}
func (h *Handler) Get(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	a, ok := authhttp.ActorFromContext(c)
	if !ok {
		api.WriteError(c, errs.ErrUnauthorized)
		return
	}
	got, err := h.holdings.Get(c.Request.Context(), a)
	if err != nil {
		api.WriteError(c, err)
		return
	}
	writeSnapshot(c, got)
}

type putRequest struct {
	ExpectedRevision int64       `json:"expectedRevision"`
	Document         documentDTO `json:"document"`
}

func (h *Handler) Put(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	a, ok := authhttp.ActorFromContext(c)
	if !ok {
		api.WriteError(c, errs.ErrUnauthorized)
		return
	}
	raw, err := io.ReadAll(io.LimitReader(c.Request.Body, domain.MaxBytes+1))
	if len(raw) > domain.MaxBytes {
		c.JSON(http.StatusRequestEntityTooLarge, envelope.Response[any]{Code: 413, Message: "持仓请求过大", Data: nil})
		return
	}
	if err != nil {
		api.WriteError(c, errs.ErrValidation)
		return
	}
	var req putRequest
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&req) != nil || decoder.Decode(new(any)) != io.EOF || !requiredFields(raw, reflect.TypeFor[putRequest]()) {
		api.WriteError(c, errs.ErrValidation)
		return
	}
	got, err := h.holdings.Put(c.Request.Context(), a, req.ExpectedRevision, req.Document.toDomain())
	if err != nil {
		api.WriteError(c, err)
		return
	}
	writeSnapshot(c, got)
}

// JSON's zero values would otherwise silently accept absent or null required
// money, date and boolean fields. Optional pointer fields may be omitted/null.
func requiredFields(raw json.RawMessage, t reflect.Type) bool {
	if t.Kind() == reflect.Pointer {
		if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
			return true
		}
		return requiredFields(raw, t.Elem())
	}
	if len(raw) == 0 || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return false
	}
	switch t.Kind() {
	case reflect.Struct:
		var obj map[string]json.RawMessage
		if json.Unmarshal(raw, &obj) != nil || obj == nil {
			return false
		}
		known := make(map[string]bool, t.NumField())
		for i := 0; i < t.NumField(); i++ {
			f := t.Field(i)
			name, opts, _ := strings.Cut(f.Tag.Get("json"), ",")
			known[name] = true
			value, ok := obj[name]
			if !ok && strings.Contains(opts, "omitempty") {
				continue
			}
			if !ok || !requiredFields(value, f.Type) {
				return false
			}
		}
		for name := range obj {
			if !known[name] {
				return false
			}
		}
	case reflect.Slice:
		var elements []json.RawMessage
		if json.Unmarshal(raw, &elements) != nil || elements == nil {
			return false
		}
		for _, el := range elements {
			if !requiredFields(el, t.Elem()) {
				return false
			}
		}
	}
	return true
}
func writeSnapshot(c *gin.Context, s domain.Snapshot) {
	raw, err := json.Marshal(envelope.Success(snapshotDTO{Revision: s.Revision, Document: documentFromDomain(s.Document)}))
	if err != nil || len(raw) > domain.MaxBytes {
		api.WriteError(c, errs.ErrInternal)
		return
	}
	c.Data(http.StatusOK, "application/json; charset=utf-8", raw)
}

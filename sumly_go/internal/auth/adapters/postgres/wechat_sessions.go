package postgres

import (
	"context"
	"errors"

	q "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"github.com/jackc/pgx/v5"
)

// LoginWechat 在一个事务内完成：定位或创建微信身份、必要时迁移旧裸
// openid 身份、插入会话。任一步失败整体回滚，不会出现「有身份没会话」、
// 「同�� openid 两个账户」或「持迁了一半」。
func (s *NativeStore) LoginWechat(ctx context.Context, appID, legacyAppID, openID string, session domain.Session) (u domain.User, err error) {
	if appID == "" || openID == "" {
		return u, domain.ErrInvalid
	}
	subject := application.WechatSubject(appID, openID)
	// 旧版本以裸 openid 作为 subject；只有 appid 已确认一致才迁移。
	migrateLegacy := legacyAppID != "" && legacyAppID == appID
	legacySubject := openID

	err = s.transaction(ctx, func(db *q.Queries) error {
		// 先锁 subject，避免并发首次注册创建两个账户
		if e := db.NativeLock(ctx, "wechat:"+subject); e != nil {
			return e
		}
		if migrateLegacy {
			// 旧身份与新身份可能并发迁移，锁后再取
			if e := db.NativeLock(ctx, "wechat:legacy:"+legacySubject); e != nil {
				return e
			}
		}

		if i, e := identity(ctx, db, "wechat", subject); e == nil {
			// 已存在：校验账户仍可用，不迁移、不改归属
			if e = userLock(ctx, db, i.User.ID); e != nil {
				return e
			}
			i, e = identity(ctx, db, "wechat", subject)
			if e != nil {
				return e
			}
			if i.User.Status != "active" {
				return domain.ErrCredentials
			}
			u = i.User
		} else if !errors.Is(e, domain.ErrCredentials) {
			return e
		} else {
			// 新身份：先尝试迁移旧用户，再决定是否新建
			var resolved *domain.User
			if migrateLegacy {
				legacy, le := db.NativeWechatLegacyUser(ctx, legacySubject)
				switch {
				case le == nil:
					// 旧身份已存在：复用其 user_id，不复制或重新归属持仓
					if e = userLock(ctx, db, legacy.UserID); e != nil {
						return e
					}
					existing, ee := identity(ctx, db, "wechat", legacySubject)
					if ee != nil {
						return ee
					}
					if existing.User.Status != "active" {
						return domain.ErrCredentials
					}
					// 旧用户可能已关联其它 appid 的微信身份，此时拒绝复用
					if current, ce := db.NativeSubjectByUser(ctx, q.NativeSubjectByUserParams{UserID: legacy.UserID, Provider: "wechat"}); ce == nil && current != subject && current != legacySubject {
						return domain.ErrCredentials
					}
					if e = db.NativeAttachWechatIdentity(ctx, q.NativeAttachWechatIdentityParams{
						UserID:       legacy.UserID,
						Subject:      subject,
						MigratedFrom: legacySubject,
					}); e != nil {
						return e
					}
					if e = db.NativeMarkWechatMigrated(ctx, q.NativeMarkWechatMigratedParams{
						Subject:      subject,
						UserID:       legacy.UserID,
						MigratedFrom: legacySubject,
					}); e != nil {
						return e
					}
					resolved = &existing.User
				case errors.Is(le, pgx.ErrNoRows):
					// 无旧身份，继续新建
				default:
					return le
				}
			}

			if resolved == nil {
				r, e := db.CreateUser(ctx, q.CreateUserParams{Openid: openID, Nickname: "微信用户"})
				if e != nil {
					return e
				}
				if e = db.NativeInsertIdentity(ctx, q.NativeInsertIdentityParams{
					UserID: r.ID, Provider: "wechat", Subject: subject,
				}); e != nil {
					return e
				}
				resolved = &domain.User{ID: r.ID, Nickname: r.Nickname, Status: r.Status, Provider: "wechat"}
			}
			if resolved.Status != "active" {
				return domain.ErrCredentials
			}
			u = *resolved
		}

		session.UserID = u.ID
		session.Provider = "wechat"
		return insertSession(ctx, db, session)
	})
	if err != nil {
		return domain.User{}, err
	}
	if u.Provider == "" {
		u.Provider = "wechat"
	}
	return u, nil
}

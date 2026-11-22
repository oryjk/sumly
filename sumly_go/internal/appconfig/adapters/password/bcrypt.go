package password

import (
	"fmt"

	"golang.org/x/crypto/bcrypt"
)

const (
	// BcryptCost 为管理员密码哈希固定使用的 cost。
	BcryptCost = 10

	// dummyBcryptHash 是合法的 cost=10 bcrypt 哈希，仅用于在账号不存在时执行等耗时哑校验，防止用户名枚举。
	dummyBcryptHash = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy"
)

// BcryptHasher 基于 golang.org/x/crypto/bcrypt 实现管理员密码哈希与校验。
type BcryptHasher struct {
	cost int
}

func NewBcryptHasher() *BcryptHasher {
	return &BcryptHasher{cost: BcryptCost}
}

func (h *BcryptHasher) Hash(password string) (string, error) {
	if len(password) > 72 {
		return "", fmt.Errorf("password exceeds bcrypt 72-byte limit")
	}
	hashed, err := bcrypt.GenerateFromPassword([]byte(password), h.cost)
	if err != nil {
		return "", fmt.Errorf("hash password: %w", err)
	}
	return string(hashed), nil
}

func (h *BcryptHasher) Compare(hash, password string) bool {
	if hash == "" || len(password) > 72 {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

func (h *BcryptHasher) DummyCompare(password string) {
	candidate := password
	if len(candidate) > 72 {
		candidate = candidate[:72]
	}
	_ = bcrypt.CompareHashAndPassword([]byte(dummyBcryptHash), []byte(candidate))
}

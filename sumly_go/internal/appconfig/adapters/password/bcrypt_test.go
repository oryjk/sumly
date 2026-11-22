package password

import (
	"strings"
	"testing"

	"golang.org/x/crypto/bcrypt"
)

func TestBcryptHasherHashCompareAndCost(t *testing.T) {
	hasher := NewBcryptHasher()

	hash, err := hasher.Hash("InitialPass#2026")
	if err != nil {
		t.Fatalf("Hash failed: %v", err)
	}
	if hash == "InitialPass#2026" {
		t.Fatal("hash must never equal plaintext password")
	}
	cost, err := bcrypt.Cost([]byte(hash))
	if err != nil {
		t.Fatalf("bcrypt.Cost failed: %v", err)
	}
	if cost != BcryptCost {
		t.Fatalf("cost=%d want %d", cost, BcryptCost)
	}

	if !hasher.Compare(hash, "InitialPass#2026") {
		t.Fatal("expected Compare to accept matching password")
	}
	if hasher.Compare(hash, "WrongPass#2026") {
		t.Fatal("expected Compare to reject wrong password")
	}
	if hasher.Compare("", "InitialPass#2026") {
		t.Fatal("expected Compare to reject empty hash")
	}

	tooLong := strings.Repeat("a", 73)
	if _, err := hasher.Hash(tooLong); err == nil {
		t.Fatal("expected >72-byte password Hash to fail")
	}
	if hasher.Compare(hash, tooLong) {
		t.Fatal("expected >72-byte password Compare to return false")
	}
}

func TestDummyBcryptHashIsValidCost10(t *testing.T) {
	cost, err := bcrypt.Cost([]byte(dummyBcryptHash))
	if err != nil {
		t.Fatalf("dummyBcryptHash invalid: %v", err)
	}
	if cost != BcryptCost {
		t.Fatalf("dummyBcryptHash cost=%d want %d", cost, BcryptCost)
	}
	hasher := NewBcryptHasher()
	hasher.DummyCompare("nonexistent-user-password")
	hasher.DummyCompare(strings.Repeat("x", 100))
}

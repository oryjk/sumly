package domain

import (
	"strings"
	"testing"
)

func TestValidateCategoryAndStatus(t *testing.T) {
	for _, raw := range []string{"suggestion", "bug", "data", "other", " bug "} {
		if _, err := ParseCategory(raw); err != nil {
			t.Fatalf("expected valid category %q, got err=%v", raw, err)
		}
	}
	if _, err := ParseCategory("invalid"); err == nil {
		t.Fatal("expected invalid category error")
	}

	for _, raw := range []string{"new", "in_progress", "resolved", "archived"} {
		if _, err := ParseStatus(raw); err != nil {
			t.Fatalf("expected valid status %q, got err=%v", raw, err)
		}
	}
	if _, err := ParseStatus("closed"); err == nil {
		t.Fatal("expected invalid status error")
	}
}

func TestValidateDeviceHashContentAndContact(t *testing.T) {
	if _, err := ValidateDeviceHash("  short "); err == nil {
		t.Fatal("expected short device_hash error")
	}
	if got, err := ValidateDeviceHash("  device_12345678  "); err != nil || got != "device_12345678" {
		t.Fatalf("ValidateDeviceHash got=%q err=%v", got, err)
	}
	if _, err := ValidateDeviceHash(strings.Repeat("a", 129)); err == nil {
		t.Fatal("expected overlong device_hash error")
	}

	// 5 Chinese characters (15 bytes) must pass
	if got, err := ValidateContent("  金价刷新慢  "); err != nil || got != "金价刷新慢" {
		t.Fatalf("expected 5 Chinese runes to pass, got=%q err=%v", got, err)
	}
	if _, err := ValidateContent("  太短了  "); err == nil {
		t.Fatal("expected 3 Chinese runes to fail")
	}
	if _, err := ValidateContent(strings.Repeat("金", 1001)); err == nil {
		t.Fatal("expected 1001 runes to fail")
	}

	if _, err := ValidateContact(strings.Repeat("x", 121)); err == nil {
		t.Fatal("expected contact > 120 runes to fail")
	}
	if got, err := ValidateContact("  user@example.com "); err != nil || got != "user@example.com" {
		t.Fatalf("ValidateContact got=%q err=%v", got, err)
	}
}

func TestValidateAttachmentsAndPath(t *testing.T) {
	if key, err := ValidateAttachmentPath("20261123", "abc_123-def.jpg"); err != nil || key != "feedback/20261123/abc_123-def.jpg" {
		t.Fatalf("ValidateAttachmentPath got=%q err=%v", key, err)
	}
	for _, tc := range [][2]string{
		{"2026112", "a.jpg"},
		{"../20261", "a.jpg"},
		{"20261123", "../secret.jpg"},
		{"20261123", "a/b.jpg"},
		{"20261123", "a.svg"},
		{"20261123", "a.gif"},
	} {
		if _, err := ValidateAttachmentPath(tc[0], tc[1]); err == nil {
			t.Fatalf("expected error for date=%q filename=%q", tc[0], tc[1])
		}
	}

	valid := []Attachment{
		{ObjectKey: "feedback/20261123/img1.jpg", URL: "/api/v1/app/feedback/attachments/20261123/img1.jpg"},
		{ObjectKey: "feedback/20261123/img2.png", URL: "https://cdn.example.com/feedback/20261123/img2.png"},
		{ObjectKey: "feedback/20261123/img3.webp", URL: "http://localhost:18090/api/v1/app/feedback/attachments/20261123/img3.webp"},
	}
	if out, err := ValidateAttachments(valid); err != nil || len(out) != 3 {
		t.Fatalf("expected 3 valid attachments, got len=%d err=%v", len(out), err)
	}

	tooMany := append(append([]Attachment{}, valid...), Attachment{ObjectKey: "feedback/20261123/img4.jpg", URL: "https://cdn.example.com/4.jpg"})
	if _, err := ValidateAttachments(tooMany); err == nil {
		t.Fatal("expected error for >3 attachments")
	}

	if _, err := ValidateAttachments([]Attachment{{ObjectKey: "feedback/20261123/img1.jpg", URL: "javascript:alert(1)"}}); err == nil {
		t.Fatal("expected javascript: URL rejection")
	}
	if _, err := ValidateAttachments([]Attachment{{ObjectKey: "other/20261123/img1.jpg", URL: "https://cdn.example.com/a.jpg"}}); err == nil {
		t.Fatal("expected non-feedback object_key rejection")
	}
}

func TestDetectAllowedImageType(t *testing.T) {
	cases := []struct {
		name     string
		data     []byte
		wantType string
		wantExt  string
		wantOK   bool
	}{
		{"jpeg", []byte{0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10}, "image/jpeg", ".jpg", true},
		{"png", []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00}, "image/png", ".png", true},
		{"webp", []byte("RIFF\x24\x00\x00\x00WEBPVP8 "), "image/webp", ".webp", true},
		{"gif", []byte("GIF89a123456"), "", "", false},
		{"svg", []byte("<svg xmlns='http://www.w3.org/2000/svg'></svg>"), "", "", false},
		{"text", []byte("plain text file"), "", "", false},
		{"empty", []byte{}, "", "", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ct, ext, ok := DetectAllowedImageType(tc.data)
			if ok != tc.wantOK || ct != tc.wantType || ext != tc.wantExt {
				t.Fatalf("got (%q, %q, %v), want (%q, %q, %v)", ct, ext, ok, tc.wantType, tc.wantExt, tc.wantOK)
			}
		})
	}
}

func TestBuildAttachmentPublicURL(t *testing.T) {
	if got := BuildAttachmentPublicURL("https://cdn.example.com/bucket/", "https://api.example.com", "20261123", "a1.jpg"); got != "https://cdn.example.com/bucket/feedback/20261123/a1.jpg" {
		t.Fatalf("prefix url=%q", got)
	}
	if got := BuildAttachmentPublicURL("", "https://api.example.com/", "20261123", "a1.jpg"); got != "https://api.example.com/api/v1/app/feedback/attachments/20261123/a1.jpg" {
		t.Fatalf("base url=%q", got)
	}
	if got := BuildAttachmentPublicURL("", "", "20261123", "a1.jpg"); got != "/api/v1/app/feedback/attachments/20261123/a1.jpg" {
		t.Fatalf("relative url=%q", got)
	}
}

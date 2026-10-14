package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func do(t *testing.T, h http.Handler, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestHealth(t *testing.T) {
	rec := do(t, NewServer().Routes(), "GET", "/healthz", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("got %d", rec.Code)
	}
	if rec.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatal("missing security headers")
	}
}

func TestCreateAndGet(t *testing.T) {
	h := NewServer().Routes()
	if rec := do(t, h, "POST", "/api/v1/items", `{"name":"widget"}`); rec.Code != http.StatusCreated {
		t.Fatalf("create: got %d %s", rec.Code, rec.Body)
	}
	rec := do(t, h, "GET", "/api/v1/items/1", "")
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "widget") {
		t.Fatalf("get: got %d %s", rec.Code, rec.Body)
	}
}

func TestRejectsBadInput(t *testing.T) {
	h := NewServer().Routes()
	cases := map[string]string{
		"empty name":    `{"name":"  "}`,
		"unknown field": `{"name":"a","admin":true}`,
		"not json":      `<script>`,
		"too long":      `{"name":"` + strings.Repeat("x", 101) + `"}`,
	}
	for name, body := range cases {
		if rec := do(t, h, "POST", "/api/v1/items", body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s: got %d", name, rec.Code)
		}
	}
	if rec := do(t, h, "GET", "/api/v1/items/abc", ""); rec.Code != http.StatusBadRequest {
		t.Errorf("bad id: got %d", rec.Code)
	}
}

// Package api implements a small in-memory "items" REST service used as the
// target for the DevSecOps pipeline (SAST, DAST, image scanning, admission).
package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"sync"
)

const maxBodyBytes = 1 << 16 // 64 KiB

type Item struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

type Server struct {
	mu     sync.RWMutex
	items  map[int]Item
	nextID int
}

func NewServer() *Server {
	return &Server{items: make(map[int]Item), nextID: 1}
}

// Routes returns the HTTP handler with security headers applied to every response.
func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("GET /api/v1/items", s.listItems)
	mux.HandleFunc("POST /api/v1/items", s.createItem)
	mux.HandleFunc("GET /api/v1/items/{id}", s.getItem)
	return securityHeaders(mux)
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) listItems(w http.ResponseWriter, _ *http.Request) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Item, 0, len(s.items))
	for i := 1; i < s.nextID; i++ {
		if it, ok := s.items[i]; ok {
			out = append(out, it)
		}
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) createItem(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name string `json:"name"`
	}
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	name := strings.TrimSpace(in.Name)
	if err := validateName(name); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	s.mu.Lock()
	it := Item{ID: s.nextID, Name: name}
	s.items[it.ID] = it
	s.nextID++
	s.mu.Unlock()

	writeJSON(w, http.StatusCreated, it)
}

func (s *Server) getItem(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(r.PathValue("id"))
	if err != nil || id < 1 {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}
	s.mu.RLock()
	it, ok := s.items[id]
	s.mu.RUnlock()
	if !ok {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	writeJSON(w, http.StatusOK, it)
}

func validateName(name string) error {
	if name == "" || len(name) > 100 {
		return errors.New("name must be 1-100 characters")
	}
	return nil
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Cache-Control", "no-store")
		h.Set("Cross-Origin-Resource-Policy", "same-origin")
		h.Set("Permissions-Policy", "geolocation=(), camera=(), microphone=()")
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

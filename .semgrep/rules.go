//go:build semgreptest

// Test fixtures for .semgrep/rules.yml (`semgrep --test .semgrep`).
// Excluded from the build by the tag above and from scans by .semgrepignore.
package fixtures

import (
	"context"
	"crypto/tls"
	"database/sql"
	"fmt"
	"html/template"
	"net/http"
)

func sqlCases(ctx context.Context, db *sql.DB, id, name string) {
	// ruleid: go-sql-string-building
	db.Query(fmt.Sprintf("SELECT * FROM items WHERE id = %s", id))
	// ruleid: go-sql-string-building
	db.ExecContext(ctx, "DELETE FROM items WHERE name = '"+name+"'")
	// ok: go-sql-string-building
	db.Query("SELECT * FROM items WHERE id = $1", id)
}

func htmlCases(userInput string) {
	// ruleid: go-unescaped-html
	_ = template.HTML(userInput)
	// ok: go-unescaped-html
	_ = template.HTML("<b>static</b>")
}

func serverCases(h http.Handler) {
	// ruleid: go-http-server-no-timeouts
	_ = http.ListenAndServe(":8080", h)
}

func tlsCases() {
	// ruleid: go-tls-insecure-skip-verify
	_ = &tls.Config{InsecureSkipVerify: true}
	// ok: go-tls-insecure-skip-verify
	_ = &tls.Config{MinVersion: tls.VersionTLS12}
}

package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeConfig(t *testing.T, dir, contents string) string {
	t.Helper()

	path := filepath.Join(dir, configFilename)
	if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}
	return path
}

func chdir(t *testing.T, dir string) {
	t.Helper()

	old, err := os.Getwd()
	if err != nil {
		t.Fatalf("failed to get working directory: %v", err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatalf("failed to change working directory: %v", err)
	}
	t.Cleanup(func() {
		if err := os.Chdir(old); err != nil {
			t.Fatalf("failed to restore working directory: %v", err)
		}
	})
}

func TestLoadFromWorkingDirectory(t *testing.T) {
	t.Setenv(EnvConfigPath, "")

	dir := t.TempDir()
	writeConfig(t, dir, "title = \"from-cwd\"\n")
	chdir(t, dir)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.Title != "from-cwd" {
		t.Fatalf("unexpected title: %q", cfg.Title)
	}
}

func TestLoadFromExplicitPath(t *testing.T) {
	dir := t.TempDir()
	path := writeConfig(t, dir, "title = \"from-env\"\nconverters = [{from = \"fb2\", to = \"epub\", command = \"fbc\"}]\n")
	t.Setenv(EnvConfigPath, path)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.Title != "from-env" {
		t.Fatalf("unexpected title: %q", cfg.Title)
	}
	if len(cfg.Converters) != 1 || cfg.Converters[0].To != "epub" {
		t.Fatalf("unexpected converters: %+v", cfg.Converters)
	}
}

func TestLoadExplicitPathMissing(t *testing.T) {
	t.Setenv(EnvConfigPath, filepath.Join(t.TempDir(), "missing.toml"))

	if _, err := Load(); err == nil {
		t.Fatal("expected error for missing explicit config")
	}
}

func TestLoadReportsSearchedPaths(t *testing.T) {
	t.Setenv(EnvConfigPath, "")

	dir := t.TempDir()
	chdir(t, dir)

	if _, err := Load(); err == nil {
		t.Skip("a config file exists in one of the default locations")
	} else if !strings.Contains(err.Error(), filepath.Join(dir, configFilename)) {
		t.Fatalf("error does not list searched paths: %v", err)
	}
}

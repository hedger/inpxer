package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/pelletier/go-toml/v2"
)

const configFilename = "inpxer.toml"

// EnvConfigPath points at an explicit configuration file.
const EnvConfigPath = "INPXER_CONFIG"

type MyConfig struct {
	Storage          string       `toml:"storage"`
	Language         string       `toml:"language"`
	Title            string       `toml:"title"`
	AuthorNameFormat string       `toml:"author_name_format"`
	IndexPath        string       `toml:"index_path"`
	LibraryPath      string       `toml:"library_path"`
	Listen           string       `toml:"listen"`
	FullUrl          string       `toml:"full_url"`
	Converters       []*Converter `toml:"converters"`
}

type Converter struct {
	From      string `toml:"from"`
	To        string `toml:"to"`
	Command   string `toml:"command"`
	Arguments string `toml:"arguments"`
}

// Load reads configuration from the first existing file in the search path.
// Lookup does not rely on the working directory alone, so both
// `/data/inpxer.toml` (recommended inside Docker) and `/inpxer.toml`
// (config mounted at container root) keep working.
func Load() (*MyConfig, error) {
	if file := os.Getenv(EnvConfigPath); file != "" {
		return loadFile(file)
	}

	candidates := searchPaths()
	for _, file := range candidates {
		if _, err := os.Stat(file); err != nil {
			continue
		}
		return loadFile(file)
	}

	return nil, fmt.Errorf("config file %s not found, looked in: %s (or set %s)",
		configFilename, strings.Join(candidates, ", "), EnvConfigPath)
}

func loadFile(file string) (*MyConfig, error) {
	data, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}

	var cfg MyConfig
	if err := toml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("%s: %w", file, err)
	}

	return &cfg, nil
}

// searchPaths returns candidate config locations, most specific first.
func searchPaths() []string {
	var paths []string
	seen := make(map[string]struct{})
	add := func(path string) {
		if _, ok := seen[path]; ok {
			return
		}
		seen[path] = struct{}{}
		paths = append(paths, path)
	}

	if wd, err := os.Getwd(); err == nil {
		add(filepath.Join(wd, configFilename))
	} else {
		add(configFilename)
	}

	add(filepath.Join("/data", configFilename))
	add(filepath.Join("/", configFilename))

	if exe, err := os.Executable(); err == nil {
		add(filepath.Join(filepath.Dir(exe), configFilename))
	}

	return paths
}

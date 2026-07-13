package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type yamlSetting struct {
	section string
	key     string
	value   interface{}
}

func requiredEnv(name string) (string, error) {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return "", fmt.Errorf("missing required environment variable: %s", name)
	}
	return value, nil
}

func readSecret(path string) (string, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(content)), nil
}

func yamlScalar(value interface{}) string {
	switch typed := value.(type) {
	case bool:
		if typed {
			return "true"
		}
		return "false"
	case int:
		return fmt.Sprintf("%d", typed)
	case string:
		encoded, _ := json.Marshal(typed)
		return string(encoded)
	default:
		encoded, _ := json.Marshal(typed)
		return string(encoded)
	}
}

func topLevelSection(line string, section string) bool {
	if strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t") {
		return false
	}
	withoutComment, _, _ := strings.Cut(strings.TrimSpace(line), "#")
	return strings.TrimSpace(withoutComment) == section+":"
}

func isNextTopLevelSection(line string) bool {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" || strings.HasPrefix(trimmed, "#") {
		return false
	}
	return !strings.HasPrefix(line, " ") && strings.Contains(trimmed, ":")
}

func sectionKey(line string) string {
	if !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "\t") {
		return ""
	}
	key, _, found := strings.Cut(strings.TrimSpace(line), ":")
	if !found {
		return ""
	}
	return strings.TrimSpace(key)
}

func insertLine(lines []string, index int, line string) []string {
	lines = append(lines, "")
	copy(lines[index+1:], lines[index:])
	lines[index] = line
	return lines
}

func upsert(lines []string, section string, key string, value interface{}) []string {
	sectionStart := -1
	for index, line := range lines {
		if topLevelSection(line, section) {
			sectionStart = index
			break
		}
	}

	if sectionStart == -1 {
		if len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) != "" {
			lines = append(lines, "")
		}
		lines = append(lines, section+":")
		lines = append(lines, fmt.Sprintf("  %s: %s", key, yamlScalar(value)))
		return lines
	}

	insertAt := len(lines)
	for index := sectionStart + 1; index < len(lines); index++ {
		line := lines[index]
		if isNextTopLevelSection(line) {
			insertAt = index
			break
		}
		if sectionKey(line) == key {
			lines[index] = fmt.Sprintf("  %s: %s", key, yamlScalar(value))
			return lines
		}
	}

	return insertLine(lines, insertAt, fmt.Sprintf("  %s: %s", key, yamlScalar(value)))
}

func readLines(path string) ([]string, error) {
	content, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return []string{}, nil
	}
	if err != nil {
		return nil, err
	}
	text := strings.ReplaceAll(string(content), "\r\n", "\n")
	text = strings.TrimRight(text, "\n")
	if text == "" {
		return []string{}, nil
	}
	return strings.Split(text, "\n"), nil
}

func writeLines(path string, lines []string) error {
	var mode os.FileMode = 0640
	if info, err := os.Stat(path); err == nil {
		mode = info.Mode().Perm()
	}

	if err := os.MkdirAll(filepath.Dir(path), 0750); err != nil {
		return err
	}
	content := strings.Join(lines, "\n") + "\n"
	tmp := path + ".home-ops.tmp"
	if err := os.WriteFile(tmp, []byte(content), 0640); err != nil {
		return err
	}
	if err := os.Chmod(tmp, mode); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func run() error {
	configFile, err := requiredEnv("HOME_OPS_BAZARR_CONFIG_FILE")
	if err != nil {
		return err
	}
	sonarrKeyFile, err := requiredEnv("HOME_OPS_SONARR_API_KEY_FILE")
	if err != nil {
		return err
	}
	radarrKeyFile, err := requiredEnv("HOME_OPS_RADARR_API_KEY_FILE")
	if err != nil {
		return err
	}

	sonarrKey, err := readSecret(sonarrKeyFile)
	if err != nil {
		return err
	}
	radarrKey, err := readSecret(radarrKeyFile)
	if err != nil {
		return err
	}

	lines, err := readLines(configFile)
	if err != nil {
		return err
	}

	for _, setting := range []yamlSetting{
		{"general", "use_sonarr", true},
		{"general", "use_radarr", true},
		{"general", "default_und_audio_lang", "en"},
		{"general", "default_und_embedded_subtitles_lang", "en"},
		{"sonarr", "ip", "127.0.0.1"},
		{"sonarr", "port", 8989},
		{"sonarr", "base_url", ""},
		{"sonarr", "ssl", false},
		{"sonarr", "apikey", sonarrKey},
		{"radarr", "ip", "127.0.0.1"},
		{"radarr", "port", 7878},
		{"radarr", "base_url", ""},
		{"radarr", "ssl", false},
		{"radarr", "apikey", radarrKey},
	} {
		lines = upsert(lines, setting.section, setting.key, setting.value)
	}

	if err := writeLines(configFile, lines); err != nil {
		return err
	}
	fmt.Println("Bazarr: configured Sonarr and Radarr")
	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

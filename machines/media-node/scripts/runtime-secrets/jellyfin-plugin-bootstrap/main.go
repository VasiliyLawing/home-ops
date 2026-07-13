package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

type desiredState struct {
	Repositories []repository    `json:"repositories"`
	Packages     []pluginPackage `json:"packages"`
}

type repository struct {
	Name    string `json:"Name"`
	Url     string `json:"Url"`
	Enabled bool   `json:"Enabled"`
}

type pluginPackage struct {
	Name          string `json:"name"`
	RepositoryUrl string `json:"repositoryUrl"`
}

type installedPlugin struct {
	Name string `json:"Name"`
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
	value := strings.TrimSpace(string(content))
	if value == "" {
		return "", fmt.Errorf("%s is empty", path)
	}
	return value, nil
}

func normalizeBaseURL(value string) string {
	return strings.TrimRight(value, "/")
}

func request(method string, endpoint string, apiKey string, payload any) ([]byte, error) {
	var body io.Reader
	if payload != nil {
		content, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}
		body = bytes.NewReader(content)
	}

	req, err := http.NewRequest(method, endpoint, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("X-Emby-Token", apiKey)
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	responseBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%s %s returned %d: %s", method, endpoint, resp.StatusCode, strings.TrimSpace(string(responseBody)))
	}
	return responseBody, nil
}

func getJSON[T any](endpoint string, apiKey string) (T, error) {
	var value T
	body, err := request("GET", endpoint, apiKey, nil)
	if err != nil {
		return value, err
	}
	return value, json.Unmarshal(body, &value)
}

func mergeRepositories(existing []repository, desired []repository) []repository {
	merged := make([]repository, 0, len(existing)+len(desired))
	indexByURL := map[string]int{}

	for _, repo := range existing {
		key := strings.ToLower(repo.Url)
		indexByURL[key] = len(merged)
		merged = append(merged, repo)
	}

	for _, repo := range desired {
		key := strings.ToLower(repo.Url)
		if index, ok := indexByURL[key]; ok {
			merged[index].Name = repo.Name
			merged[index].Enabled = repo.Enabled
			continue
		}
		indexByURL[key] = len(merged)
		merged = append(merged, repo)
	}

	return merged
}

func ensureRepositories(baseURL string, apiKey string, desired []repository) error {
	existing, err := getJSON[[]repository](baseURL+"/Repositories", apiKey)
	if err != nil {
		return err
	}
	merged := mergeRepositories(existing, desired)
	if _, err := request("POST", baseURL+"/Repositories", apiKey, merged); err != nil {
		return err
	}
	for _, repo := range desired {
		fmt.Printf("Jellyfin plugins: ensured repository %s\n", repo.Name)
	}
	return nil
}

func installedPluginNames(baseURL string, apiKey string) (map[string]bool, error) {
	plugins, err := getJSON[[]installedPlugin](baseURL+"/Plugins", apiKey)
	if err != nil {
		return nil, err
	}
	names := map[string]bool{}
	for _, plugin := range plugins {
		names[strings.ToLower(plugin.Name)] = true
	}
	return names, nil
}

func installPackage(baseURL string, apiKey string, pkg pluginPackage) error {
	query := url.Values{}
	query.Set("repositoryUrl", pkg.RepositoryUrl)
	endpoint := baseURL + "/Packages/Installed/" + url.PathEscape(pkg.Name) + "?" + query.Encode()
	_, err := request("POST", endpoint, apiKey, nil)
	return err
}

func installPackages(baseURL string, apiKey string, packages []pluginPackage) error {
	installed, err := installedPluginNames(baseURL, apiKey)
	if err != nil {
		return err
	}
	for _, pkg := range packages {
		if installed[strings.ToLower(pkg.Name)] {
			fmt.Printf("Jellyfin plugins: %s already installed\n", pkg.Name)
			continue
		}
		if err := installPackage(baseURL, apiKey, pkg); err != nil {
			return fmt.Errorf("install %s: %w", pkg.Name, err)
		}
		fmt.Printf("Jellyfin plugins: installed %s\n", pkg.Name)
	}
	return nil
}

func run() error {
	configFile, err := requiredEnv("HOME_OPS_JELLYFIN_PLUGIN_CONFIG")
	if err != nil {
		return err
	}
	apiKeyFile, err := requiredEnv("HOME_OPS_JELLYFIN_API_KEY_FILE")
	if err != nil {
		return err
	}
	baseURL := strings.TrimSpace(os.Getenv("HOME_OPS_JELLYFIN_BASE_URL"))
	if baseURL == "" {
		baseURL = "http://127.0.0.1:8096"
	}
	baseURL = normalizeBaseURL(baseURL)

	apiKey, err := readSecret(apiKeyFile)
	if err != nil {
		return err
	}

	content, err := os.ReadFile(configFile)
	if err != nil {
		return err
	}
	var desired desiredState
	if err := json.Unmarshal(content, &desired); err != nil {
		return err
	}

	if err := ensureRepositories(baseURL, apiKey, desired.Repositories); err != nil {
		return err
	}
	if err := installPackages(baseURL, apiKey, desired.Packages); err != nil {
		return err
	}

	fmt.Println("Jellyfin plugins: finished; restart Jellyfin to load newly installed plugins")
	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

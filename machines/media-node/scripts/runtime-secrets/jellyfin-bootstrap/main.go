package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

type virtualFolder struct {
	Name           string   `json:"Name"`
	CollectionType string   `json:"CollectionType"`
	Locations      []string `json:"Locations"`
}

type desiredLibrary struct {
	Name           string
	CollectionType string
	Path           string
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

func request(method string, endpoint string, apiKey string) ([]byte, error) {
	req, err := http.NewRequest(method, endpoint, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-Emby-Token", apiKey)
	req.Header.Set("Accept", "application/json")

	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%s %s returned %d: %s", method, endpoint, resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return body, nil
}

func getLibraries(baseURL string, apiKey string) ([]virtualFolder, error) {
	body, err := request("GET", strings.TrimRight(baseURL, "/")+"/Library/VirtualFolders", apiKey)
	if err != nil {
		return nil, err
	}
	var libraries []virtualFolder
	if err := json.Unmarshal(body, &libraries); err != nil {
		return nil, err
	}
	return libraries, nil
}

func hasLibrary(libraries []virtualFolder, name string) bool {
	for _, library := range libraries {
		if strings.EqualFold(library.Name, name) {
			return true
		}
	}
	return false
}

func createLibrary(baseURL string, apiKey string, library desiredLibrary) error {
	params := url.Values{}
	params.Set("name", library.Name)
	params.Set("collectionType", library.CollectionType)
	params.Set("paths", library.Path)
	params.Set("refreshLibrary", "false")
	endpoint := strings.TrimRight(baseURL, "/") + "/Library/VirtualFolders?" + params.Encode()
	_, err := request("POST", endpoint, apiKey)
	return err
}

func ensureLibrary(baseURL string, apiKey string, library desiredLibrary) error {
	libraries, err := getLibraries(baseURL, apiKey)
	if err != nil {
		return err
	}
	if hasLibrary(libraries, library.Name) {
		fmt.Printf("Jellyfin: library %s already exists\n", library.Name)
		return nil
	}
	if err := createLibrary(baseURL, apiKey, library); err != nil {
		return err
	}
	fmt.Printf("Jellyfin: created %s library at %s\n", library.Name, library.Path)
	return nil
}

func ensureWithRetry(baseURL string, apiKey string, libraries []desiredLibrary) error {
	var lastErr error
	for attempt := 1; attempt <= 30; attempt++ {
		ok := true
		for _, library := range libraries {
			if err := ensureLibrary(baseURL, apiKey, library); err != nil {
				lastErr = err
				ok = false
				fmt.Fprintf(os.Stderr, "Jellyfin: waiting for API readiness (%d/30): %v\n", attempt, err)
				break
			}
		}
		if ok {
			return nil
		}
		time.Sleep(2 * time.Second)
	}
	return lastErr
}

func run() error {
	apiKeyFile, err := requiredEnv("HOME_OPS_JELLYFIN_API_KEY_FILE")
	if err != nil {
		return err
	}
	apiKey, err := readSecret(apiKeyFile)
	if err != nil {
		return err
	}
	baseURL := strings.TrimSpace(os.Getenv("HOME_OPS_JELLYFIN_BASE_URL"))
	if baseURL == "" {
		baseURL = "http://127.0.0.1:8096"
	}

	libraries := []desiredLibrary{
		{Name: "Movies", CollectionType: "movies", Path: "/mnt/nas/data/media/movies"},
		{Name: "TV", CollectionType: "tvshows", Path: "/mnt/nas/data/media/tv"},
	}
	return ensureWithRetry(baseURL, apiKey, libraries)
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

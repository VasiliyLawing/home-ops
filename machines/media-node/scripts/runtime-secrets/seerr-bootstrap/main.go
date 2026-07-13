package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type qualityProfile struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

type rootFolder struct {
	Path string `json:"path"`
}

type jellyfinSystemInfo struct {
	ID         string `json:"Id"`
	ServerName string `json:"ServerName"`
}

type jellyfinMediaFoldersResponse struct {
	Items []jellyfinMediaFolder `json:"Items"`
}

type jellyfinMediaFolder struct {
	ID             string `json:"Id"`
	Name           string `json:"Name"`
	Type           string `json:"Type"`
	CollectionType string `json:"CollectionType"`
}

func requiredEnv(name string) (string, error) {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return "", fmt.Errorf("missing required environment variable: %s", name)
	}
	return value, nil
}

func optionalEnv(name string) string {
	return strings.TrimSpace(os.Getenv(name))
}

func readSecret(path string) (string, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(content)), nil
}

func readOptionalSecret(path string) (string, bool, error) {
	if strings.TrimSpace(path) == "" {
		return "", false, nil
	}
	content, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	value := strings.TrimSpace(string(content))
	if value == "" {
		return "", false, nil
	}
	return value, true, nil
}

func normalizeBaseURL(url string) string {
	return strings.TrimRight(url, "/")
}

func request(method string, url string, apiKey string, body interface{}) ([]byte, error) {
	var reader io.Reader
	if body != nil {
		payload, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(payload)
	}

	req, err := http.NewRequest(method, url, reader)
	if err != nil {
		return nil, err
	}
	if apiKey != "" {
		req.Header.Set("X-Api-Key", apiKey)
		req.Header.Set("X-Emby-Token", apiKey)
	}
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	client := &http.Client{Timeout: 15 * time.Second}
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
		return nil, fmt.Errorf("%s %s returned %d: %s", method, url, resp.StatusCode, strings.TrimSpace(string(responseBody)))
	}

	return responseBody, nil
}

func decodeGet[T any](url string, apiKey string) (T, error) {
	var value T
	body, err := request("GET", url, apiKey, nil)
	if err != nil {
		return value, err
	}
	err = json.Unmarshal(body, &value)
	return value, err
}

func selectProfile(baseURL string, apiKey string, preferredName string) (qualityProfile, error) {
	profiles, err := decodeGet[[]qualityProfile](normalizeBaseURL(baseURL)+"/api/v3/qualityprofile", apiKey)
	if err != nil {
		return qualityProfile{}, err
	}
	if len(profiles) == 0 {
		return qualityProfile{}, fmt.Errorf("%s has no quality profiles", baseURL)
	}
	for _, profile := range profiles {
		if strings.EqualFold(profile.Name, preferredName) {
			return profile, nil
		}
	}
	return profiles[0], nil
}

func ensureRootFolder(baseURL string, apiKey string, desiredPath string) error {
	folders, err := decodeGet[[]rootFolder](normalizeBaseURL(baseURL)+"/api/v3/rootfolder", apiKey)
	if err != nil {
		return err
	}
	for _, folder := range folders {
		if folder.Path == desiredPath {
			return nil
		}
	}
	_, err = request("POST", normalizeBaseURL(baseURL)+"/api/v3/rootfolder", apiKey, map[string]string{
		"path": desiredPath,
	})
	return err
}

func asMap(value interface{}) map[string]interface{} {
	existing, ok := value.(map[string]interface{})
	if ok {
		return existing
	}
	return map[string]interface{}{}
}

func readSettings(path string) (map[string]interface{}, error) {
	content, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return map[string]interface{}{}, nil
	}
	if err != nil {
		return nil, err
	}
	settings := map[string]interface{}{}
	if strings.TrimSpace(string(content)) == "" {
		return settings, nil
	}
	if err := json.Unmarshal(content, &settings); err != nil {
		return nil, err
	}
	return settings, nil
}

func writeSettings(path string, settings map[string]interface{}) error {
	var mode os.FileMode = 0640
	if info, err := os.Stat(path); err == nil {
		mode = info.Mode().Perm()
	}

	if err := os.MkdirAll(filepath.Dir(path), 0750); err != nil {
		return err
	}
	content, err := json.MarshalIndent(settings, "", " ")
	if err != nil {
		return err
	}
	content = append(content, '\n')
	tmp := path + ".home-ops.tmp"
	if err := os.WriteFile(tmp, content, 0640); err != nil {
		return err
	}
	if err := os.Chmod(tmp, mode); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func arrDisplayName(kind string) (string, error) {
	switch kind {
	case "sonarr":
		return "Sonarr", nil
	case "radarr":
		return "Radarr", nil
	default:
		return "", fmt.Errorf("unsupported Arr service kind: %s", kind)
	}
}

func configureArr(settings map[string]interface{}, kind string, apiKey string, baseURL string, rootPath string, preferredProfile string) error {
	if err := ensureRootFolder(baseURL, apiKey, rootPath); err != nil {
		return err
	}
	profile, err := selectProfile(baseURL, apiKey, preferredProfile)
	if err != nil {
		return err
	}
	displayName, err := arrDisplayName(kind)
	if err != nil {
		return err
	}

	entry := map[string]interface{}{
		"id":                0,
		"name":              displayName,
		"hostname":          "127.0.0.1",
		"port":              7878,
		"apiKey":            apiKey,
		"useSsl":            false,
		"baseUrl":           "",
		"activeProfileId":   profile.ID,
		"activeProfileName": profile.Name,
		"activeDirectory":   rootPath,
		"tags":              []interface{}{},
		"is4k":              false,
		"isDefault":         true,
		"syncEnabled":       true,
		"preventSearch":     false,
		"tagRequests":       false,
		"overrideRule":      []interface{}{},
	}

	if kind == "sonarr" {
		entry["port"] = 8989
		entry["seriesType"] = "standard"
		entry["animeSeriesType"] = "anime"
		entry["activeAnimeProfileId"] = profile.ID
		entry["activeAnimeProfileName"] = profile.Name
		entry["activeAnimeDirectory"] = rootPath
		entry["animeTags"] = []interface{}{}
		entry["enableSeasonFolders"] = true
		entry["monitorNewItems"] = "all"
	} else {
		entry["minimumAvailability"] = "released"
	}

	settings[kind] = []interface{}{entry}
	return nil
}

func jellyfinLibraryType(collectionType string) (string, bool) {
	switch collectionType {
	case "movies":
		return "movie", true
	case "tvshows":
		return "show", true
	default:
		return "", false
	}
}

func getJellyfinLibraries(baseURL string, apiKey string) ([]interface{}, error) {
	response, err := decodeGet[jellyfinMediaFoldersResponse](normalizeBaseURL(baseURL)+"/Library/MediaFolders", apiKey)
	if err != nil {
		return nil, err
	}

	libraries := []interface{}{}
	for _, folder := range response.Items {
		if folder.Type != "CollectionFolder" {
			continue
		}
		libraryType, ok := jellyfinLibraryType(folder.CollectionType)
		if !ok {
			continue
		}
		libraries = append(libraries, map[string]interface{}{
			"id":      folder.ID,
			"name":    folder.Name,
			"enabled": true,
			"type":    libraryType,
		})
	}

	if len(libraries) == 0 {
		return nil, fmt.Errorf("Jellyfin returned no Movies/TV media folders")
	}
	return libraries, nil
}

func configureJellyfin(settings map[string]interface{}, apiKey string, baseURL string) error {
	info, err := decodeGet[jellyfinSystemInfo](normalizeBaseURL(baseURL)+"/System/Info", apiKey)
	if err != nil {
		return err
	}
	libraries, err := getJellyfinLibraries(baseURL, apiKey)
	if err != nil {
		return err
	}
	jellyfin := asMap(settings["jellyfin"])
	jellyfin["name"] = info.ServerName
	jellyfin["ip"] = "127.0.0.1"
	jellyfin["port"] = 8096
	jellyfin["useSsl"] = false
	jellyfin["urlBase"] = ""
	jellyfin["externalHostname"] = "http://media-node:8096"
	jellyfin["jellyfinForgotPasswordUrl"] = ""
	jellyfin["serverId"] = info.ID
	jellyfin["apiKey"] = apiKey
	jellyfin["libraries"] = libraries
	settings["jellyfin"] = jellyfin

	main := asMap(settings["main"])
	main["mediaServerType"] = 2
	main["applicationTitle"] = "Seerr"
	main["applicationUrl"] = "http://media-node:5055"
	main["localLogin"] = true
	main["mediaServerLogin"] = true
	settings["main"] = main
	return nil
}

func run() error {
	settingsFile, err := requiredEnv("HOME_OPS_SEERR_SETTINGS_FILE")
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
	jellyfinKeyFile := optionalEnv("HOME_OPS_JELLYFIN_API_KEY_FILE")

	sonarrKey, err := readSecret(sonarrKeyFile)
	if err != nil {
		return err
	}
	radarrKey, err := readSecret(radarrKeyFile)
	if err != nil {
		return err
	}

	settings, err := readSettings(settingsFile)
	if err != nil {
		return err
	}

	if err := configureArr(settings, "sonarr", sonarrKey, "http://127.0.0.1:8989", "/mnt/nas/data/media/tv", "WEB-1080p"); err != nil {
		return fmt.Errorf("configure Sonarr: %w", err)
	}
	if err := configureArr(settings, "radarr", radarrKey, "http://127.0.0.1:7878", "/mnt/nas/data/media/movies", "HD Bluray + WEB"); err != nil {
		return fmt.Errorf("configure Radarr: %w", err)
	}

	jellyfinKey, ok, err := readOptionalSecret(jellyfinKeyFile)
	if err != nil {
		return err
	}
	if ok {
		if err := configureJellyfin(settings, jellyfinKey, "http://127.0.0.1:8096"); err != nil {
			return fmt.Errorf("configure Jellyfin: %w", err)
		}
		fmt.Println("Seerr: configured Jellyfin, Sonarr, and Radarr")
	} else {
		fmt.Printf("Seerr: configured Sonarr and Radarr; skipping Jellyfin because %s is missing or empty\n", jellyfinKeyFile)
	}

	return writeSettings(settingsFile, settings)
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

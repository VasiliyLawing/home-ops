package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// Adds a "Jellyfin Library Update" notification (Emby/Jellyfin connection) to
// Sonarr and Radarr so that on import/upgrade/rename they tell Jellyfin to scan
// the affected path immediately. /mnt/nas is NFS, where Jellyfin's real-time
// file monitor never fires, so without this new media only appears on the
// scheduled library scan.

const notificationName = "Jellyfin Library Update"

type field struct {
	Name  string      `json:"name"`
	Value interface{} `json:"value,omitempty"`
}

type notification struct {
	ID                 int     `json:"id,omitempty"`
	Name               string  `json:"name"`
	OnGrab             bool    `json:"onGrab"`
	OnDownload         bool    `json:"onDownload"`
	OnUpgrade          bool    `json:"onUpgrade"`
	OnRename           bool    `json:"onRename"`
	Implementation     string  `json:"implementation"`
	ImplementationName string  `json:"implementationName"`
	ConfigContract     string  `json:"configContract"`
	Fields             []field `json:"fields"`
}

type appConfig struct {
	Name    string
	BaseURL string
	APIKey  string
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

func request(method, url, apiKey string, body interface{}) ([]byte, error) {
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
	req.Header.Set("X-Api-Key", apiKey)
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

func normalizeBaseURL(url string) string {
	return strings.TrimRight(url, "/")
}

func hasField(fields []field, name string) bool {
	for _, item := range fields {
		if item.Name == name {
			return true
		}
	}
	return false
}

func setFieldIfPresent(fields []field, name string, value interface{}) []field {
	for index := range fields {
		if fields[index].Name == name {
			fields[index].Value = value
			return fields
		}
	}
	return fields
}

// applyDesiredFields sets the connection fields we care about, leaving any
// schema field the running arr version does not expose untouched.
func applyDesiredFields(fields []field, host string, port int, apiKey string) []field {
	fields = setFieldIfPresent(fields, "host", host)
	fields = setFieldIfPresent(fields, "port", port)
	fields = setFieldIfPresent(fields, "useSsl", false)
	fields = setFieldIfPresent(fields, "urlBase", "")
	fields = setFieldIfPresent(fields, "apiKey", apiKey)
	fields = setFieldIfPresent(fields, "notify", false)
	fields = setFieldIfPresent(fields, "updateLibrary", true)
	return fields
}

func jellyfinSchema(app appConfig) (notification, error) {
	body, err := request("GET", normalizeBaseURL(app.BaseURL)+"/api/v3/notification/schema", app.APIKey, nil)
	if err != nil {
		return notification{}, err
	}

	var schemas []notification
	if err := json.Unmarshal(body, &schemas); err != nil {
		return notification{}, err
	}

	for _, schema := range schemas {
		if schema.Implementation == "MediaBrowser" {
			if !hasField(schema.Fields, "updateLibrary") {
				return notification{}, fmt.Errorf("%s: MediaBrowser schema missing updateLibrary field", app.Name)
			}
			schema.ID = 0
			schema.Name = notificationName
			schema.OnGrab = false
			schema.OnDownload = true
			schema.OnUpgrade = true
			schema.OnRename = true
			return schema, nil
		}
	}

	return notification{}, fmt.Errorf("%s: MediaBrowser notification schema not found", app.Name)
}

func existingNotification(app appConfig, name string) (*notification, error) {
	body, err := request("GET", normalizeBaseURL(app.BaseURL)+"/api/v3/notification", app.APIKey, nil)
	if err != nil {
		return nil, err
	}

	var notifications []notification
	if err := json.Unmarshal(body, &notifications); err != nil {
		return nil, err
	}

	for _, item := range notifications {
		if item.Name == name {
			return &item, nil
		}
	}

	return nil, nil
}

func configureApp(app appConfig, host string, port int, jellyfinKey string) error {
	desired, err := jellyfinSchema(app)
	if err != nil {
		return err
	}
	desired.Fields = applyDesiredFields(desired.Fields, host, port, jellyfinKey)

	existing, err := existingNotification(app, desired.Name)
	if err != nil {
		return err
	}

	if existing == nil {
		if _, err := request("POST", normalizeBaseURL(app.BaseURL)+"/api/v3/notification", app.APIKey, desired); err != nil {
			return err
		}
		fmt.Printf("%s: created %q notification\n", app.Name, desired.Name)
		return nil
	}

	desired.ID = existing.ID
	if _, err := request("PUT", fmt.Sprintf("%s/api/v3/notification/%d", normalizeBaseURL(app.BaseURL), existing.ID), app.APIKey, desired); err != nil {
		return err
	}
	fmt.Printf("%s: updated %q notification\n", app.Name, desired.Name)
	return nil
}

func configureAppWithRetry(app appConfig, host string, port int, jellyfinKey string) error {
	var lastErr error
	for attempt := 1; attempt <= 30; attempt++ {
		if err := configureApp(app, host, port, jellyfinKey); err != nil {
			lastErr = err
			fmt.Fprintf(os.Stderr, "%s: waiting for API readiness (%d/30): %v\n", app.Name, attempt, err)
			time.Sleep(2 * time.Second)
			continue
		}
		return nil
	}
	return lastErr
}

func run() error {
	sonarrKeyFile, err := requiredEnv("HOME_OPS_SONARR_API_KEY_FILE")
	if err != nil {
		return err
	}
	radarrKeyFile, err := requiredEnv("HOME_OPS_RADARR_API_KEY_FILE")
	if err != nil {
		return err
	}
	jellyfinKeyFile, err := requiredEnv("HOME_OPS_JELLYFIN_API_KEY_FILE")
	if err != nil {
		return err
	}
	jellyfinHost, err := requiredEnv("HOME_OPS_JELLYFIN_HOST")
	if err != nil {
		return err
	}
	jellyfinPortText, err := requiredEnv("HOME_OPS_JELLYFIN_PORT")
	if err != nil {
		return err
	}
	jellyfinPort, err := strconv.Atoi(jellyfinPortText)
	if err != nil {
		return fmt.Errorf("invalid HOME_OPS_JELLYFIN_PORT: %w", err)
	}

	sonarrKey, err := readSecret(sonarrKeyFile)
	if err != nil {
		return err
	}
	radarrKey, err := readSecret(radarrKeyFile)
	if err != nil {
		return err
	}
	jellyfinKey, err := readSecret(jellyfinKeyFile)
	if err != nil {
		return err
	}

	apps := []appConfig{
		{Name: "Sonarr", BaseURL: "http://127.0.0.1:8989", APIKey: sonarrKey},
		{Name: "Radarr", BaseURL: "http://127.0.0.1:7878", APIKey: radarrKey},
	}

	for _, app := range apps {
		if err := configureAppWithRetry(app, jellyfinHost, jellyfinPort, jellyfinKey); err != nil {
			return err
		}
	}

	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

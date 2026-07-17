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

type field struct {
	Name  string      `json:"name"`
	Value interface{} `json:"value,omitempty"`
}

type downloadClient struct {
	ID                 int     `json:"id,omitempty"`
	Enable             bool    `json:"enable"`
	Name               string  `json:"name"`
	Protocol           string  `json:"protocol"`
	Priority           int     `json:"priority"`
	Implementation     string  `json:"implementation"`
	ImplementationName string  `json:"implementationName"`
	ConfigContract     string  `json:"configContract"`
	Fields             []field `json:"fields"`
}

type appConfig struct {
	Name          string
	BaseURL       string
	APIKey        string
	Category      string
	CategoryField string
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

func setField(fields []field, name string, value interface{}) []field {
	for index := range fields {
		if fields[index].Name == name {
			fields[index].Value = value
			return fields
		}
	}
	return fields
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
	if hasField(fields, name) {
		return setField(fields, name, value)
	}
	return fields
}

// clientSpec describes one download client to upsert into an arr app.
type clientSpec struct {
	Implementation  string
	Name            string
	DefaultProtocol string
	Fields          map[string]interface{}
}

func clientSchema(app appConfig, spec clientSpec) (downloadClient, error) {
	body, err := request("GET", normalizeBaseURL(app.BaseURL)+"/api/v3/downloadclient/schema", app.APIKey, nil)
	if err != nil {
		return downloadClient{}, err
	}

	var schemas []downloadClient
	if err := json.Unmarshal(body, &schemas); err != nil {
		return downloadClient{}, err
	}

	for _, schema := range schemas {
		if strings.EqualFold(schema.Implementation, spec.Implementation) || strings.EqualFold(schema.ImplementationName, spec.Implementation) {
			schema.ID = 0
			schema.Enable = true
			schema.Name = spec.Name
			if schema.Protocol == "" {
				schema.Protocol = spec.DefaultProtocol
			}
			if schema.Priority == 0 {
				schema.Priority = 1
			}
			return schema, nil
		}
	}

	return downloadClient{}, fmt.Errorf("%s: %s download-client schema not found", app.Name, spec.Name)
}

func existingClient(app appConfig, name string) (*downloadClient, error) {
	body, err := request("GET", normalizeBaseURL(app.BaseURL)+"/api/v3/downloadclient", app.APIKey, nil)
	if err != nil {
		return nil, err
	}

	var clients []downloadClient
	if err := json.Unmarshal(body, &clients); err != nil {
		return nil, err
	}

	for _, client := range clients {
		if client.Name == name {
			return &client, nil
		}
	}

	return nil, nil
}

func configureApp(app appConfig, spec clientSpec) error {
	client, err := clientSchema(app, spec)
	if err != nil {
		return err
	}

	for name, value := range spec.Fields {
		client.Fields = setFieldIfPresent(client.Fields, name, value)
	}
	client.Fields = setFieldIfPresent(client.Fields, app.CategoryField, app.Category)

	existing, err := existingClient(app, client.Name)
	if err != nil {
		return err
	}

	if existing == nil {
		_, err = request("POST", normalizeBaseURL(app.BaseURL)+"/api/v3/downloadclient", app.APIKey, client)
		if err == nil {
			fmt.Printf("%s: created %s download client\n", app.Name, spec.Name)
		}
		return err
	}

	client.ID = existing.ID
	_, err = request("PUT", fmt.Sprintf("%s/api/v3/downloadclient/%d", normalizeBaseURL(app.BaseURL), existing.ID), app.APIKey, client)
	if err == nil {
		fmt.Printf("%s: updated %s download client\n", app.Name, spec.Name)
	}
	return err
}

func configureAppWithRetry(app appConfig, specs []clientSpec) error {
	var lastErr error
	for attempt := 1; attempt <= 30; attempt++ {
		lastErr = nil
		for _, spec := range specs {
			if err := configureApp(app, spec); err != nil {
				lastErr = err
				break
			}
		}
		if lastErr == nil {
			return nil
		}
		fmt.Fprintf(os.Stderr, "%s: waiting for API readiness (%d/30): %v\n", app.Name, attempt, lastErr)
		time.Sleep(2 * time.Second)
	}

	return lastErr
}

func run() error {
	qbitUserFile, err := requiredEnv("HOME_OPS_QBIT_USERNAME_FILE")
	if err != nil {
		return err
	}
	qbitPasswordFile, err := requiredEnv("HOME_OPS_QBIT_PASSWORD_FILE")
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
	qbitHost, err := requiredEnv("HOME_OPS_QBIT_HOST")
	if err != nil {
		return err
	}
	qbitPortText, err := requiredEnv("HOME_OPS_QBIT_PORT")
	if err != nil {
		return err
	}
	qbitPort, err := strconv.Atoi(qbitPortText)
	if err != nil {
		return fmt.Errorf("invalid HOME_OPS_QBIT_PORT: %w", err)
	}

	qbitUser, err := readSecret(qbitUserFile)
	if err != nil {
		return err
	}
	qbitPassword, err := readSecret(qbitPasswordFile)
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

	specs := []clientSpec{
		{
			Implementation:  "qbittorrent",
			Name:            "qBittorrent",
			DefaultProtocol: "torrent",
			Fields: map[string]interface{}{
				"host":     qbitHost,
				"port":     qbitPort,
				"useSsl":   false,
				"urlBase":  "",
				"username": qbitUser,
				"password": qbitPassword,
			},
		},
	}

	// SABnzbd is optional: configured only when the env trio is present.
	if sabKeyFile := strings.TrimSpace(os.Getenv("HOME_OPS_SAB_API_KEY_FILE")); sabKeyFile != "" {
		sabHost, err := requiredEnv("HOME_OPS_SAB_HOST")
		if err != nil {
			return err
		}
		sabPortText, err := requiredEnv("HOME_OPS_SAB_PORT")
		if err != nil {
			return err
		}
		sabPort, err := strconv.Atoi(sabPortText)
		if err != nil {
			return fmt.Errorf("invalid HOME_OPS_SAB_PORT: %w", err)
		}
		sabKey, err := readSecret(sabKeyFile)
		if err != nil {
			return err
		}
		specs = append(specs, clientSpec{
			Implementation:  "sabnzbd",
			Name:            "SABnzbd",
			DefaultProtocol: "usenet",
			Fields: map[string]interface{}{
				"host":    sabHost,
				"port":    sabPort,
				"useSsl":  false,
				"urlBase": "",
				"apiKey":  sabKey,
			},
		})
	}

	apps := []appConfig{
		{
			Name:          "Sonarr",
			BaseURL:       "http://127.0.0.1:8989",
			APIKey:        sonarrKey,
			Category:      "tv",
			CategoryField: "tvCategory",
		},
		{
			Name:          "Radarr",
			BaseURL:       "http://127.0.0.1:7878",
			APIKey:        radarrKey,
			Category:      "movies",
			CategoryField: "movieCategory",
		},
	}

	for _, app := range apps {
		if err := configureAppWithRetry(app, specs); err != nil {
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

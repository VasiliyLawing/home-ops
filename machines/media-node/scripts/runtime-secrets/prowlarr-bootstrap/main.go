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

type providerResource struct {
	ID                 int     `json:"id,omitempty"`
	Name               string  `json:"name"`
	Implementation     string  `json:"implementation"`
	ImplementationName string  `json:"implementationName"`
	ConfigContract     string  `json:"configContract"`
	DefinitionName     string  `json:"definitionName,omitempty"`
	Enable             bool    `json:"enable"`
	SyncLevel          string  `json:"syncLevel,omitempty"`
	Redirect           bool    `json:"redirect,omitempty"`
	AppProfileID       int     `json:"appProfileId,omitempty"`
	Priority           int     `json:"priority,omitempty"`
	Tags               []int   `json:"tags,omitempty"`
	Fields             []field `json:"fields"`
}

type tagResource struct {
	ID    int    `json:"id,omitempty"`
	Label string `json:"label"`
}

type desiredApplication struct {
	Name           string `json:"name"`
	Implementation string `json:"implementation"`
	BaseURL        string `json:"baseUrl"`
	APIKeyFileEnv  string `json:"apiKeyFileEnv"`
	SyncLevel      string `json:"syncLevel"`
}

type desiredIndexer struct {
	Name         string                 `json:"name"`
	Match        string                 `json:"match"`
	Required     bool                   `json:"required"`
	Enable       bool                   `json:"enable"`
	Redirect     bool                   `json:"redirect"`
	Priority     int                    `json:"priority"`
	AppProfileID int                    `json:"appProfileId"`
	Tags         []string               `json:"tags"`
	Fields       map[string]interface{} `json:"fields"`
	// APIKeyFileEnv names an env var holding a secret-file path; its content
	// is set as the indexer's apiKey field (keeps keys out of bootstrap.json).
	APIKeyFileEnv string `json:"apiKeyFileEnv"`
}

type desiredIndexerProxy struct {
	Name           string                 `json:"name"`
	Implementation string                 `json:"implementation"`
	Required       bool                   `json:"required"`
	Tags           []string               `json:"tags"`
	Fields         map[string]interface{} `json:"fields"`
}

type bootstrapConfig struct {
	BaseURL        string                `json:"baseUrl"`
	ProwlarrURL    string                `json:"prowlarrUrl"`
	Applications   []desiredApplication  `json:"applications"`
	IndexerProxies []desiredIndexerProxy `json:"indexerProxies"`
	Indexers       []desiredIndexer      `json:"indexers"`
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

func getProviders(baseURL string, apiKey string, endpoint string) ([]providerResource, error) {
	body, err := request("GET", normalizeBaseURL(baseURL)+"/api/v1/"+endpoint, apiKey, nil)
	if err != nil {
		return nil, err
	}

	var providers []providerResource
	if err := json.Unmarshal(body, &providers); err != nil {
		return nil, err
	}

	return providers, nil
}

func getSchemas(baseURL string, apiKey string, endpoint string) ([]providerResource, error) {
	body, err := request("GET", normalizeBaseURL(baseURL)+"/api/v1/"+endpoint+"/schema", apiKey, nil)
	if err != nil {
		return nil, err
	}

	var schemas []providerResource
	if err := json.Unmarshal(body, &schemas); err != nil {
		return nil, err
	}

	return schemas, nil
}

func equalName(left string, right string) bool {
	return strings.EqualFold(strings.TrimSpace(left), strings.TrimSpace(right))
}

func schemaMatches(schema providerResource, match string) bool {
	return equalName(schema.Name, match) ||
		equalName(schema.Implementation, match) ||
		equalName(schema.ImplementationName, match) ||
		equalName(schema.DefinitionName, match)
}

func findSchema(schemas []providerResource, match string) (*providerResource, error) {
	for _, schema := range schemas {
		if schemaMatches(schema, match) {
			schema.Fields = append([]field(nil), schema.Fields...)
			return &schema, nil
		}
	}

	available := make([]string, 0, len(schemas))
	for _, schema := range schemas {
		name := schema.Name
		if schema.DefinitionName != "" {
			name = name + "/" + schema.DefinitionName
		}
		available = append(available, name)
	}

	return nil, fmt.Errorf("schema %q not found; available schemas include: %s", match, strings.Join(available, ", "))
}

func findExisting(providers []providerResource, name string) *providerResource {
	for _, provider := range providers {
		if equalName(provider.Name, name) {
			return &provider
		}
	}
	return nil
}

func setField(fields []field, name string, value interface{}) []field {
	for index := range fields {
		if equalName(fields[index].Name, name) {
			fields[index].Value = normalizeJSONValue(value)
			return fields
		}
	}
	return fields
}

func normalizeJSONValue(value interface{}) interface{} {
	number, ok := value.(float64)
	if !ok {
		return value
	}
	if number == float64(int(number)) {
		return int(number)
	}
	return number
}

func createOrUpdate(baseURL string, apiKey string, endpoint string, desired providerResource) error {
	existingProviders, err := getProviders(baseURL, apiKey, endpoint)
	if err != nil {
		return err
	}

	existing := findExisting(existingProviders, desired.Name)
	if existing == nil {
		_, err = request("POST", normalizeBaseURL(baseURL)+"/api/v1/"+endpoint, apiKey, desired)
		if err == nil {
			fmt.Printf("%s: created %s\n", endpoint, desired.Name)
		}
		return err
	}

	desired.ID = existing.ID
	_, err = request("PUT", normalizeBaseURL(baseURL)+"/api/v1/"+endpoint+"/"+strconv.Itoa(existing.ID), apiKey, desired)
	if err == nil {
		fmt.Printf("%s: updated %s\n", endpoint, desired.Name)
	}
	return err
}

func ensureTags(baseURL string, apiKey string, labels []string) ([]int, error) {
	if len(labels) == 0 {
		return nil, nil
	}

	body, err := request("GET", normalizeBaseURL(baseURL)+"/api/v1/tag", apiKey, nil)
	if err != nil {
		return nil, err
	}

	var existing []tagResource
	if err := json.Unmarshal(body, &existing); err != nil {
		return nil, err
	}

	ids := make([]int, 0, len(labels))
	for _, label := range labels {
		label = strings.TrimSpace(label)
		if label == "" {
			continue
		}

		var id int
		for _, tag := range existing {
			if equalName(tag.Label, label) {
				id = tag.ID
				break
			}
		}

		if id == 0 {
			payload := tagResource{Label: label}
			response, err := request("POST", normalizeBaseURL(baseURL)+"/api/v1/tag", apiKey, payload)
			if err != nil {
				return nil, err
			}
			var created tagResource
			if err := json.Unmarshal(response, &created); err != nil {
				return nil, err
			}
			id = created.ID
			existing = append(existing, created)
			fmt.Printf("tag: created %s\n", label)
		}

		ids = append(ids, id)
	}

	return ids, nil
}

func configureApplication(cfg bootstrapConfig, apiKey string, schemas []providerResource, app desiredApplication) error {
	schema, err := findSchema(schemas, app.Implementation)
	if err != nil {
		return err
	}

	appAPIKeyFile, err := requiredEnv(app.APIKeyFileEnv)
	if err != nil {
		return err
	}
	appAPIKey, err := readSecret(appAPIKeyFile)
	if err != nil {
		return err
	}

	desired := *schema
	desired.ID = 0
	desired.Name = app.Name
	desired.Enable = true
	desired.SyncLevel = app.SyncLevel
	if desired.SyncLevel == "" {
		desired.SyncLevel = "addOnly"
	}
	desired.Fields = setField(desired.Fields, "prowlarrUrl", cfg.ProwlarrURL)
	desired.Fields = setField(desired.Fields, "baseUrl", app.BaseURL)
	desired.Fields = setField(desired.Fields, "apiKey", appAPIKey)

	return createOrUpdate(cfg.BaseURL, apiKey, "applications", desired)
}

func configureIndexer(cfg bootstrapConfig, apiKey string, schemas []providerResource, indexer desiredIndexer) error {
	match := indexer.Match
	if match == "" {
		match = indexer.Name
	}
	schema, err := findSchema(schemas, match)
	if err != nil {
		return err
	}

	desired := *schema
	desired.ID = 0
	desired.Name = indexer.Name
	desired.Enable = indexer.Enable
	desired.Redirect = indexer.Redirect
	desired.Priority = indexer.Priority
	if desired.Priority == 0 {
		desired.Priority = 25
	}
	desired.AppProfileID = indexer.AppProfileID
	if desired.AppProfileID == 0 {
		desired.AppProfileID = 1
	}
	tags, err := ensureTags(cfg.BaseURL, apiKey, indexer.Tags)
	if err != nil {
		return err
	}
	desired.Tags = tags
	for name, value := range indexer.Fields {
		desired.Fields = setField(desired.Fields, name, value)
	}
	if indexer.APIKeyFileEnv != "" {
		keyFile, err := requiredEnv(indexer.APIKeyFileEnv)
		if err != nil {
			return err
		}
		key, err := readSecret(keyFile)
		if err != nil {
			return err
		}
		desired.Fields = setField(desired.Fields, "apiKey", key)
	}

	return createOrUpdate(cfg.BaseURL, apiKey, "indexer", desired)
}

func configureIndexerProxy(cfg bootstrapConfig, apiKey string, schemas []providerResource, proxy desiredIndexerProxy) error {
	match := proxy.Implementation
	if match == "" {
		match = proxy.Name
	}
	schema, err := findSchema(schemas, match)
	if err != nil {
		return err
	}

	desired := *schema
	desired.ID = 0
	desired.Name = proxy.Name
	desired.Enable = true
	tags, err := ensureTags(cfg.BaseURL, apiKey, proxy.Tags)
	if err != nil {
		return err
	}
	desired.Tags = tags
	for name, value := range proxy.Fields {
		desired.Fields = setField(desired.Fields, name, value)
	}

	return createOrUpdate(cfg.BaseURL, apiKey, "indexerProxy", desired)
}

func configure(cfg bootstrapConfig, apiKey string) error {
	appSchemas, err := getSchemas(cfg.BaseURL, apiKey, "applications")
	if err != nil {
		return err
	}
	indexerProxySchemas, err := getSchemas(cfg.BaseURL, apiKey, "indexerProxy")
	if err != nil {
		return err
	}
	indexerSchemas, err := getSchemas(cfg.BaseURL, apiKey, "indexer")
	if err != nil {
		return err
	}

	for _, proxy := range cfg.IndexerProxies {
		if err := configureIndexerProxy(cfg, apiKey, indexerProxySchemas, proxy); err != nil {
			if proxy.Required {
				return err
			}
			fmt.Fprintf(os.Stderr, "indexerProxy: skipped %s: %v\n", proxy.Name, err)
		}
	}

	for _, app := range cfg.Applications {
		if err := configureApplication(cfg, apiKey, appSchemas, app); err != nil {
			return err
		}
	}
	for _, indexer := range cfg.Indexers {
		if err := configureIndexer(cfg, apiKey, indexerSchemas, indexer); err != nil {
			if indexer.Required {
				return err
			}
			fmt.Fprintf(os.Stderr, "indexer: skipped %s: %v\n", indexer.Name, err)
		}
	}

	return nil
}

func configureWithRetry(cfg bootstrapConfig, apiKey string) error {
	var lastErr error
	for attempt := 1; attempt <= 30; attempt++ {
		err := configure(cfg, apiKey)
		if err == nil {
			return nil
		}
		lastErr = err
		fmt.Fprintf(os.Stderr, "waiting for Prowlarr API readiness (%d/30): %v\n", attempt, err)
		time.Sleep(2 * time.Second)
	}

	return lastErr
}

func run() error {
	configFile, err := requiredEnv("HOME_OPS_PROWLARR_BOOTSTRAP_CONFIG")
	if err != nil {
		return err
	}
	apiKeyFile, err := requiredEnv("HOME_OPS_PROWLARR_API_KEY_FILE")
	if err != nil {
		return err
	}

	content, err := os.ReadFile(configFile)
	if err != nil {
		return err
	}
	var cfg bootstrapConfig
	if err := json.Unmarshal(content, &cfg); err != nil {
		return err
	}
	if cfg.BaseURL == "" {
		cfg.BaseURL = "http://127.0.0.1:9696"
	}
	if cfg.ProwlarrURL == "" {
		cfg.ProwlarrURL = cfg.BaseURL
	}

	apiKey, err := readSecret(apiKeyFile)
	if err != nil {
		return err
	}

	return configureWithRetry(cfg, apiKey)
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

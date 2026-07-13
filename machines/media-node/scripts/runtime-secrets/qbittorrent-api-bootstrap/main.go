package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

type category struct {
	Name     string `json:"name"`
	SavePath string `json:"savePath"`
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

func login(baseURL string, username string, password string) (string, error) {
	form := url.Values{}
	form.Set("username", username)
	form.Set("password", password)

	req, err := http.NewRequest("POST", baseURL+"/api/v2/auth/login", strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Referer", baseURL+"/")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("login returned %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	for _, cookie := range resp.Cookies() {
		if cookie.Name == "SID" && cookie.Value != "" {
			return "SID=" + cookie.Value, nil
		}
	}
	if strings.TrimSpace(string(body)) == "" {
		return "", nil
	}
	return "", fmt.Errorf("login did not return SID cookie: %s", strings.TrimSpace(string(body)))
}

func apiRequest(baseURL string, cookie string, endpoint string, form url.Values) ([]byte, error) {
	req, err := http.NewRequest("POST", baseURL+endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if cookie != "" {
		req.Header.Set("Cookie", cookie)
	}
	req.Header.Set("Referer", baseURL+"/")

	client := &http.Client{Timeout: 30 * time.Second}
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
		return nil, fmt.Errorf("POST %s returned %d: %s", endpoint, resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return body, nil
}

func apiGet(baseURL string, cookie string, endpoint string) ([]byte, error) {
	req, err := http.NewRequest("GET", baseURL+endpoint, nil)
	if err != nil {
		return nil, err
	}
	if cookie != "" {
		req.Header.Set("Cookie", cookie)
	}
	req.Header.Set("Referer", baseURL+"/")
	req.Header.Set("Accept", "application/json")

	client := &http.Client{Timeout: 30 * time.Second}
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
		return nil, fmt.Errorf("GET %s returned %d: %s", endpoint, resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return body, nil
}

func setPreferences(baseURL string, cookie string, savePath string, tempPath string, torrentingPort string) error {
	preferences := map[string]any{
		"save_path":                     savePath,
		"temp_path_enabled":             true,
		"temp_path":                     tempPath,
		"auto_tmm_enabled":              true,
		"torrent_changed_tmm_enabled":   true,
		"save_path_changed_tmm_enabled": true,
		"category_changed_tmm_enabled":  true,
		"random_port":                   false,
		"upnp":                          false,
	}
	if torrentingPort != "" {
		port, err := strconv.Atoi(torrentingPort)
		if err != nil {
			return fmt.Errorf("invalid torrenting port %q: %w", torrentingPort, err)
		}
		preferences["listen_port"] = port
	}

	content, err := json.Marshal(preferences)
	if err != nil {
		return err
	}

	form := url.Values{}
	form.Set("json", string(content))
	_, err = apiRequest(baseURL, cookie, "/api/v2/app/setPreferences", form)
	return err
}

func categoryPath(savePath string, categoryName string) string {
	return strings.TrimRight(savePath, "/") + "/" + categoryName
}

func getCategories(baseURL string, cookie string) (map[string]category, error) {
	body, err := apiGet(baseURL, cookie, "/api/v2/torrents/categories")
	if err != nil {
		return nil, err
	}
	categories := map[string]category{}
	if strings.TrimSpace(string(body)) == "" {
		return categories, nil
	}
	if err := json.Unmarshal(body, &categories); err != nil {
		return nil, err
	}
	return categories, nil
}

func ensureCategory(baseURL string, cookie string, name string, savePath string) error {
	categories, err := getCategories(baseURL, cookie)
	if err != nil {
		return err
	}

	form := url.Values{}
	form.Set("category", name)
	form.Set("savePath", savePath)

	if _, ok := categories[name]; ok {
		_, err = apiRequest(baseURL, cookie, "/api/v2/torrents/editCategory", form)
		if err == nil {
			fmt.Printf("qBittorrent: updated category %s -> %s\n", name, savePath)
		}
		return err
	}

	_, err = apiRequest(baseURL, cookie, "/api/v2/torrents/createCategory", form)
	if err == nil {
		fmt.Printf("qBittorrent: created category %s -> %s\n", name, savePath)
	}
	return err
}

func configureWithRetry(baseURL string, username string, password string, savePath string, tempPath string, torrentingPort string) error {
	var lastErr error
	for attempt := 1; attempt <= 30; attempt++ {
		cookie, err := login(baseURL, username, password)
		if err == nil {
			err = setPreferences(baseURL, cookie, savePath, tempPath, torrentingPort)
		}
		if err == nil {
			categories := map[string]string{
				"movies":     categoryPath(savePath, "movies"),
				"tv":         categoryPath(savePath, "tv"),
				"music":      categoryPath(savePath, "music"),
				"books":      categoryPath(savePath, "books"),
				"audiobooks": categoryPath(savePath, "audiobooks"),
			}
			var categoryErr error
			for name, path := range categories {
				if err := ensureCategory(baseURL, cookie, name, path); err != nil {
					categoryErr = err
					break
				}
			}
			if categoryErr != nil {
				lastErr = categoryErr
				fmt.Fprintf(os.Stderr, "qBittorrent: waiting for category sync (%d/30): %v\n", attempt, categoryErr)
				time.Sleep(2 * time.Second)
				continue
			}
			fmt.Println("qBittorrent: configured live Web API paths and categories")
			return nil
		}
		lastErr = err
		fmt.Fprintf(os.Stderr, "qBittorrent: waiting for Web API readiness (%d/30): %v\n", attempt, err)
		time.Sleep(2 * time.Second)
	}
	return lastErr
}

func run() error {
	baseURL := normalizeBaseURL(strings.TrimSpace(os.Getenv("HOME_OPS_QBIT_BASE_URL")))
	if baseURL == "" {
		baseURL = "http://127.0.0.1:8081"
	}

	usernameFile, err := requiredEnv("HOME_OPS_QBIT_USERNAME_FILE")
	if err != nil {
		return err
	}
	passwordFile, err := requiredEnv("HOME_OPS_QBIT_PASSWORD_FILE")
	if err != nil {
		return err
	}
	savePath, err := requiredEnv("HOME_OPS_QBIT_SAVE_PATH")
	if err != nil {
		return err
	}
	tempPath, err := requiredEnv("HOME_OPS_QBIT_TEMP_PATH")
	if err != nil {
		return err
	}

	username, err := readSecret(usernameFile)
	if err != nil {
		return err
	}
	password, err := readSecret(passwordFile)
	if err != nil {
		return err
	}

	return configureWithRetry(baseURL, username, password, savePath, tempPath, strings.TrimSpace(os.Getenv("HOME_OPS_QBIT_TORRENTING_PORT")))
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

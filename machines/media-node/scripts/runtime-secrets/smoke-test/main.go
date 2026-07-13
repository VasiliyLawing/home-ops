package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type smokeContext struct {
	dataRoot          string
	secretDir         string
	seerrSettingsFile string
}

type check struct {
	name string
	run  func(smokeContext) error
}

type arrDownloadClient struct {
	Name           string `json:"name"`
	Implementation string `json:"implementation"`
	Enable         bool   `json:"enable"`
}

type prowlarrApplication struct {
	Name string `json:"name"`
}

type prowlarrProxy struct {
	Name string `json:"name"`
}

type jellyfinMediaFoldersResponse struct {
	Items []jellyfinMediaFolder `json:"Items"`
}

type jellyfinMediaFolder struct {
	Name           string `json:"Name"`
	Type           string `json:"Type"`
	CollectionType string `json:"CollectionType"`
}

type qbittorrentPreferences struct {
	SavePath        string `json:"save_path"`
	TempPathEnabled bool   `json:"temp_path_enabled"`
	TempPath        string `json:"temp_path"`
	RandomPort      bool   `json:"random_port"`
	UPnP            bool   `json:"upnp"`
}

func envDefault(name string, fallback string) string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	return value
}

func commandOutput(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	output, err := cmd.Output()
	if err != nil {
		details := strings.TrimSpace(stderr.String())
		if details == "" {
			details = strings.TrimSpace(string(output))
		}
		if details == "" {
			details = err.Error()
		}
		return string(output), fmt.Errorf("%s %s failed: %s", name, strings.Join(args, " "), details)
	}
	return string(output), nil
}

func readSecret(secretDir string, name string) (string, error) {
	content, err := os.ReadFile(filepath.Join(secretDir, name))
	if err != nil {
		return "", err
	}
	value := strings.TrimSpace(string(content))
	if value == "" {
		return "", fmt.Errorf("%s is empty", name)
	}
	return value, nil
}

func request(method string, url string, apiKey string, body io.Reader) ([]byte, error) {
	req, err := http.NewRequest(method, url, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	if apiKey != "" {
		req.Header.Set("X-Api-Key", apiKey)
		req.Header.Set("X-Emby-Token", apiKey)
	}

	client := &http.Client{Timeout: 10 * time.Second}
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

func getJSON[T any](url string, apiKey string) (T, error) {
	var value T
	body, err := request("GET", url, apiKey, nil)
	if err != nil {
		return value, err
	}
	return value, json.Unmarshal(body, &value)
}

func retry(fn func() error) error {
	var last error
	for attempt := 1; attempt <= 6; attempt++ {
		if err := fn(); err != nil {
			last = err
			time.Sleep(2 * time.Second)
			continue
		}
		return nil
	}
	return last
}

func checkNoFailedUnits(smokeContext) error {
	output, err := commandOutput("systemctl", "--failed", "--no-legend", "--plain")
	if err != nil {
		return err
	}
	failedLines := []string{}
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.Contains(line, "home-ops-smoke-test.service") {
			continue
		}
		failedLines = append(failedLines, line)
	}
	if len(failedLines) > 0 {
		return fmt.Errorf("failed units present:\n%s", strings.Join(failedLines, "\n"))
	}
	return nil
}

func unitExists(unit string) bool {
	output, err := commandOutput("systemctl", "show", "-p", "LoadState", "--value", unit)
	return err == nil && strings.TrimSpace(output) == "loaded"
}

func checkRequiredUnits(units ...string) func(smokeContext) error {
	return func(smokeContext) error {
		for _, unit := range units {
			if _, err := commandOutput("systemctl", "is-active", "--quiet", unit); err != nil {
				return fmt.Errorf("%s is not active", unit)
			}
		}
		return nil
	}
}

func checkOptionalUnits(units ...string) func(smokeContext) error {
	return func(smokeContext) error {
		for _, unit := range units {
			if !unitExists(unit) {
				continue
			}
			if _, err := commandOutput("systemctl", "is-active", "--quiet", unit); err != nil {
				return fmt.Errorf("%s exists but is not active", unit)
			}
		}
		return nil
	}
}

func checkNasPaths(ctx smokeContext) error {
	requiredPaths := []string{
		filepath.Join(ctx.dataRoot, "torrents", "complete"),
		filepath.Join(ctx.dataRoot, "torrents", "incomplete"),
		filepath.Join(ctx.dataRoot, "media", "movies"),
		filepath.Join(ctx.dataRoot, "media", "tv"),
	}
	for _, path := range requiredPaths {
		info, err := os.Stat(path)
		if err != nil {
			return err
		}
		if !info.IsDir() {
			return fmt.Errorf("%s exists but is not a directory", path)
		}
	}
	return nil
}

func checkQbittorrentVPNNamespace(smokeContext) error {
	output, err := commandOutput("docker", "inspect", "qbittorrent", "--format", "{{.HostConfig.NetworkMode}}")
	if err != nil {
		return err
	}
	networkMode := strings.TrimSpace(output)
	if !strings.HasPrefix(networkMode, "container:") {
		return fmt.Errorf("qbittorrent network mode is %q, want container:<gluetun-id>", networkMode)
	}
	return nil
}

func qbittorrentCookie(ctx smokeContext) (string, error) {
	username, err := readSecret(ctx.secretDir, "qbittorrent-webui-username")
	if err != nil {
		return "", err
	}
	password, err := readSecret(ctx.secretDir, "qbittorrent-webui-password")
	if err != nil {
		return "", err
	}

	form := url.Values{}
	form.Set("username", username)
	form.Set("password", password)

	req, err := http.NewRequest(
		"POST",
		"http://localhost:8081/api/v2/auth/login",
		strings.NewReader(form.Encode()),
	)
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Origin", "http://localhost:8081")
	req.Header.Set("Referer", "http://localhost:8081/")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	responseBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("qBittorrent login returned %d: %s", resp.StatusCode, strings.TrimSpace(string(responseBody)))
	}
	for _, cookie := range resp.Cookies() {
		if cookie.Name == "SID" && cookie.Value != "" {
			return "SID=" + cookie.Value, nil
		}
	}
	if strings.TrimSpace(string(responseBody)) == "" {
		return "", nil
	}
	return "", fmt.Errorf("qBittorrent login did not return a SID cookie: %s", strings.TrimSpace(string(responseBody)))
}

func checkQbittorrentAPI(ctx smokeContext) error {
	return retry(func() error {
		cookie, err := qbittorrentCookie(ctx)
		if err != nil {
			return err
		}

		req, err := http.NewRequest("GET", "http://localhost:8081/api/v2/app/version", nil)
		if err != nil {
			return err
		}
		req.Header.Set("Accept", "text/plain")
		if cookie != "" {
			req.Header.Set("Cookie", cookie)
		}
		req.Header.Set("Origin", "http://localhost:8081")
		req.Header.Set("Referer", "http://localhost:8081/")

		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			return err
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return err
		}
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return fmt.Errorf("GET qBittorrent app/version returned %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
		}
		if strings.TrimSpace(string(body)) == "" {
			return fmt.Errorf("qBittorrent returned an empty version")
		}

		prefsReq, err := http.NewRequest("GET", "http://localhost:8081/api/v2/app/preferences", nil)
		if err != nil {
			return err
		}
		prefsReq.Header.Set("Accept", "application/json")
		if cookie != "" {
			prefsReq.Header.Set("Cookie", cookie)
		}
		prefsReq.Header.Set("Origin", "http://localhost:8081")
		prefsReq.Header.Set("Referer", "http://localhost:8081/")

		prefsResp, err := client.Do(prefsReq)
		if err != nil {
			return err
		}
		defer prefsResp.Body.Close()

		prefsBody, err := io.ReadAll(prefsResp.Body)
		if err != nil {
			return err
		}
		if prefsResp.StatusCode < 200 || prefsResp.StatusCode >= 300 {
			return fmt.Errorf("GET qBittorrent app/preferences returned %d: %s", prefsResp.StatusCode, strings.TrimSpace(string(prefsBody)))
		}

		var prefs qbittorrentPreferences
		if err := json.Unmarshal(prefsBody, &prefs); err != nil {
			return err
		}
		expectedSavePath := envDefault("HOME_OPS_QBIT_SAVE_PATH", "/data/torrents/complete")
		expectedTempPath := envDefault("HOME_OPS_QBIT_TEMP_PATH", "/data/torrents/incomplete")
		if prefs.SavePath != expectedSavePath {
			return fmt.Errorf("qBittorrent save_path is %q, want %q", prefs.SavePath, expectedSavePath)
		}
		if !prefs.TempPathEnabled || prefs.TempPath != expectedTempPath {
			return fmt.Errorf("qBittorrent temp path is enabled=%v path=%q, want enabled=true path=%q", prefs.TempPathEnabled, prefs.TempPath, expectedTempPath)
		}
		if prefs.RandomPort {
			return fmt.Errorf("qBittorrent random port is enabled")
		}
		if prefs.UPnP {
			return fmt.Errorf("qBittorrent UPnP/NAT-PMP is enabled")
		}
		return nil
	})
}

func checkArrDownloadClient(kind string, url string, secretName string) func(smokeContext) error {
	return func(ctx smokeContext) error {
		apiKey, err := readSecret(ctx.secretDir, secretName)
		if err != nil {
			return err
		}
		return retry(func() error {
			if _, err := request("GET", url+"/api/v3/system/status", apiKey, nil); err != nil {
				return err
			}
			clients, err := getJSON[[]arrDownloadClient](url+"/api/v3/downloadclient", apiKey)
			if err != nil {
				return err
			}
			for _, client := range clients {
				if strings.EqualFold(client.Name, "qBittorrent") || strings.Contains(strings.ToLower(client.Implementation), "qbittorrent") {
					return nil
				}
			}
			return fmt.Errorf("%s has no qBittorrent download client", kind)
		})
	}
}

func checkProwlarr(ctx smokeContext) error {
	apiKey, err := readSecret(ctx.secretDir, "prowlarr-api-key")
	if err != nil {
		return err
	}
	return retry(func() error {
		if _, err := request("GET", "http://127.0.0.1:9696/api/v1/system/status", apiKey, nil); err != nil {
			return err
		}
		applications, err := getJSON[[]prowlarrApplication]("http://127.0.0.1:9696/api/v1/applications", apiKey)
		if err != nil {
			return err
		}
		seen := map[string]bool{}
		for _, app := range applications {
			seen[strings.ToLower(app.Name)] = true
		}
		if !seen["sonarr"] || !seen["radarr"] {
			return fmt.Errorf("Prowlarr applications are missing Sonarr/Radarr links")
		}

		proxies, err := getJSON[[]prowlarrProxy]("http://127.0.0.1:9696/api/v1/indexerProxy", apiKey)
		if err != nil {
			return err
		}
		for _, proxy := range proxies {
			if strings.Contains(strings.ToLower(proxy.Name), "flaresolverr") {
				return nil
			}
		}
		return fmt.Errorf("Prowlarr has no FlareSolverr indexer proxy")
	})
}

func checkJellyfin(ctx smokeContext) error {
	apiKey, err := readSecret(ctx.secretDir, "jellyfin-api-key")
	if err != nil {
		return err
	}
	return retry(func() error {
		if _, err := request("GET", "http://127.0.0.1:8096/System/Info", apiKey, nil); err != nil {
			return err
		}
		response, err := getJSON[jellyfinMediaFoldersResponse]("http://127.0.0.1:8096/Library/MediaFolders", apiKey)
		if err != nil {
			return err
		}
		seen := map[string]bool{}
		for _, folder := range response.Items {
			if folder.Type == "CollectionFolder" {
				seen[folder.CollectionType] = true
			}
		}
		if !seen["movies"] || !seen["tvshows"] {
			return fmt.Errorf("Jellyfin is missing Movies/TV libraries")
		}
		return nil
	})
}

func asMap(value interface{}) map[string]interface{} {
	if typed, ok := value.(map[string]interface{}); ok {
		return typed
	}
	return map[string]interface{}{}
}

func asSlice(value interface{}) []interface{} {
	if typed, ok := value.([]interface{}); ok {
		return typed
	}
	return nil
}

func checkSeerrSettings(ctx smokeContext) error {
	content, err := os.ReadFile(ctx.seerrSettingsFile)
	if err != nil {
		return err
	}
	settings := map[string]interface{}{}
	if err := json.Unmarshal(content, &settings); err != nil {
		return err
	}

	main := asMap(settings["main"])
	if mediaServerType, ok := main["mediaServerType"].(float64); !ok || int(mediaServerType) != 2 {
		return fmt.Errorf("Seerr main.mediaServerType is not Jellyfin")
	}

	jellyfin := asMap(settings["jellyfin"])
	apiKey, _ := jellyfin["apiKey"].(string)
	if strings.TrimSpace(apiKey) == "" {
		return fmt.Errorf("Seerr Jellyfin API key is empty")
	}
	hasEnabledLibrary := false
	for _, library := range asSlice(jellyfin["libraries"]) {
		if asMap(library)["enabled"] == true {
			hasEnabledLibrary = true
			break
		}
	}
	if !hasEnabledLibrary {
		return fmt.Errorf("Seerr has no enabled Jellyfin libraries")
	}

	if len(asSlice(settings["sonarr"])) == 0 {
		return fmt.Errorf("Seerr has no Sonarr service configured")
	}
	if len(asSlice(settings["radarr"])) == 0 {
		return fmt.Errorf("Seerr has no Radarr service configured")
	}
	return nil
}

func run() error {
	ctx := smokeContext{
		dataRoot:          envDefault("HOME_OPS_DATA_ROOT", "/mnt/nas/data"),
		secretDir:         envDefault("HOME_OPS_SECRET_DIRECTORY", "/var/lib/home-ops/secrets"),
		seerrSettingsFile: envDefault("HOME_OPS_SEERR_SETTINGS_FILE", "/var/lib/seerr/settings.json"),
	}

	checks := []check{
		{name: "no failed systemd units", run: checkNoFailedUnits},
		{name: "core media units active", run: checkRequiredUnits("jellyfin.service", "seerr.service", "sonarr.service", "radarr.service", "prowlarr.service", "bazarr.service", "sabnzbd.service", "docker-gluetun.service", "docker-qbittorrent.service", "docker-unpackerr.service")},
		{name: "optional media units active when installed", run: checkOptionalUnits("flaresolverr.service", "audiobookshelf.service", "lidarr.service", "navidrome.service", "docker-aurral.service", "docker-neutarr.service", "docker-shelfmark.service", "docker-calibre-web-automated.service")},
		{name: "NAS media paths exist", run: checkNasPaths},
		{name: "qBittorrent shares Gluetun network namespace", run: checkQbittorrentVPNNamespace},
		{name: "qBittorrent Web API reachable", run: checkQbittorrentAPI},
		{name: "Sonarr has qBittorrent download client", run: checkArrDownloadClient("Sonarr", "http://127.0.0.1:8989", "sonarr-api-key")},
		{name: "Radarr has qBittorrent download client", run: checkArrDownloadClient("Radarr", "http://127.0.0.1:7878", "radarr-api-key")},
		{name: "Prowlarr app links and FlareSolverr proxy", run: checkProwlarr},
		{name: "Jellyfin Movies/TV libraries", run: checkJellyfin},
		{name: "Seerr media settings configured", run: checkSeerrSettings},
	}

	failures := 0
	for _, check := range checks {
		if err := check.run(ctx); err != nil {
			failures++
			fmt.Printf("FAIL %s: %v\n", check.name, err)
			continue
		}
		fmt.Printf("PASS %s\n", check.name)
	}
	if failures > 0 {
		return fmt.Errorf("%d smoke check(s) failed", failures)
	}
	fmt.Println("PASS all smoke checks")
	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

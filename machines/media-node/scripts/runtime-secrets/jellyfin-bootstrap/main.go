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

func request(method string, endpoint string, apiKey string, body []byte) ([]byte, error) {
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequest(method, endpoint, reader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-Emby-Token", apiKey)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%s %s returned %d: %s", method, endpoint, resp.StatusCode, strings.TrimSpace(string(respBody)))
	}
	return respBody, nil
}

func getLibraries(baseURL string, apiKey string) ([]virtualFolder, error) {
	body, err := request("GET", strings.TrimRight(baseURL, "/")+"/Library/VirtualFolders", apiKey, nil)
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
	_, err := request("POST", endpoint, apiKey, nil)
	return err
}

// Desired-state VAAPI transcoding settings for the AMD 780M (VCN 4):
// hardware decode for every codec it supports, HEVC/AV1 hardware encode,
// HDR->SDR tone mapping (Jellyfin picks the Vulkan/libplacebo path on AMD
// without a ROCm OpenCL runtime), and throttling so concurrent remote
// streams don't transcode whole files ahead of playback.
func desiredEncodingSettings() map[string]any {
	return map[string]any{
		"HardwareAccelerationType":       "vaapi",
		"VaapiDevice":                    "/dev/dri/renderD128",
		"HardwareDecodingCodecs":         []string{"h264", "hevc", "mpeg2video", "vc1", "vp8", "vp9", "av1"},
		"EnableDecodingColorDepth10Hevc": true,
		"EnableDecodingColorDepth10Vp9":  true,
		"EnableHardwareEncoding":         true,
		"AllowHevcEncoding":              true,
		"AllowAv1Encoding":               true,
		"EnableTonemapping":              true,
		"EnableThrottling":               true,
		"EnableSegmentDeletion":          true,
	}
}

func configureEncoding(baseURL string, apiKey string) error {
	endpoint := strings.TrimRight(baseURL, "/") + "/System/Configuration/encoding"
	body, err := request("GET", endpoint, apiKey, nil)
	if err != nil {
		return err
	}
	config := map[string]any{}
	if len(body) > 0 {
		if err := json.Unmarshal(body, &config); err != nil {
			return err
		}
	}
	for key, value := range desiredEncodingSettings() {
		config[key] = value
	}
	payload, err := json.Marshal(config)
	if err != nil {
		return err
	}
	if _, err := request("POST", endpoint, apiKey, payload); err != nil {
		return err
	}
	fmt.Println("Jellyfin: applied VAAPI hardware transcoding settings")
	return nil
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
	if err := ensureWithRetry(baseURL, apiKey, libraries); err != nil {
		return err
	}
	return configureEncoding(baseURL, apiKey)
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

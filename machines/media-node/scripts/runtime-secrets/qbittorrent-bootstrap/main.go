package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha512"
	"encoding/base64"
	"fmt"
	"hash"
	"math"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
)

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

func pbkdf2SHA512(password string, salt []byte, iterations int, keyLength int) []byte {
	prf := func() hash.Hash {
		return hmac.New(sha512.New, []byte(password))
	}

	hashLength := prf().Size()
	blocks := int(math.Ceil(float64(keyLength) / float64(hashLength)))
	output := make([]byte, 0, blocks*hashLength)

	for block := 1; block <= blocks; block++ {
		mac := prf()
		mac.Write(salt)
		mac.Write([]byte{
			byte(block >> 24),
			byte(block >> 16),
			byte(block >> 8),
			byte(block),
		})

		u := mac.Sum(nil)
		t := append([]byte(nil), u...)

		for i := 1; i < iterations; i++ {
			mac = prf()
			mac.Write(u)
			u = mac.Sum(nil)

			for j := range t {
				t[j] ^= u[j]
			}
		}

		output = append(output, t...)
	}

	return output[:keyLength]
}

func qBittorrentPasswordHash(password string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}

	digest := pbkdf2SHA512(password, salt, 100000, 64)

	return base64.StdEncoding.EncodeToString(salt) + ":" + base64.StdEncoding.EncodeToString(digest), nil
}

func setINIValue(lines []string, section string, key string, value string) []string {
	sectionHeader := "[" + section + "]"
	sectionStart := -1
	sectionEnd := len(lines)

	for index, line := range lines {
		if strings.TrimSpace(line) == sectionHeader {
			sectionStart = index
			break
		}
	}

	if sectionStart == -1 {
		if len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) != "" {
			lines = append(lines, "")
		}

		return append(lines, sectionHeader, key+"="+value)
	}

	for index := sectionStart + 1; index < len(lines); index++ {
		line := strings.TrimSpace(lines[index])
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			sectionEnd = index
			break
		}
	}

	prefix := key + "="
	for index := sectionStart + 1; index < sectionEnd; index++ {
		if strings.HasPrefix(lines[index], prefix) {
			lines[index] = prefix + value
			return lines
		}
	}

	lines = append(lines, "")
	copy(lines[sectionEnd+1:], lines[sectionEnd:])
	lines[sectionEnd] = prefix + value

	return lines
}

func lookupOwner(ownerName string, groupName string) (int, int, error) {
	owner, err := user.Lookup(ownerName)
	if err != nil {
		return 0, 0, err
	}

	group, err := user.LookupGroup(groupName)
	if err != nil {
		return 0, 0, err
	}

	uid, err := strconv.Atoi(owner.Uid)
	if err != nil {
		return 0, 0, err
	}

	gid, err := strconv.Atoi(group.Gid)
	if err != nil {
		return 0, 0, err
	}

	return uid, gid, nil
}

func readConfigLines(path string) ([]string, error) {
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

func writeConfigFile(path string, lines []string) error {
	var mode os.FileMode = 0o640
	if info, err := os.Stat(path); err == nil {
		mode = info.Mode().Perm()
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o775); err != nil {
		return err
	}

	tmp := path + ".home-ops.tmp"
	content := []byte(strings.Join(lines, "\n") + "\n")
	if err := os.WriteFile(tmp, content, 0o640); err != nil {
		return err
	}
	if err := os.Chmod(tmp, mode); err != nil {
		return err
	}

	return os.Rename(tmp, path)
}

func run() error {
	configFile, err := requiredEnv("HOME_OPS_QBIT_CONFIG_FILE")
	if err != nil {
		return err
	}

	usernameFile, err := requiredEnv("HOME_OPS_QBIT_USERNAME_FILE")
	if err != nil {
		return err
	}

	passwordFile, err := requiredEnv("HOME_OPS_QBIT_PASSWORD_FILE")
	if err != nil {
		return err
	}

	owner, err := requiredEnv("HOME_OPS_QBIT_OWNER")
	if err != nil {
		return err
	}

	group, err := requiredEnv("HOME_OPS_QBIT_GROUP")
	if err != nil {
		return err
	}

	webUIPort, err := requiredEnv("HOME_OPS_QBIT_WEBUI_PORT")
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

	torrentingPort, err := requiredEnv("HOME_OPS_QBIT_TORRENTING_PORT")
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

	lines, err := readConfigLines(configFile)
	if err != nil {
		return err
	}

	passwordHash, err := qBittorrentPasswordHash(password)
	if err != nil {
		return err
	}

	values := []struct {
		key   string
		value string
	}{
		{`WebUI\Username`, username},
		{`WebUI\Password_PBKDF2`, `"@ByteArray(` + passwordHash + `)"`},
		{`WebUI\LocalHostAuth`, "true"},
		{`WebUI\Port`, webUIPort},
		{`Downloads\SavePath`, savePath},
		{`Downloads\TempPath`, tempPath},
		{`Downloads\TempPathEnabled`, "true"},
		{`Connection\PortRangeMin`, torrentingPort},
		{`Connection\UPnP`, "false"},
		{`Connection\RandomPort`, "false"},
	}

	for _, item := range values {
		lines = setINIValue(lines, "Preferences", item.key, item.value)
	}

	configDir := filepath.Dir(configFile)
	if err := writeConfigFile(configFile, lines); err != nil {
		return err
	}

	uid, gid, err := lookupOwner(owner, group)
	if err != nil {
		return err
	}

	if err := os.Chown(configDir, uid, gid); err != nil {
		return err
	}

	return os.Chown(configFile, uid, gid)
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

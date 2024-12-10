package utils

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
)

type Config struct {
	Team              string `json:"team"`
	WebhookURL        string `json:"webhook_url"`
	WebhookComplement string `json:"webhook_complement"`
	SlackUserID       string `json:"slack_user_id"`
	GroupApprovers    string `json:"group_approvers"`
	GroupMergers      string `json:"group_mergers"`
}

type SlackMessageBlock struct {
	Type string `json:"type"`
	Text *struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"text,omitempty"`
}

type SlackMessage struct {
	Blocks    []SlackMessageBlock `json:"blocks"`
	Username  string              `json:"username"`
	IconEmoji string              `json:"icon_emoji"`
}

type TemplateConfig struct {
	Username      string `json:"username"`
	IconEmoji     string `json:"icon_emoji"`
	MessageFormat string `json:"message_format"`
}

func loadConfig(filename string) (*Config, error) {
	file, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("error reading config file: %w", err)
	}

	var config Config
	err = json.Unmarshal(file, &config)
	if err != nil {
		return nil, fmt.Errorf("error parsing config file: %w", err)
	}

	return &config, nil
}

func sendSlackMessage(payload []byte, webhookURL string) error {
	resp, err := http.Post(webhookURL, "application/json", bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("error sending Slack message: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("Slack returned non-200 status code: %d", resp.StatusCode)
	}

	return nil
}

func loadTemplates(filename string) (map[string]TemplateConfig, error) {
	file, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("error reading templates file: %w", err)
	}

	var templates map[string]TemplateConfig
	err = json.Unmarshal(file, &templates)
	if err != nil {
		return nil, fmt.Errorf("error parsing templates file: %w", err)
	}

	return templates, nil
}

func BuildSlackMessage(prURL, prTitle, prNumber string, config *Config) ([]byte, error) {
	_, currentFilePath, _, _ := runtime.Caller(0)
	currentDir := filepath.Dir(currentFilePath)
	templatesPath := filepath.Join(currentDir, "../env/templates.json")

	templates, err := loadTemplates(templatesPath)
	if err != nil {
		return nil, fmt.Errorf("error loading templates: %w", err)
	}

	template, exists := templates[config.Team]
	if !exists {
		return nil, fmt.Errorf("no template found for team: %s", config.Team)
	}

	author := fmt.Sprintf("<@%s>", config.SlackUserID)
	groupApprovers := fmt.Sprintf("<!subteam^%s>", config.GroupApprovers)
	titleWithLink := fmt.Sprintf("<%s|%s> #%s", prURL, prTitle, prNumber)

	messageText := fmt.Sprintf(template.MessageFormat, author, config.Team, titleWithLink, groupApprovers)

	message := SlackMessage{
		Username:  template.Username,
		IconEmoji: template.IconEmoji,
		Blocks: []SlackMessageBlock{
			{
				Type: "section",
				Text: &struct {
					Type string `json:"type"`
					Text string `json:"text"`
				}{
					Type: "mrkdwn",
					Text: messageText,
				},
			},
		},
	}

	return json.Marshal(message)
}

func main() {
	if len(os.Args) < 4 {
		fmt.Println("Usage: go run main.go <PR_URL> <PR_TITLE> <PR_NUMBER>")
		os.Exit(1)
	}

	prURL := os.Args[1]
	prTitle := os.Args[2]
	prNumber := os.Args[3]

	_, currentFilePath, _, _ := runtime.Caller(0)
	currentDir := filepath.Dir(currentFilePath)
	configPath := filepath.Join(currentDir, "../env/config.json")

	config, err := loadConfig(configPath)
	if err != nil {
		fmt.Printf("Error loading config: %s\n", err)
		os.Exit(1)
	}

	message, err := BuildSlackMessage(prURL, prTitle, prNumber, config)
	if err != nil {
		fmt.Printf("Error building message: %s\n", err)
		os.Exit(1)
	}

	webhookURL := config.WebhookURL + config.WebhookComplement
	err = sendSlackMessage(message, webhookURL)
	if err != nil {
		fmt.Printf("Error sending message to Slack: %s\n", err)
		os.Exit(1)
	}

	fmt.Println("Message sent successfully.")
}

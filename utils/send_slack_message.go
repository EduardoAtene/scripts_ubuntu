package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

type Config struct {
	WebhookURL     string `json:"webhook_url"`
	SlackUserID    string `json:"slack_user_id"`
	GroupApprovers string `json:"group_approvers"`
}

type SlackMessageBlock struct {
	Type string    `json:"type"`
	Text *struct { // Usar ponteiro para tornar opcional
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"text,omitempty"` // Incluído apenas quando não for nil
}

type SlackMessage struct {
	Blocks    []SlackMessageBlock `json:"blocks"`
	Username  string              `json:"username"`
	IconEmoji string              `json:"icon_emoji"`
}

func loadConfig(filename string) (*Config, error) {
	file, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("erro ao ler arquivo de configuração: %w", err)
	}

	var config Config
	err = json.Unmarshal(file, &config)
	if err != nil {
		return nil, fmt.Errorf("erro ao fazer parse do arquivo de configuração: %w", err)
	}

	return &config, nil
}

func getUserName() string {
	// Tenta pegar nome do Git local
	gitNameCmd := exec.Command("git", "config", "user.name")
	gitNameOutput, err := gitNameCmd.Output()
	if err == nil && len(gitNameOutput) > 0 {
		return strings.TrimSpace(string(gitNameOutput))
	}

	// Fallback para GitHub username
	ghNameCmd := exec.Command("gh", "api", "user", "--jq", ".login")
	ghNameOutput, err := ghNameCmd.Output()
	if err == nil && len(ghNameOutput) > 0 {
		return strings.TrimSpace(string(ghNameOutput))
	}

	return "Desenvolvedor"
}

func sendSlackMessage(prURL string, prTitle string, prNumberPr string, config *Config) error {
	author := fmt.Sprintf("<@%s>", config.SlackUserID)
	groupApprovers := fmt.Sprintf("<!subteam^%s>", config.GroupApprovers)

	projectName := getProjectNameFromURL(prURL)
	titleWithLink := fmt.Sprintf("<%s|%s> #%s", prURL, prTitle, prNumberPr)

	messageText := fmt.Sprintf(
		`:rocket: *PR Criada - %s - %s* 
*🏷️ Título:* %s
*👥 Aprovadores:* %s
		`,
		author, projectName, titleWithLink, groupApprovers,
	)

	message := SlackMessage{
		Username:  "Alerquina",
		IconEmoji: ":alerquina-prs:",
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

	jsonData, err := json.Marshal(message)
	fmt.Println(string(jsonData))
	fmt.Printf("urlWebhook: %s\n", config.WebhookURL)

	if err != nil {
		return fmt.Errorf("erro ao converter mensagem para JSON: %w", err)
	}

	resp, err := http.Post(config.WebhookURL, "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("erro ao enviar a mensagem para o Slack: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("erro ao enviar mensagem, status code: %d", resp.StatusCode)
	}

	return nil
}

func main() {
	if len(os.Args) < 4 {
		fmt.Println("Uso: go run send_slack_message.go <PR_URL> <PR_TITLE> <PR_NUMBER>")
		os.Exit(1)
	}

	prURL := os.Args[1]
	prTitle := os.Args[2]
	prNumberPr := os.Args[3]

	// Carregar a configuração com caminho relativo ao diretório do arquivo atual
	_, currentFilePath, _, _ := runtime.Caller(0)
	currentDir := filepath.Dir(currentFilePath)
	configPath := filepath.Join(currentDir, "../env/config.json")

	// Carregar a configuração usando o caminho calculado
	config, err := loadConfig(configPath)
	if err != nil {
		fmt.Printf("Erro ao carregar configuração: %s\n", err)
		os.Exit(1)
	}

	err = sendSlackMessage(prURL, prTitle, prNumberPr, config)
	if err != nil {
		fmt.Printf("Erro ao enviar a mensagem ao Slack: %s\n", err)
		os.Exit(1)
	}

	fmt.Println("Mensagem enviada ao Slack com sucesso.")
}

func getProjectNameFromURL(url string) string {
	switch {
	case strings.Contains(url, "360-api"):
		return "Portal 360°"
	case strings.Contains(url, "wallet.em.cash"):
		return "Wallet"
	case strings.Contains(url, "controle.em.cash"):
		return "Controle"
	default:
		return "-"
	}
}

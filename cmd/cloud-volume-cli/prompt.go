// Interactive prompts are isolated here so init stays focused on config flow.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"

	"golang.org/x/term"
)

type promptUI struct {
	reader *bufio.Reader
	out    io.Writer
}

func newPromptUI() *promptUI {
	return &promptUI{
		reader: bufio.NewReader(os.Stdin),
		out:    os.Stdout,
	}
}

func (ui *promptUI) askString(label, defaultValue string, required bool) (string, error) {
	for {
		if defaultValue != "" {
			fmt.Fprintf(ui.out, "%s [%s]: ", label, defaultValue)
		} else {
			fmt.Fprintf(ui.out, "%s: ", label)
		}
		line, err := ui.reader.ReadString('\n')
		if err != nil {
			return "", err
		}
		value := strings.TrimSpace(line)
		if value == "" {
			value = strings.TrimSpace(defaultValue)
		}
		if required && value == "" {
			fmt.Fprintln(ui.out, "该项必填，请重新输入。")
			continue
		}
		return value, nil
	}
}

func (ui *promptUI) askBool(label string, defaultValue bool) (bool, error) {
	suffix := "y/N"
	if defaultValue {
		suffix = "Y/n"
	}
	for {
		fmt.Fprintf(ui.out, "%s [%s]: ", label, suffix)
		line, err := ui.reader.ReadString('\n')
		if err != nil {
			return false, err
		}
		value := strings.ToLower(strings.TrimSpace(line))
		switch value {
		case "":
			return defaultValue, nil
		case "y", "yes":
			return true, nil
		case "n", "no":
			return false, nil
		default:
			fmt.Fprintln(ui.out, "请输入 y 或 n。")
		}
	}
}

func (ui *promptUI) askSecret(label string, currentValue string) (string, error) {
	if term.IsTerminal(int(os.Stdin.Fd())) {
		prompt := fmt.Sprintf("%s", label)
		if strings.TrimSpace(currentValue) != "" {
			prompt += " [保留现有值请直接回车]"
		}
		fmt.Fprintf(ui.out, "%s: ", prompt)
		secret, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(ui.out)
		if err != nil {
			return "", err
		}
		value := strings.TrimSpace(string(secret))
		if value == "" && strings.TrimSpace(currentValue) != "" {
			return strings.TrimSpace(currentValue), nil
		}
		if value == "" {
			fmt.Fprintln(ui.out, "该项必填，请重新输入。")
			return ui.askSecret(label, currentValue)
		}
		return value, nil
	}
	return ui.askString(label, currentValue, true)
}

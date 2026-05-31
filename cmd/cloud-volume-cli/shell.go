// Interactive shell mode keeps repeated CLI operations short on headless servers.
package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"strings"

	s3ops "remote-storage/go/s3"
)

var errShellExit = errors.New("shell exit")

type shellState struct {
	configPath     string
	bucketOverride string
	currentDir     string
}

var activeShell *shellState

func runShell() error {
	loaded, err := loadConfig("")
	if err != nil {
		return err
	}
	state := &shellState{
		configPath: loaded.path,
	}
	activeShell = state
	defer func() {
		activeShell = nil
	}()

	if strings.TrimSpace(loaded.cfg.Bucket) != "" {
		state.bucketOverride = strings.TrimSpace(loaded.cfg.Bucket)
	}

	fmt.Fprintf(stdoutWriter(), "进入 cloud-volume shell。配置: %s\n", loaded.path)
	if strings.TrimSpace(state.bucketOverride) != "" {
		fmt.Fprintf(stdoutWriter(), "当前 bucket: %s\n", state.bucketOverride)
	}
	fmt.Fprintln(stdoutWriter(), "输入 help 查看命令，输入 exit 退出。")

	scanner := bufio.NewScanner(os.Stdin)
	for {
		fmt.Fprint(stdoutWriter(), shellPrompt(state))
		if !scanner.Scan() {
			if err := scanner.Err(); err != nil {
				return err
			}
			fmt.Fprintln(stdoutWriter())
			return nil
		}
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		args, err := splitShellLine(line)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			continue
		}
		if err := runShellCommand(state, args); err != nil {
			if errors.Is(err, errShellExit) {
				return nil
			}
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		}
	}
}

func shellPrompt(state *shellState) string {
	if state != nil && strings.TrimSpace(state.bucketOverride) != "" {
		dir := shellDisplayDir(state.currentDir)
		return fmt.Sprintf("cloud-volume[%s:%s]> ", strings.TrimSpace(state.bucketOverride), dir)
	}
	return "cloud-volume> "
}

func runShellCommand(state *shellState, args []string) error {
	if len(args) == 0 {
		return nil
	}
	switch strings.ToLower(strings.TrimSpace(args[0])) {
	case "exit", "quit":
		return errShellExit
	case "bucket":
		return runShellBucketCommand(state, args[1:])
	case "cd":
		return runShellCDCommand(state, args[1:])
	case "pwd":
		return runShellPWDCommand(state, args[1:])
	case "?":
		printShellHelp()
		return nil
	default:
		return run(args)
	}
}

func runShellBucketCommand(state *shellState, args []string) error {
	if state == nil {
		return errors.New("shell state is not initialized")
	}
	if len(args) == 0 {
		if strings.TrimSpace(state.bucketOverride) == "" {
			fmt.Fprintln(stdoutWriter(), "(empty)")
			return nil
		}
		fmt.Fprintln(stdoutWriter(), strings.TrimSpace(state.bucketOverride))
		return nil
	}
	if len(args) > 1 {
		return errors.New("bucket 用法: bucket [name]")
	}
	state.bucketOverride = strings.TrimSpace(args[0])
	state.currentDir = ""
	if state.bucketOverride == "" {
		fmt.Fprintln(stdoutWriter(), "已清空 shell bucket 覆盖值")
		return nil
	}
	fmt.Fprintf(stdoutWriter(), "当前 bucket 已切换为 %s\n", state.bucketOverride)
	return nil
}

func runShellCDCommand(state *shellState, args []string) error {
	if state == nil {
		return errors.New("shell state is not initialized")
	}
	if len(args) > 1 {
		return errors.New("cd 用法: cd [remote-dir]")
	}
	if strings.TrimSpace(state.bucketOverride) == "" {
		return errors.New("请先设置 bucket，再执行 cd")
	}

	targetDir := ""
	if len(args) == 1 {
		targetDir = resolveVisiblePath(state.currentDir, args[0])
	}
	if err := ensureRemoteDirectoryExists(state, targetDir); err != nil {
		return err
	}
	state.currentDir = targetDir
	fmt.Fprintln(stdoutWriter(), shellDisplayDir(state.currentDir))
	return nil
}

func runShellPWDCommand(state *shellState, args []string) error {
	if len(args) != 0 {
		return errors.New("pwd 不接受参数")
	}
	if state == nil {
		return errors.New("shell state is not initialized")
	}
	fmt.Fprintln(stdoutWriter(), shellDisplayDir(state.currentDir))
	return nil
}

func ensureRemoteDirectoryExists(state *shellState, visibleDir string) error {
	loaded, err := loadConfiguredConfig(state.configPath)
	if err != nil {
		return err
	}
	prefix := applyRootPrefix(loaded.cfg.RootPrefix, visibleDir, true)
	if prefix == "" {
		return nil
	}
	page, err := s3ops.ListObjectsPage(loaded.cfg, state.bucketOverride, prefix, "", 1)
	if err != nil {
		return err
	}
	if len(page.Items) > 0 {
		return nil
	}
	if _, err := s3ops.HeadObject(loaded.cfg, state.bucketOverride, strings.TrimSuffix(prefix, "/")); err == nil {
		return fmt.Errorf("%s 不是目录", shellDisplayDir(visibleDir))
	}
	if _, err := s3ops.HeadObject(loaded.cfg, state.bucketOverride, prefix); err == nil {
		return nil
	}
	return fmt.Errorf("远端目录不存在: %s", shellDisplayDir(visibleDir))
}

func printShellHelp() {
	printUsage(stdoutWriter())
	fmt.Fprintln(stdoutWriter(), "")
	fmt.Fprintln(stdoutWriter(), "Shell builtins:")
	fmt.Fprintln(stdoutWriter(), "  bucket [name]    查看或切换当前 shell 默认 bucket")
	fmt.Fprintln(stdoutWriter(), "  cd [dir]         切换当前远端目录，支持相对路径、.. 和绝对路径")
	fmt.Fprintln(stdoutWriter(), "  pwd              输出当前远端目录")
	fmt.Fprintln(stdoutWriter(), "  exit | quit      退出 shell")
}

func shellDisplayDir(value string) string {
	clean := cleanObjectPath(value)
	if clean == "" {
		return "/"
	}
	return "/" + clean
}

func currentShellDir() string {
	if activeShell == nil {
		return ""
	}
	return cleanObjectPath(activeShell.currentDir)
}

func splitShellLine(line string) ([]string, error) {
	args := make([]string, 0)
	current := strings.Builder{}
	inQuote := byte(0)
	escaped := false

	flush := func() {
		if current.Len() == 0 {
			return
		}
		args = append(args, current.String())
		current.Reset()
	}

	for index := 0; index < len(line); index++ {
		ch := line[index]
		switch {
		case escaped:
			current.WriteByte(ch)
			escaped = false
		case ch == '\\':
			escaped = true
		case inQuote != 0:
			if ch == inQuote {
				inQuote = 0
				continue
			}
			current.WriteByte(ch)
		case ch == '\'' || ch == '"':
			inQuote = ch
		case ch == ' ' || ch == '\t':
			flush()
		default:
			current.WriteByte(ch)
		}
	}
	if escaped {
		current.WriteByte('\\')
	}
	if inQuote != 0 {
		return nil, fmt.Errorf("unterminated quote %q", string(inQuote))
	}
	flush()
	return args, nil
}

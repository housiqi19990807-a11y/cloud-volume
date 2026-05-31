// Command routing is kept in one file so subcommands stay easy to discover.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
)

func run(args []string) error {
	if len(args) == 0 {
		return runShell()
	}

	switch strings.ToLower(strings.TrimSpace(args[0])) {
	case "help", "-h", "--help":
		printUsage(os.Stdout)
		return nil
	case "version", "--version":
		fmt.Fprintln(os.Stdout, version)
		return nil
	case "init":
		return runInitCommand(args[1:])
	case "shell":
		return runShell()
	case "mount":
		return runMountCommand(args[1:])
	case "unmount":
		return runUnmountCommand(args[1:])
	case "status":
		return runStatusCommand(args[1:])
	case "put":
		return runPutCommand(args[1:])
	case "get":
		return runGetCommand(args[1:])
	case "list", "ls":
		return runListCommand(args[1:])
	default:
		printUsage(os.Stderr)
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func newFlagSet(name string) *flag.FlagSet {
	set := flag.NewFlagSet(name, flag.ContinueOnError)
	set.SetOutput(io.Discard)
	return set
}

func printUsage(w io.Writer) {
	fmt.Fprintln(w, "Usage:")
	fmt.Fprintln(w, "  cloud-volume-cli                    # enter interactive shell")
	fmt.Fprintln(w, "  cloud-volume-cli shell")
	fmt.Fprintln(w, "  cloud-volume-cli init [--config /path/to/config.toml] [--skip-validate]")
	fmt.Fprintln(w, "  cloud-volume-cli put [--config /path/to/config.toml] [--bucket name] <local-path> [remote-path]")
	fmt.Fprintln(w, "  cloud-volume-cli get [--config /path/to/config.toml] [--bucket name] <remote-path> [local-path]")
	fmt.Fprintln(w, "  cloud-volume-cli ls [--config /path/to/config.toml] [--bucket name] [prefix]")
	fmt.Fprintln(w, "  cloud-volume-cli list [--config /path/to/config.toml] [--bucket name] [prefix]")
	fmt.Fprintln(w, "  cloud-volume-cli mount [--config /path/to/config.toml] [--bucket name] [--mount-point /path]")
	fmt.Fprintln(w, "  cloud-volume-cli unmount [--config /path/to/config.toml] [--bucket name] [--mount-point /path]")
	fmt.Fprintln(w, "  cloud-volume-cli status [--config /path/to/config.toml] [--bucket name] [--mount-point /path]")
	fmt.Fprintln(w, "  cloud-volume-cli version")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Examples:")
	fmt.Fprintln(w, "  cloud-volume-cli init")
	fmt.Fprintln(w, "  cloud-volume-cli put ./demo.txt docs/demo.txt")
	fmt.Fprintln(w, "  cloud-volume-cli get docs/demo.txt ./demo.txt")
	fmt.Fprintln(w, "  cloud-volume-cli ls docs")
	fmt.Fprintln(w, "  cloud-volume-cli mount --bucket media --mount-point /mnt/media")
	fmt.Fprintln(w, "  cloud-volume-cli status --bucket media")
	fmt.Fprintln(w, "  cloud-volume-cli unmount --bucket media")
}

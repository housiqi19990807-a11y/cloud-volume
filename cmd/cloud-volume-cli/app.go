// Command routing is kept in one file so subcommands stay easy to discover.
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
)

func run(args []string) error {
	if len(args) == 0 {
		printUsage(os.Stderr)
		return errors.New("missing command")
	}

	switch strings.ToLower(strings.TrimSpace(args[0])) {
	case "help", "-h", "--help":
		printUsage(os.Stdout)
		return nil
	case "init":
		return runInitCommand(args[1:])
	case "mount":
		return runMountCommand(args[1:])
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
	fmt.Fprintln(w, "  cloud-volume-cli init [--config /path/to/config.toml] [--skip-validate]")
	fmt.Fprintln(w, "  cloud-volume-cli mount [--config /path/to/config.toml] [--bucket name] [--mount-point /path]")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Examples:")
	fmt.Fprintln(w, "  cloud-volume-cli init")
	fmt.Fprintln(w, "  cloud-volume-cli mount --bucket media --mount-point /mnt/media")
}

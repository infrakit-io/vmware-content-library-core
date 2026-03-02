package contentlibrary

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Runner executes govc commands.
type Runner interface {
	Run(ctx context.Context, args ...string) ([]byte, error)
}

// GovcRunner runs commands via local govc binary.
type GovcRunner struct {
	Command string
	Env     []string
}

// Run executes a govc command with configured environment.
func (r GovcRunner) Run(ctx context.Context, args ...string) ([]byte, error) {
	cmdName := strings.TrimSpace(r.Command)
	if cmdName == "" {
		cmdName = "govc"
	}
	cmd := exec.CommandContext(ctx, cmdName, args...)
	if len(r.Env) > 0 {
		cmd.Env = append(os.Environ(), r.Env...)
	}
	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = strings.TrimSpace(out.String())
		}
		if msg != "" {
			return nil, fmt.Errorf("%w: %s", err, msg)
		}
		return nil, err
	}
	return out.Bytes(), nil
}

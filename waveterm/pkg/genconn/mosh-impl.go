// Copyright 2025, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

package genconn

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"

	"golang.org/x/crypto/ssh"
)

const (
	MoshDefaultColorDepth = 256
	MoshDefaultLocale     = "LANG=en_US.UTF-8"
	MoshConnectPrefix     = "MOSH CONNECT"
)

var _ ShellClient = (*MoshShellClient)(nil)

// MoshShellClient wraps the local mosh-client binary to provide a Mosh connection.
// SSH is used to start mosh-server on the remote, then a local mosh-client process
// is spawned to handle the terminal I/O over UDP/SSP.
type MoshShellClient struct {
	sshClient  *ssh.Client
	remoteHost string
}

// MakeMoshShellClient creates a new Mosh shell client
func MakeMoshShellClient(sshClient *ssh.Client, remoteHost string) *MoshShellClient {
	return &MoshShellClient{
		sshClient:  sshClient,
		remoteHost: remoteHost,
	}
}

func (c *MoshShellClient) MakeProcessController(cmdSpec CommandSpec) (ShellProcessController, error) {
	// First check if mosh-server is available on remote
	log.Printf("MOSH: Checking for remote mosh-server\n")
	if err := CheckRemoteMoshServer(c.sshClient); err != nil {
		return nil, fmt.Errorf("mosh-server not available on %s: %w", c.remoteHost, err)
	}

	// Find local mosh-client binary
	log.Printf("MOSH: Finding local mosh-client binary\n")
	moshClientPath, err := FindMoshClientBinary()
	if err != nil {
		return nil, fmt.Errorf("mosh-client not found on local machine (remote: %s): %w", c.remoteHost, err)
	}
	log.Printf("MOSH: Found mosh-client at %s\n", moshClientPath)

	// Create SSH session to start mosh-server
	log.Printf("MOSH: Creating SSH session to start mosh-server\n")
	session, err := c.sshClient.NewSession()
	if err != nil {
		return nil, fmt.Errorf("failed to create SSH session: %w", err)
	}
	defer session.Close()

	// Capture stdout from mosh-server
	var stdout bytes.Buffer
	session.Stdout = &stdout

	// Run mosh-server new command
	moshServerCmd := fmt.Sprintf("mosh-server new -s -c %d -l %s", MoshDefaultColorDepth, MoshDefaultLocale)
	log.Printf("MOSH: Running: %s\n", moshServerCmd)
	if err := session.Run(moshServerCmd); err != nil {
		return nil, fmt.Errorf("failed to start mosh-server: %w", err)
	}

	// Parse MOSH CONNECT line
	output := stdout.String()
	log.Printf("MOSH: Server output: %s\n", output)
	port, key, err := ParseMoshConnectLine(output)
	if err != nil {
		return nil, fmt.Errorf("failed to parse mosh-server output: %w", err)
	}
	log.Printf("MOSH: Parsed connection - port: %s, key length: %d\n", port, len(key))

	// Create local mosh-client command
	cmd := exec.Command(moshClientPath, c.remoteHost, port)
	cmd.Env = append(os.Environ(), fmt.Sprintf("MOSH_KEY=%s", key))

	log.Printf("MOSH: Created mosh-client command: %s %s %s\n", moshClientPath, c.remoteHost, port)

	return &MoshProcessController{
		cmd:  cmd,
		lock: &sync.Mutex{},
		once: &sync.Once{},
	}, nil
}

// MoshProcessController implements ShellProcessController for Mosh connections
type MoshProcessController struct {
	cmd         *exec.Cmd
	lock        *sync.Mutex
	once        *sync.Once
	stdinPiped  bool
	stdoutPiped bool
	stderrPiped bool
	waitErr     error
	started     bool
}

// GetCmd returns the underlying exec.Cmd for PTY wrapping.
// This is used by shellexec to start the mosh-client with a local PTY.
func (m *MoshProcessController) GetCmd() *exec.Cmd {
	return m.cmd
}

// Start begins execution of the mosh-client command
func (m *MoshProcessController) Start() error {
	m.lock.Lock()
	defer m.lock.Unlock()

	if m.started {
		return fmt.Errorf("command already started")
	}

	if err := m.cmd.Start(); err != nil {
		return fmt.Errorf("failed to start mosh-client: %w", err)
	}

	m.started = true
	log.Printf("MOSH: Process started successfully\n")
	return nil
}

// Wait waits for the mosh-client command to complete
func (m *MoshProcessController) Wait() error {
	m.once.Do(func() {
		m.waitErr = m.cmd.Wait()
		if m.waitErr != nil {
			log.Printf("MOSH: Process wait error: %v\n", m.waitErr)
		} else {
			log.Printf("MOSH: Process completed successfully\n")
		}
	})
	return m.waitErr
}

// Kill terminates the mosh-client command
func (m *MoshProcessController) Kill() {
	m.lock.Lock()
	defer m.lock.Unlock()

	if m.cmd == nil {
		return
	}
	process := m.cmd.Process
	if process == nil {
		return
	}
	log.Printf("MOSH: Killing process\n")
	process.Kill()
}

func (m *MoshProcessController) StdinPipe() (io.WriteCloser, error) {
	m.lock.Lock()
	defer m.lock.Unlock()

	if m.started {
		return nil, fmt.Errorf("command already started")
	}
	if m.stdinPiped {
		return nil, fmt.Errorf("stdin already piped")
	}

	m.stdinPiped = true
	return m.cmd.StdinPipe()
}

func (m *MoshProcessController) StdoutPipe() (io.Reader, error) {
	m.lock.Lock()
	defer m.lock.Unlock()

	if m.started {
		return nil, fmt.Errorf("command already started")
	}
	if m.stdoutPiped {
		return nil, fmt.Errorf("stdout already piped")
	}

	m.stdoutPiped = true
	stdout, err := m.cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	return stdout, nil
}

func (m *MoshProcessController) StderrPipe() (io.Reader, error) {
	m.lock.Lock()
	defer m.lock.Unlock()

	if m.started {
		return nil, fmt.Errorf("command already started")
	}
	if m.stderrPiped {
		return nil, fmt.Errorf("stderr already piped")
	}

	m.stderrPiped = true
	stderr, err := m.cmd.StderrPipe()
	if err != nil {
		return nil, err
	}
	return stderr, nil
}

// ParseMoshConnectLine parses "MOSH CONNECT <port> <key>" from mosh-server output
// Returns (port string, key string, error)
func ParseMoshConnectLine(output string) (string, string, error) {
	// Look for "MOSH CONNECT <port> <key>" in the output
	re := regexp.MustCompile(`MOSH CONNECT (\d+) ([A-Za-z0-9+/=]+)`)
	matches := re.FindStringSubmatch(output)
	if len(matches) != 3 {
		return "", "", fmt.Errorf("could not find MOSH CONNECT line in output")
	}

	port := matches[1]
	key := matches[2]

	if port == "" || key == "" {
		return "", "", fmt.Errorf("invalid MOSH CONNECT line: port or key is empty")
	}

	return port, key, nil
}

// FindMoshClientBinary finds the mosh-client binary on the local system
// Checks: PATH, then platform-specific paths.
// Exported for auto-detection probing from shellcontroller.
func FindMoshClientBinary() (string, error) {
	// First try to find in PATH
	path, err := exec.LookPath("mosh-client")
	if err == nil {
		return path, nil
	}

	// Platform-specific fallback paths
	var searchPaths []string

	switch runtime.GOOS {
	case "windows":
		// Windows: check scoop, chocolatey, and common install locations
		homeDir, err := os.UserHomeDir()
		if err == nil {
			searchPaths = append(searchPaths,
				filepath.Join(homeDir, "scoop", "shims", "mosh-client.exe"),
				filepath.Join(homeDir, "scoop", "apps", "mosh", "current", "mosh-client.exe"),
			)
		}
		searchPaths = append(searchPaths,
			"C:\\ProgramData\\chocolatey\\bin\\mosh-client.exe",
			"C:\\Program Files\\mosh\\mosh-client.exe",
			"C:\\Program Files (x86)\\mosh\\mosh-client.exe",
		)

	case "darwin":
		// macOS: check homebrew paths
		searchPaths = append(searchPaths,
			"/usr/local/bin/mosh-client",
			"/opt/homebrew/bin/mosh-client",
			"/opt/local/bin/mosh-client", // MacPorts
		)

	case "linux":
		// Linux: check standard paths
		searchPaths = append(searchPaths,
			"/usr/bin/mosh-client",
			"/usr/local/bin/mosh-client",
			"/opt/bin/mosh-client",
		)

	default:
		// Other Unix-like systems
		searchPaths = append(searchPaths,
			"/usr/bin/mosh-client",
			"/usr/local/bin/mosh-client",
		)
	}

	// Check each path
	for _, path := range searchPaths {
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}

	return "", fmt.Errorf("mosh-client binary not found in PATH or common locations")
}

// CheckRemoteMoshServer checks if mosh-server is available on remote via SSH.
// Exported so that auto-detection logic in shellcontroller can probe without starting a full mosh session.
func CheckRemoteMoshServer(client *ssh.Client) error {
	session, err := client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create SSH session: %w", err)
	}
	defer session.Close()

	// Try to find mosh-server
	var stdout bytes.Buffer
	session.Stdout = &stdout

	// Use 'command -v' which is POSIX-compliant
	if err := session.Run("command -v mosh-server"); err != nil {
		return fmt.Errorf("mosh-server not found on remote host (try: apt install mosh / yum install mosh / brew install mosh)")
	}

	moshServerPath := strings.TrimSpace(stdout.String())
	if moshServerPath == "" {
		return fmt.Errorf("mosh-server not found on remote host")
	}

	log.Printf("MOSH: Found mosh-server on remote at: %s\n", moshServerPath)
	return nil
}

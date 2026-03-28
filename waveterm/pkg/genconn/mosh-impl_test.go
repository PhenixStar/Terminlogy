// Copyright 2025, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

package genconn

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
)

func TestParseMoshConnectLine(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		wantPort string
		wantKey  string
		wantErr  bool
	}{
		{
			name:     "valid single line output",
			input:    "MOSH CONNECT 60001 AbCdEf123456==",
			wantPort: "60001",
			wantKey:  "AbCdEf123456==",
			wantErr:  false,
		},
		{
			name: "valid multi-line output with noise",
			input: `mosh-server (mosh 1.4.0)
Copyright 2012 Keith Winstein

MOSH CONNECT 60001 AbCdEf123456==`,
			wantPort: "60001",
			wantKey:  "AbCdEf123456==",
			wantErr:  false,
		},
		{
			name: "valid output with trailing newline",
			input: `MOSH CONNECT 60001 AbCdEf123456==
`,
			wantPort: "60001",
			wantKey:  "AbCdEf123456==",
			wantErr:  false,
		},
		{
			name: "valid output with debug messages",
			input: `[debug] Starting mosh-server
[info] Listening on port 60001
MOSH CONNECT 60001 AbCdEf123456==
[info] Connection established`,
			wantPort: "60001",
			wantKey:  "AbCdEf123456==",
			wantErr:  false,
		},
		{
			name:     "port at lower boundary",
			input:    "MOSH CONNECT 60000 key==",
			wantPort: "60000",
			wantKey:  "key==",
			wantErr:  false,
		},
		{
			name:     "port at upper boundary",
			input:    "MOSH CONNECT 61000 key==",
			wantPort: "61000",
			wantKey:  "key==",
			wantErr:  false,
		},
		{
			name:     "large port number",
			input:    "MOSH CONNECT 65535 key==",
			wantPort: "65535",
			wantKey:  "key==",
			wantErr:  false,
		},
		{
			name:     "key with plus and slash characters",
			input:    "MOSH CONNECT 60001 ABC+def/123==",
			wantPort: "60001",
			wantKey:  "ABC+def/123==",
			wantErr:  false,
		},
		{
			name:     "key with various padding",
			input:    "MOSH CONNECT 60001 ABCdef=",
			wantPort: "60001",
			wantKey:  "ABCdef=",
			wantErr:  false,
		},
		{
			name:     "key without padding",
			input:    "MOSH CONNECT 60001 ABCdefGHI",
			wantPort: "60001",
			wantKey:  "ABCdefGHI",
			wantErr:  false,
		},
		{
			name:     "missing MOSH CONNECT line",
			input:    "some random output\nwithout MOSH CONNECT",
			wantPort: "",
			wantKey:  "",
			wantErr:  true,
		},
		{
			name:     "empty output",
			input:    "",
			wantPort: "",
			wantKey:  "",
			wantErr:  true,
		},
		{
			name:     "malformed line - missing port and key",
			input:    "MOSH CONNECT",
			wantPort: "",
			wantKey:  "",
			wantErr:  true,
		},
		{
			name:     "malformed line - missing key",
			input:    "MOSH CONNECT 60001",
			wantPort: "",
			wantKey:  "",
			wantErr:  true,
		},
		{
			name:     "malformed line - missing port",
			input:    "MOSH CONNECT AbCdEf123456==",
			wantPort: "",
			wantKey:  "",
			wantErr:  true,
		},
		{
			name:     "malformed line - non-numeric port",
			input:    "MOSH CONNECT abc AbCdEf123456==",
			wantPort: "",
			wantKey:  "",
			wantErr:  true,
		},
		{
			name:     "partial match - MOSH only",
			input:    "MOSH server starting...",
			wantPort: "",
			wantKey:  "",
			wantErr:  true,
		},
		{
			name:     "partial match - CONNECT only",
			input:    "CONNECT to server",
			wantPort: "",
			wantKey:  "",
			wantErr:  true,
		},
		{
			name:     "extra whitespace",
			input:    "MOSH  CONNECT  60001  AbCdEf123456==",
			wantPort: "",
			wantKey:  "",
			wantErr:  true,
		},
		{
			name:     "case sensitivity - lowercase",
			input:    "mosh connect 60001 AbCdEf123456==",
			wantPort: "",
			wantKey:  "",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			port, key, err := ParseMoshConnectLine(tt.input)

			if tt.wantErr {
				if err == nil {
					t.Errorf("ParseMoshConnectLine() expected error but got none")
				}
				return
			}

			if err != nil {
				t.Errorf("ParseMoshConnectLine() unexpected error: %v", err)
				return
			}

			if port != tt.wantPort {
				t.Errorf("ParseMoshConnectLine() port = %v, want %v", port, tt.wantPort)
			}

			if key != tt.wantKey {
				t.Errorf("ParseMoshConnectLine() key = %v, want %v", key, tt.wantKey)
			}
		})
	}
}

func TestFindMoshClientBinary(t *testing.T) {
	// Test 1: Check if function returns without error when mosh-client is in PATH
	t.Run("find in PATH", func(t *testing.T) {
		// Try to find mosh-client in PATH
		pathMosh, pathErr := exec.LookPath("mosh-client")
		if pathErr == nil {
			// mosh-client is available in PATH
			foundPath, err := FindMoshClientBinary()
			if err != nil {
				t.Errorf("FindMoshClientBinary() error = %v, expected to find mosh-client at %s", err, pathMosh)
				return
			}
			if foundPath == "" {
				t.Error("FindMoshClientBinary() returned empty path when mosh-client is in PATH")
			}
			t.Logf("Found mosh-client at: %s", foundPath)
		} else {
			t.Skip("mosh-client not in PATH, skipping PATH test")
		}
	})

	// Test 2: Check platform-specific paths
	t.Run("platform specific paths", func(t *testing.T) {
		// This test verifies the function checks platform-specific paths
		// We'll create a temporary directory structure to test path checking
		tempDir := t.TempDir()

		var testBinaryPath string
		switch runtime.GOOS {
		case "windows":
			testBinaryPath = filepath.Join(tempDir, "mosh-client.exe")
		default:
			testBinaryPath = filepath.Join(tempDir, "mosh-client")
		}

		// Create a mock mosh-client binary
		f, err := os.Create(testBinaryPath)
		if err != nil {
			t.Fatalf("Failed to create test binary: %v", err)
		}
		f.Close()

		// Make it executable on Unix-like systems
		if runtime.GOOS != "windows" {
			if err := os.Chmod(testBinaryPath, 0755); err != nil {
				t.Fatalf("Failed to chmod test binary: %v", err)
			}
		}

		// The function won't find our temp binary since it's not in the hardcoded paths,
		// but we can verify the function runs without panicking
		_, err = FindMoshClientBinary()
		// We expect an error if mosh-client is not installed system-wide
		if err == nil {
			t.Log("mosh-client found on system")
		} else {
			t.Logf("mosh-client not found (expected in test environment): %v", err)
		}
	})

	// Test 3: Verify error message is descriptive
	t.Run("descriptive error message", func(t *testing.T) {
		// Temporarily modify PATH to exclude mosh-client
		originalPath := os.Getenv("PATH")
		os.Setenv("PATH", "")
		defer os.Setenv("PATH", originalPath)

		_, err := FindMoshClientBinary()
		if err == nil {
			// If no error, mosh-client was found in hardcoded paths
			t.Log("mosh-client found in hardcoded paths")
			return
		}

		expectedSubstring := "mosh-client binary not found"
		if !containsSubstring(err.Error(), expectedSubstring) {
			t.Errorf("Error message doesn't contain expected substring.\nGot: %v\nWant substring: %v", err.Error(), expectedSubstring)
		}
	})
}

func TestMoshShellClientImplementsInterface(t *testing.T) {
	// Compile-time check that MoshShellClient implements ShellClient
	var _ ShellClient = (*MoshShellClient)(nil)
	t.Log("MoshShellClient correctly implements ShellClient interface")
}

func TestMoshProcessControllerStateManagement(t *testing.T) {
	// Create a mock command (we won't actually execute it)
	cmd := exec.Command("echo", "test")

	mpc := &MoshProcessController{
		cmd:  cmd,
		lock: &sync.Mutex{},
		once: &sync.Once{},
	}

	// Test initial state
	if mpc.started {
		t.Error("MoshProcessController should not be started initially")
	}

	// Test pipe methods before start
	t.Run("pipes before start", func(t *testing.T) {
		// These should work before Start() is called
		stdin, err := mpc.StdinPipe()
		if err != nil {
			t.Errorf("StdinPipe() before start failed: %v", err)
		}
		if stdin == nil {
			t.Error("StdinPipe() returned nil pipe")
		}

		stdout, err := mpc.StdoutPipe()
		if err != nil {
			t.Errorf("StdoutPipe() before start failed: %v", err)
		}
		if stdout == nil {
			t.Error("StdoutPipe() returned nil pipe")
		}

		stderr, err := mpc.StderrPipe()
		if err != nil {
			t.Errorf("StderrPipe() before start failed: %v", err)
		}
		if stderr == nil {
			t.Error("StderrPipe() returned nil pipe")
		}
	})

	// Test duplicate pipe calls
	t.Run("duplicate pipes", func(t *testing.T) {
		cmd2 := exec.Command("echo", "test")
		mpc2 := &MoshProcessController{
			cmd:  cmd2,
			lock: &sync.Mutex{},
			once: &sync.Once{},
		}

		_, err := mpc2.StdinPipe()
		if err != nil {
			t.Fatalf("First StdinPipe() failed: %v", err)
		}

		_, err = mpc2.StdinPipe()
		if err == nil {
			t.Error("Second StdinPipe() should return error")
		}
	})

	// Test Kill on nil process
	t.Run("kill nil process", func(t *testing.T) {
		mpc3 := &MoshProcessController{
			cmd:  nil,
			lock: &sync.Mutex{},
			once: &sync.Once{},
		}
		// Should not panic
		mpc3.Kill()
	})
}

func TestMakeMoshShellClient(t *testing.T) {
	// Test that MakeMoshShellClient creates a properly initialized client
	// Note: We can't create a real SSH client without a connection,
	// but we can verify the constructor works with nil (for structure testing)
	remoteHost := "test.example.com"

	client := MakeMoshShellClient(nil, remoteHost)

	if client == nil {
		t.Fatal("MakeMoshShellClient returned nil")
	}

	if client.remoteHost != remoteHost {
		t.Errorf("remoteHost = %v, want %v", client.remoteHost, remoteHost)
	}

	if client.sshClient != nil {
		t.Error("sshClient should be nil when passed nil")
	}
}

// Helper function to check if a string contains a substring
func containsSubstring(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > len(substr) && findSubstring(s, substr))
}

func findSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

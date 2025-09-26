package docker

import (
	"os"
	"path/filepath"
	"testing"
)

// Helper function to create a temporary Dockerfile with given content
func createTempDockerfile(t *testing.T, content string) string {
	tempDir, err := os.MkdirTemp("", "dockerfile_test")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(tempDir) })

	dockerfilePath := filepath.Join(tempDir, "Dockerfile")
	err = os.WriteFile(dockerfilePath, []byte(content), 0644)
	if err != nil {
		t.Fatalf("Failed to create test Dockerfile: %v", err)
	}
	return dockerfilePath
}

func TestExtractPlatformFromDockerfile_WithPlatformLabel(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL platform=linux/amd64
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if platform != "linux/amd64" {
		t.Errorf("Expected platform %q, got %q", "linux/amd64", platform)
	}
}

func TestExtractPlatformFromDockerfile_CaseInsensitivePlatformLabel(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL PLATFORM=linux/arm64
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if platform != "linux/arm64" {
		t.Errorf("Expected platform %q, got %q", "linux/arm64", platform)
	}
}

func TestExtractPlatformFromDockerfile_MixedCasePlatformLabel(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL Platform=linux/arm/v7
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if platform != "linux/arm/v7" {
		t.Errorf("Expected platform %q, got %q", "linux/arm/v7", platform)
	}
}

func TestExtractPlatformFromDockerfile_MultipleLabelsIncludingPlatform(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL version=1.0
LABEL platform=linux/amd64
LABEL maintainer=test@example.com
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if platform != "linux/amd64" {
		t.Errorf("Expected platform %q, got %q", "linux/amd64", platform)
	}
}

func TestExtractPlatformFromDockerfile_MultipleLabelsOnSameLineIncludingPlatform(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL version=1.0 platform=linux/s390x maintainer=test@example.com
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if platform != "linux/s390x" {
		t.Errorf("Expected platform %q, got %q", "linux/s390x", platform)
	}
}

func TestExtractPlatformFromDockerfile_WithoutPlatformLabel(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL version=1.0
LABEL maintainer=test@example.com
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if platform != "" {
		t.Errorf("Expected platform %q, got %q", "", platform)
	}
}

func TestExtractPlatformFromDockerfile_NoLabels(t *testing.T) {
	content := `FROM ubuntu:20.04
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if platform != "" {
		t.Errorf("Expected platform %q, got %q", "", platform)
	}
}

func TestExtractPlatformFromDockerfile_PlatformLabelInMultiStageBuild(t *testing.T) {
	content := `FROM ubuntu:20.04 as builder
LABEL platform=linux/amd64
RUN echo "Building"

FROM alpine:latest
COPY --from=builder /app /app`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if platform != "linux/amd64" {
		t.Errorf("Expected platform %q, got %q", "linux/amd64", platform)
	}
}

func TestExtractPlatformFromDockerfile_PlatformLabelInSecondStage(t *testing.T) {
	content := `FROM ubuntu:20.04 as builder
RUN echo "Building"

FROM alpine:latest
LABEL platform=linux/arm64
COPY --from=builder /app /app`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if platform != "linux/arm64" {
		t.Errorf("Expected platform %q, got %q", "linux/arm64", platform)
	}
}

func TestExtractPlatformFromDockerfile_PlatformLabelsInMultipleStagesFirstWins(t *testing.T) {
	content := `FROM ubuntu:20.04 as builder
LABEL platform=linux/amd64
RUN echo "Building"

FROM alpine:latest
LABEL platform=linux/arm64
COPY --from=builder /app /app`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if platform != "linux/amd64" {
		t.Errorf("Expected platform %q, got %q", "linux/amd64", platform)
	}
}

func TestExtractPlatformFromDockerfile_NonExistentFile(t *testing.T) {
	platform, err := ExtractPlatformFromDockerfile("/nonexistent/path/Dockerfile")

	if err == nil {
		t.Errorf("Expected error but got none")
	}
	if platform != "" {
		t.Errorf("Expected empty platform for error case, got %q", platform)
	}
}

func TestExtractPlatformFromDockerfile_EmptyFilepath(t *testing.T) {
	platform, err := ExtractPlatformFromDockerfile("")

	if err == nil {
		t.Errorf("Expected error but got none")
	}
	if platform != "" {
		t.Errorf("Expected empty platform for error case, got %q", platform)
	}
}

func TestExtractPlatformFromDockerfile_InvalidDockerfileSyntax(t *testing.T) {
	content := `INVALID INSTRUCTION
LABEL platform=linux/amd64`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err == nil {
		t.Errorf("Expected error but got none")
	}
	if platform != "" {
		t.Errorf("Expected empty platform for error case, got %q", platform)
	}
}

func TestExtractPlatformFromDockerfile_EmptyFile(t *testing.T) {
	content := ""

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	if err == nil {
		t.Errorf("Expected error but got none")
	}
	if platform != "" {
		t.Errorf("Expected empty platform for error case, got %q", platform)
	}
}

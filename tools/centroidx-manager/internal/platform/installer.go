package platform

// Installer is the interface for platform-specific installation operations.
// Each OS has a concrete implementation (windows.go, linux.go, darwin.go).
// This file has no build tag and compiles on all platforms.
type Installer interface {
	// Install installs the application from the given asset path.
	// On Windows: runs Add-AppxPackage via PowerShell.
	// On Linux: runs dpkg -i via pkexec or sudo.
	// On macOS: mounts DMG and copies .app or runs .pkg installer.
	Install(assetPath string) error

	// TrustCertificate installs a self-signed certificate into the OS trust store.
	// On Windows: imports to LocalMachine\TrustedPeople (not Root).
	// On Linux/macOS: no-op (certificate trust handled differently or not needed).
	TrustCertificate(certPath string) error

	// LaunchApp starts the installed application after update.
	LaunchApp() error
}

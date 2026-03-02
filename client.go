package contentlibrary

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
)

type libraryInfoJSON struct {
	Library struct {
		ID   string `json:"ID"`
		Name string `json:"Name"`
	} `json:"Library"`
}

// LibraryRef identifies a content library.
type LibraryRef struct {
	ID     string
	Name   string
	Target string
}

// DeployOptions controls govc library.deploy invocation.
type DeployOptions struct {
	Datacenter   string
	Datastore    string
	Folder       string
	ResourcePool string
	OptionsPath  string
	ItemPath     string
	VMName       string
}

// Client provides idempotent content library operations.
type Client struct {
	runner Runner
	locks  sync.Map
}

// NewClient creates a client with a command runner.
func NewClient(runner Runner) *Client {
	return &Client{runner: runner}
}

// ResolveLibraryID returns the library ID for a given library name.
func (c *Client) ResolveLibraryID(ctx context.Context, name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", fmt.Errorf("library name is required")
	}
	out, err := c.runner.Run(ctx, "library.info", "-json", name)
	if err != nil {
		return "", err
	}
	return parseLibraryID(out)
}

// EnsureLibrary ensures a named library exists and returns ID + target path.
func (c *Client) EnsureLibrary(ctx context.Context, name string) (LibraryRef, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return LibraryRef{}, fmt.Errorf("library name is required")
	}
	id, err := c.ResolveLibraryID(ctx, name)
	if err == nil {
		return LibraryRef{ID: id, Name: name, Target: id}, nil
	}
	if !isNoMatch(err) {
		return LibraryRef{}, fmt.Errorf("resolve library %q: %w", name, err)
	}
	if _, err := c.runner.Run(ctx, "library.create", name); err != nil {
		return LibraryRef{}, fmt.Errorf("create library %q: %w", name, err)
	}
	id, err = c.ResolveLibraryID(ctx, name)
	if err != nil {
		return LibraryRef{}, fmt.Errorf("resolve library %q after create: %w", name, err)
	}
	return LibraryRef{ID: id, Name: name, Target: id}, nil
}

// ItemPath returns govc path format <library>/<item>.
func ItemPath(libraryTarget, itemName string) string {
	return fmt.Sprintf("%s/%s", strings.TrimSpace(libraryTarget), strings.TrimSpace(itemName))
}

// ItemExists checks if an item exists in content library.
func (c *Client) ItemExists(ctx context.Context, libraryTarget, itemName string) (bool, error) {
	out, err := c.runner.Run(ctx, "library.info", "-json", ItemPath(libraryTarget, itemName))
	if err != nil {
		return false, err
	}
	return parseInfoPresence(out), nil
}

// RemoveItem deletes item from library.
func (c *Client) RemoveItem(ctx context.Context, libraryTarget, itemName string) {
	_, _ = c.runner.Run(ctx, "library.rm", ItemPath(libraryTarget, itemName))
}

// ImportItemFromURL imports item from remote URL.
// First it tries server-side pull. If that fails, it retries client-side import.
func (c *Client) ImportItemFromURL(ctx context.Context, libraryTarget, itemName, artifactURL string) error {
	if _, err := c.runner.Run(ctx, "library.import", "-pull", "-n", itemName, libraryTarget, artifactURL); err == nil {
		return nil
	}
	c.RemoveItem(ctx, libraryTarget, itemName)
	if _, err := c.runner.Run(ctx, "library.import", "-n", itemName, libraryTarget, artifactURL); err != nil {
		if isAlreadyExists(err) {
			return nil
		}
		return fmt.Errorf("library.import failed (pull and fallback): %w", err)
	}
	return nil
}

// EnsureItemFromURL imports item only if missing.
// Check+import is serialized per library/item key to avoid concurrent duplicate imports.
func (c *Client) EnsureItemFromURL(ctx context.Context, libraryTarget, itemName, artifactURL string) error {
	key := ItemPath(libraryTarget, itemName)
	lockAny, _ := c.locks.LoadOrStore(key, &sync.Mutex{})
	lock := lockAny.(*sync.Mutex)
	lock.Lock()
	defer lock.Unlock()

	exists, err := c.ItemExists(ctx, libraryTarget, itemName)
	if err != nil {
		return fmt.Errorf("item existence check failed: %w", err)
	}
	if exists {
		return nil
	}
	return c.ImportItemFromURL(ctx, libraryTarget, itemName, artifactURL)
}

// DeployItem deploys an OVF item from content library.
func (c *Client) DeployItem(ctx context.Context, opt DeployOptions) error {
	if strings.TrimSpace(opt.Datacenter) == "" {
		return fmt.Errorf("datacenter is required")
	}
	if strings.TrimSpace(opt.Datastore) == "" {
		return fmt.Errorf("datastore is required")
	}
	if strings.TrimSpace(opt.ItemPath) == "" {
		return fmt.Errorf("item path is required")
	}
	if strings.TrimSpace(opt.VMName) == "" {
		return fmt.Errorf("vm name is required")
	}
	args := []string{"library.deploy", "-dc", opt.Datacenter, "-ds", opt.Datastore}
	if strings.TrimSpace(opt.OptionsPath) != "" {
		args = append(args, "-options", opt.OptionsPath)
	}
	if strings.TrimSpace(opt.Folder) != "" {
		args = append(args, "-folder", opt.Folder)
	}
	if strings.TrimSpace(opt.ResourcePool) != "" {
		args = append(args, "-pool", opt.ResourcePool)
	}
	args = append(args, opt.ItemPath, opt.VMName)
	if _, err := c.runner.Run(ctx, args...); err != nil {
		return fmt.Errorf("library.deploy failed: %w", err)
	}
	return nil
}

func parseLibraryID(raw []byte) (string, error) {
	trimmed := strings.TrimSpace(string(raw))
	if trimmed == "" || trimmed == "null" || trimmed == "[]" {
		return "", fmt.Errorf("matches 0 items")
	}
	var obj libraryInfoJSON
	if err := json.Unmarshal([]byte(trimmed), &obj); err == nil {
		id := strings.TrimSpace(obj.Library.ID)
		if id != "" {
			return id, nil
		}
	}
	var arr []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal([]byte(trimmed), &arr); err == nil {
		if len(arr) == 1 && strings.TrimSpace(arr[0].ID) != "" {
			return strings.TrimSpace(arr[0].ID), nil
		}
		if len(arr) > 1 {
			return "", fmt.Errorf("matches %d items", len(arr))
		}
	}
	return "", fmt.Errorf("matches 0 items")
}

func parseInfoPresence(raw []byte) bool {
	trimmed := strings.TrimSpace(string(raw))
	if trimmed == "" || trimmed == "null" || trimmed == "[]" {
		return false
	}
	var obj map[string]any
	if err := json.Unmarshal([]byte(trimmed), &obj); err == nil && len(obj) > 0 {
		return true
	}
	var arr []map[string]any
	if err := json.Unmarshal([]byte(trimmed), &arr); err == nil && len(arr) > 0 {
		return true
	}
	return false
}

func isNoMatch(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "matches 0 items")
}

func isAlreadyExists(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "already_exists") || strings.Contains(msg, "duplicate_item_name_unsupported_in_library")
}

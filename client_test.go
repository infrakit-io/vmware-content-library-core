package contentlibrary

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
)

type fakeRunner struct {
	mu       sync.Mutex
	calls    []string
	response map[string]fakeResp
}

type fakeResp struct {
	out []byte
	err error
}

func (f *fakeRunner) Run(_ context.Context, args ...string) ([]byte, error) {
	cmd := strings.Join(args, " ")
	f.mu.Lock()
	f.calls = append(f.calls, cmd)
	resp, ok := f.response[cmd]
	f.mu.Unlock()
	if !ok {
		return nil, fmt.Errorf("unexpected call: %s", cmd)
	}
	return resp.out, resp.err
}

func TestParseLibraryID_Object(t *testing.T) {
	id, err := parseLibraryID([]byte(`{"Library":{"ID":"abc-123","Name":"x"}}`))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if id != "abc-123" {
		t.Fatalf("id = %q", id)
	}
}

func TestParseLibraryID_Array(t *testing.T) {
	id, err := parseLibraryID([]byte(`[{"id":"lib-id"}]`))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if id != "lib-id" {
		t.Fatalf("id = %q", id)
	}
}

func TestParseLibraryID_NotFound(t *testing.T) {
	_, err := parseLibraryID([]byte(`null`))
	if err == nil || !strings.Contains(err.Error(), "matches 0 items") {
		t.Fatalf("unexpected err: %v", err)
	}
}

func TestEnsureItemFromURL_SkipsWhenExists(t *testing.T) {
	r := &fakeRunner{response: map[string]fakeResp{
		"library.info -json lib/item": {out: []byte(`{"name":"item"}`)},
	}}
	c := NewClient(r)
	if err := c.EnsureItemFromURL(context.Background(), "lib", "item", "https://example.invalid/item.ova"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(r.calls) != 1 || r.calls[0] != "library.info -json lib/item" {
		t.Fatalf("unexpected calls: %#v", r.calls)
	}
}

func TestEnsureItemFromURL_ImportsWhenMissing(t *testing.T) {
	r := &fakeRunner{response: map[string]fakeResp{
		"library.info -json lib/item":                                  {out: []byte(`null`)},
		"library.import -pull -n item lib https://example.invalid/ova": {},
	}}
	c := NewClient(r)
	if err := c.EnsureItemFromURL(context.Background(), "lib", "item", "https://example.invalid/ova"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestImportItemFromURL_Fallback(t *testing.T) {
	r := &fakeRunner{response: map[string]fakeResp{
		"library.import -pull -n item lib https://example.invalid/ova": {err: errors.New("pull failed")},
		"library.rm lib/item": {},
		"library.import -n item lib https://example.invalid/ova": {},
	}}
	c := NewClient(r)
	if err := c.ImportItemFromURL(context.Background(), "lib", "item", "https://example.invalid/ova"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestEnsureLibrary_CreateWhenMissing(t *testing.T) {
	r := &fakeRunner{response: map[string]fakeResp{
		"library.info -json my-lib": {err: errors.New("govc: matches 0 items")},
		"library.create my-lib":     {},
	}}
	c := NewClient(r)
	r.response["library.info -json my-lib"] = fakeResp{out: []byte(`{"Library":{"ID":"lib-1"}}`)}
	ref, err := c.EnsureLibrary(context.Background(), "my-lib")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ref.ID != "lib-1" || ref.Target != "lib-1" {
		t.Fatalf("unexpected ref: %#v", ref)
	}
}

package main

import (
	"encoding/json"
	"os"
	"strings"
)

type htmlStructure struct {
	Name  string            `json:"name"`
	Group string            `json:"group"`
	Note  string            `json:"note"`
	Tags  []string          `json:"tags"`
	Skip  map[string]string `json:"skip,omitempty"`
}

type htmlWorkload struct {
	Name  string `json:"name"`
	Group string `json:"group"`
	Mode  string `json:"mode"`
	Light bool   `json:"light"`
	Note  string `json:"note"`
	Base  string `json:"baseline"`
}

type htmlFile struct {
	Env       Env      `json:"env"`
	UpdatedAt string   `json:"updated_at"`
	Rows      []Row    `json:"rows"`
	Warnings  []string `json:"warnings"`
}

type htmlData struct {
	Suite struct {
		Name       string          `json:"name"`
		Title      string          `json:"title"`
		Blurb      string          `json:"blurb"`
		SizeLabel  string          `json:"size_label"`
		Facets     []Facet         `json:"facets"`
		Structures []htmlStructure `json:"structures"`
		Workloads  []htmlWorkload  `json:"workloads"`
	} `json:"suite"`
	Files       []htmlFile `json:"files"`
	GeneratedAt string     `json:"generated_at"`
}

func writeHTML(s *Suite, files []*File, path string) error {
	var d htmlData
	d.Suite.Name, d.Suite.Title, d.Suite.Blurb = s.Name, s.Title, s.Blurb
	d.Suite.SizeLabel = s.sizeLabel()
	d.Suite.Facets = s.Facets
	for _, st := range s.Structures {
		d.Suite.Structures = append(d.Suite.Structures, htmlStructure{st.Name, st.Group, st.Note, st.Tags, st.Skip})
	}
	for _, w := range s.Workloads {
		d.Suite.Workloads = append(d.Suite.Workloads, htmlWorkload{w.Name, w.Group, w.mode(), w.Light, w.Note, w.Baseline})
	}
	for _, f := range files {
		hf := htmlFile{Env: f.Env, UpdatedAt: f.UpdatedAt}
		for _, r := range f.Rows {
			hf.Rows = append(hf.Rows, r)
		}
		w := f.Warn(30)
		if len(w.MixedGno) > 1 {
			hf.Warnings = append(hf.Warnings, "Measured against more than one gno revision: "+strings.Join(w.MixedGno, ", "))
		}
		if len(w.Stale) > 0 {
			hf.Warnings = append(hf.Warnings, itoa(len(w.Stale))+" row(s) are over 30 days old")
		}
		if len(w.Unstable) > 0 {
			hf.Warnings = append(hf.Warnings, itoa(len(w.Unstable))+" row(s) did not reproduce across repeats")
		}
		if len(w.Failed) > 0 {
			hf.Warnings = append(hf.Warnings, itoa(len(w.Failed))+" row(s) failed")
		}
		d.Files = append(d.Files, hf)
	}
	d.GeneratedAt = nowUTC()

	b, err := json.Marshal(d)
	if err != nil {
		return err
	}
	page := strings.Replace(htmlPage, "/*DATA*/", string(b), 1)
	return os.WriteFile(path, []byte(page), 0o644)
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var d []byte
	for n > 0 {
		d = append([]byte{byte('0' + n%10)}, d...)
		n /= 10
	}
	return string(d)
}

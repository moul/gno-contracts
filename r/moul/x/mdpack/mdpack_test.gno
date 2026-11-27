package mdpack

import (
	"strings"
	"testing"
)

func TestRender(t *testing.T) {
	cases := []struct {
		route string
		want  []string
	}{
		{"", []string{path + ":pixel.png", path + ":data.json", "mimetype=image/png", pixel, data}},
		{"pixel.png", []string{"# pixel.png", pixel}},
		{"data.json", []string{"# data.json", data}},
		{"<script>", []string{"File not found."}},
	}
	for _, tc := range cases {
		got := Render(tc.route)
		for _, want := range tc.want {
			if !strings.Contains(got, want) {
				t.Errorf("Render(%q) omitted %q", tc.route, want)
			}
		}
		if strings.Contains(got, "<script>") {
			t.Errorf("Render(%q) reflected the path", tc.route)
		}
	}
}

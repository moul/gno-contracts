package sapin

import (
	"testing"
)

func TestRender(t *testing.T) {
	tt := []struct {
		path string
		want string
	}{
		{"1", "```" + `
   *
  ***
 *****
*******
  |||
` + "```\n"},
		{"", "```" + `
         *
        ***
       *****
      *******
       *****
      *******
     *********
    ***********
   *************
     *********
    ***********
   *************
  ***************
 *****************
*******************
        |||
        |||
        |||
` + "```\n"},
	}

	for _, tc := range tt {
		name := tc.path
		t.Run(name, func(t *testing.T) {
			got := Render(tc.path)
			want := tc.want
			if got != want {
				t.Errorf("expected \n%s\n, got \n%s\n.", want, got)
			}
		})
	}
}

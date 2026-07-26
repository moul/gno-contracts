package piglatin

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestTranslateWord(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"pig", "igpay"},
		{"banana", "ananabay"},
		{"smile", "ilesmay"},
		{"string", "ingstray"},
		{"eat", "eatway"},
		{"apple", "appleway"},
		{"yellow", "ellowyay"},  // leading y = consonant
		{"myth", "ythmay"},      // internal y = vowel
		{"Hello", "Ellohay"},    // title-case preserved
		{"NASA", "ASANAY"},      // all caps preserved
	}
	for _, c := range cases {
		got := translateWord(c.in)
		uassert.Equal(t, c.want, got)
	}
}

func TestTranslateSentence(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"hello world", "ellohay orldway"},
		{"Hello, world!", "Ellohay, orldway!"},
		{"The quick brown fox", "Ethay uickqay ownbray oxfay"},
		{"", ""},
		{"   ", "   "}, // whitespace preserved, no words
	}
	for _, c := range cases {
		got := Translate(c.in)
		uassert.Equal(t, c.want, got)
	}
}

func TestSplitAffixes(t *testing.T) {
	lead, core, trail := splitAffixes("(Hello!)")
	uassert.Equal(t, "(", lead)
	uassert.Equal(t, "Hello", core)
	uassert.Equal(t, "!)", trail)

	lead, core, trail = splitAffixes("...")
	uassert.Equal(t, "...", lead)
	uassert.Equal(t, "", core)
	uassert.Equal(t, "", trail)
}

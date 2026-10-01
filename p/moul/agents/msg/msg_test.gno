package msg

import "testing"

func TestEncodeDecodeRoundTrip(t *testing.T) {
	tests := []struct {
		name string
		m    Msg
	}{
		{"plain", Msg{1, 100, "claude@hermey", "build", "note", "pr/12", "ci is green"}},
		{"empty optional fields", Msg{2, 0, "a", "t", "", "", "b"}},
		{"body holds the separator", Msg{3, 7, "a", "t", "k", "r", "3:abc:def"}},
		{"body holds a newline", Msg{4, 7, "a", "t", "k", "r", "line one\nline two"}},
		{"body holds an encoded message", Msg{5, 7, "a", "t", "k", "r", Msg{1, 1, "x", "y", "z", "w", "v"}.Encode()}},
		{"unicode body", Msg{6, 7, "a", "t", "k", "r", "héllo … 世界"}},
		{"max height", Msg{7, 9223372036854775807, "a", "t", "k", "r", "b"}},
	}
	for _, tt := range tests {
		got, ok := Decode(tt.m.Encode())
		if !ok {
			t.Errorf("%s: Decode reported failure", tt.name)
			continue
		}
		if got != tt.m {
			t.Errorf("%s: round trip changed the message", tt.name)
		}
	}
}

func TestDecodeRejects(t *testing.T) {
	tests := []struct {
		name string
		s    string
	}{
		{"empty, which is an unwritten ring slot", ""},
		{"not length-prefixed", "hello"},
		{"too few fields", "1:1" + "1:2"},
		{"length runs past the end", "99:short"},
		{"trailing bytes after the last field", Msg{1, 1, "a", "t", "k", "r", "b"}.Encode() + "x"},
		{"seq is not a number", "1:x1:00:00:00:00:01:b"},
		{"negative length", "-1:a"},
		{"no colon", "5abcde"},
	}
	for _, tt := range tests {
		if _, ok := Decode(tt.s); ok {
			t.Errorf("%s: Decode accepted it", tt.name)
		}
	}
}

func TestEncodeIsUnambiguous(t *testing.T) {
	// The reason for length prefixes: two different splits of the same bytes
	// must not encode to the same string.
	a := Msg{1, 1, "ab", "c", "k", "r", "b"}.Encode()
	b := Msg{1, 1, "a", "bc", "k", "r", "b"}.Encode()
	if a == b {
		t.Error("two distinct messages share an encoding")
	}
}

func TestValidate(t *testing.T) {
	long := func(n int) string {
		s := ""
		for i := 0; i < n; i++ {
			s += "x"
		}
		return s
	}
	ok := Msg{From: "a", Topic: "t", Body: "b"}

	tests := []struct {
		name string
		m    Msg
		want string
	}{
		{"valid", ok, ""},
		{"valid with dots and digits", Msg{From: "a", Topic: "build.v2-0", Body: "b"}, ""},
		{"empty from", Msg{Topic: "t", Body: "b"}, "empty from"},
		{"from too long", Msg{From: long(MaxFrom + 1), Topic: "t", Body: "b"}, "from too long"},
		{"empty topic", Msg{From: "a", Body: "b"}, "empty topic"},
		{"topic too long", Msg{From: "a", Topic: long(MaxTopic + 1), Body: "b"}, "topic too long"},
		{"uppercase topic", Msg{From: "a", Topic: "Build", Body: "b"}, "topic must be lowercase a-z, 0-9, dash or dot"},
		{"topic with a slash", Msg{From: "a", Topic: "a/b", Body: "b"}, "topic must be lowercase a-z, 0-9, dash or dot"},
		{"topic with a space", Msg{From: "a", Topic: "a b", Body: "b"}, "topic must be lowercase a-z, 0-9, dash or dot"},
		{"kind too long", Msg{From: "a", Topic: "t", Kind: long(MaxKind + 1), Body: "b"}, "kind too long"},
		{"ref too long", Msg{From: "a", Topic: "t", Ref: long(MaxRef + 1), Body: "b"}, "ref too long"},
		{"empty body", Msg{From: "a", Topic: "t"}, "empty body"},
		{"body too long", Msg{From: "a", Topic: "t", Body: long(MaxBody + 1)}, "body too long"},
		{"body at the limit", Msg{From: "a", Topic: "t", Body: long(MaxBody)}, ""},
	}
	for _, tt := range tests {
		if got := tt.m.Validate(); got != tt.want {
			t.Errorf("%s: got %q, want %q", tt.name, got, tt.want)
		}
	}
}

func TestFrameUnframe(t *testing.T) {
	tests := []struct {
		name string
		v    string
		tail string
	}{
		{"plain", "g1abc", ""},
		{"empty value", "", "rest"},
		{"value holds a colon", "a:b", "rest"},
		// The bug this pair exists to prevent: scanning backwards for the
		// length prefix cannot tell a body's trailing digits from it.
		{"preceded by a message ending in digits", "g1abc", ""},
	}
	for _, tt := range tests {
		got, rest, ok := Unframe(Frame(tt.v) + tt.tail)
		if !ok || got != tt.v || rest != tt.tail {
			t.Errorf("%s: got (%q, %q, %v), want (%q, %q, true)", tt.name, got, rest, ok, tt.v, tt.tail)
		}
	}
}

func TestFrameSurvivesABodyEndingInDigits(t *testing.T) {
	// A relay frames the author and concatenates. Decoding must recover both
	// even when the message body ends in the digits a backwards scan would
	// mistake for the author's length prefix.
	m := Msg{1, 1, "a", "t", "k", "r", "ends in 40"}
	addr := "g1manfred47kzduec920z88wfr64ylksmdcedlf5"
	author, rest, ok := Unframe(Frame(addr) + m.Encode())
	if !ok || author != addr {
		t.Fatalf("author not recovered: got %q, ok=%v", author, ok)
	}
	got, ok := Decode(rest)
	if !ok || got != m {
		t.Errorf("message not recovered after the framed author")
	}
}

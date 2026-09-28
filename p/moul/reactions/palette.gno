package reactions

// The palette: the closed set of reactions, and the only moderation policy
// this package has.
//
// It is closed on purpose. A free-text reaction is a comment, a comment needs
// moderation, and moderation is the thing worth not building. Six is enough to
// say something and few enough to fit on one line on a phone.
//
// Every glyph here is a SINGLE codepoint with no variation selector (no
// U+FE0F) and no zero-width joiner. That is a constraint, not a coincidence:
// these strings pass through a markdown escaper that strips zero-width and
// bidi characters, and a glyph that needs U+FE0F to render would come out the
// other side as its bare monochrome form. ❤️ is the obvious casualty, which is
// why "heart" is 💜 (U+1F49C), a codepoint that is a colour emoji on its own.
const (
	// KeyUp is the default, first in the strip.
	KeyUp = "up"
	// KeyHeart is affection rather than agreement.
	KeyHeart = "heart"
	// KeyFire is "this is good".
	KeyFire = "fire"
	// KeyParty is a congratulation.
	KeyParty = "party"
	// KeyRocket is "ship it".
	KeyRocket = "rocket"
	// KeyEyes is "I am watching this", the only one that is not praise.
	KeyEyes = "eyes"
)

// order is the display order of the palette, which is also the order the
// strip renders in. A slice and not a map range: gno map iteration order is
// unspecified, and a Render that reshuffles between identical calls is a
// consensus bug.
var order = []string{KeyUp, KeyHeart, KeyFire, KeyParty, KeyRocket, KeyEyes}

// palette maps a key to its glyph. Written as \U escapes rather than literal
// emoji so that the source says exactly which codepoint it means and a review
// diff cannot hide a lookalike.
var palette = map[string]string{
	KeyUp:     "\U0001F44D", // 👍
	KeyHeart:  "\U0001F49C", // 💜
	KeyFire:   "\U0001F525", // 🔥
	KeyParty:  "\U0001F389", // 🎉
	KeyRocket: "\U0001F680", // 🚀
	KeyEyes:   "\U0001F440", // 👀
}

// Keys returns the palette keys in display order. The returned slice is a copy,
// so a caller cannot reorder the palette for everyone else.
func Keys() []string {
	out := make([]string, len(order))
	copy(out, order)
	return out
}

// Valid reports whether key names a reaction in the palette.
func Valid(key string) bool {
	_, ok := palette[key]
	return ok
}

// Emoji returns the glyph for a palette key, or "" when the key is not one.
func Emoji(key string) string { return palette[key] }

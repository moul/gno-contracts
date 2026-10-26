// Package cron parses the classic five-field cron expression and answers the
// only question a schedule exists to answer: when does it next fire.
//
// The grammar is the one every crontab uses, in the order minute, hour,
// day-of-month, month, day-of-week:
//
//	*/15 9-17 * * mon-fri
//	│    │    │ │ │
//	│    │    │ │ └── day of week, 0-7 or sun..sat (0 and 7 are both Sunday)
//	│    │    │ └──── month, 1-12 or jan..dec
//	│    │    └────── day of month, 1-31
//	│    └─────────── hour, 0-23
//	└──────────────── minute, 0-59
//
// Each field is a comma-separated list whose items are a value, a range, a
// star, or any of those followed by a step: 5, 5-30, *, */15, 5-30/5, 5/20.
// The seven @macros are accepted too (@hourly, @daily, @weekly, @monthly,
// @yearly, @annually, @midnight).
//
// A Schedule is immutable once parsed and holds no state, so it is safe to
// build one at package scope and share it. Everything is computed in UTC: a
// block timestamp has no local zone, and a schedule whose answer depended on
// one would not be the same schedule on every validating node.
package cron

import (
	"errors"
	"strconv"
	"strings"
	"time"
)

// horizonYears bounds the search in Next. A cron expression can be perfectly
// well formed and still never fire (February the 30th), so the walk needs a
// stop condition that is not "a match eventually appears". Four years clears
// the longest real gap, the leap day, with a year to spare.
const horizonYears = 5

// Schedule is a parsed cron expression.
type Schedule struct {
	expr string

	minute [60]bool
	hour   [24]bool
	dom    [32]bool // 1..31
	month  [13]bool // 1..12
	dow    [7]bool  // 0..6, Sunday is 0

	// Whether each day field was narrowed from "*". The pair decides how the
	// two are combined; see matchDay.
	domRestricted bool
	dowRestricted bool
}

var macros = map[string]string{
	"@yearly":   "0 0 1 1 *",
	"@annually": "0 0 1 1 *",
	"@monthly":  "0 0 1 * *",
	"@weekly":   "0 0 * * 0",
	"@daily":    "0 0 * * *",
	"@midnight": "0 0 * * *",
	"@hourly":   "0 * * * *",
}

var monthNames = map[string]int{
	"jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
	"jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}

var dayNames = map[string]int{
	"sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6,
}

// Parse compiles a cron expression.
//
// It validates the grammar and the ranges, and nothing else: an expression
// that is well formed but can never fire parses successfully, because only
// Next is in a position to discover that.
func Parse(expr string) (*Schedule, error) {
	raw := strings.TrimSpace(expr)
	if raw == "" {
		return nil, errors.New("cron: empty expression")
	}

	spec := raw
	if strings.HasPrefix(spec, "@") {
		expanded, ok := macros[strings.ToLower(spec)]
		if !ok {
			return nil, errors.New("cron: unknown macro " + strconv.Quote(raw))
		}
		spec = expanded
	}

	fields := strings.Fields(spec)
	if len(fields) != 5 {
		return nil, errors.New("cron: want 5 fields, got " + strconv.Itoa(len(fields)) +
			" in " + strconv.Quote(raw))
	}

	s := &Schedule{expr: raw}

	minute, err := parseField(fields[0], 0, 59, nil)
	if err != nil {
		return nil, fieldError("minute", fields[0], err)
	}
	copy(s.minute[:], minute)

	hour, err := parseField(fields[1], 0, 23, nil)
	if err != nil {
		return nil, fieldError("hour", fields[1], err)
	}
	copy(s.hour[:], hour)

	dom, err := parseField(fields[2], 1, 31, nil)
	if err != nil {
		return nil, fieldError("day of month", fields[2], err)
	}
	copy(s.dom[:], dom)
	s.domRestricted = fields[2] != "*"

	month, err := parseField(fields[3], 1, 12, monthNames)
	if err != nil {
		return nil, fieldError("month", fields[3], err)
	}
	copy(s.month[:], month)

	// Day of week is parsed over 0..7 so that 7 and 5-7 stay legal, then
	// folded: Sunday has two spellings and one slot.
	dow, err := parseField(fields[4], 0, 7, dayNames)
	if err != nil {
		return nil, fieldError("day of week", fields[4], err)
	}
	if dow[7] {
		dow[0] = true
	}
	copy(s.dow[:], dow[:7])
	s.dowRestricted = fields[4] != "*"

	return s, nil
}

// MustParse is Parse for an expression written by the programmer rather than
// supplied by a caller. It panics instead of returning an error, so a constant
// schedule can be a package-level variable.
func MustParse(expr string) *Schedule {
	s, err := Parse(expr)
	if err != nil {
		panic(err)
	}
	return s
}

// Expr returns the expression this schedule was parsed from, unmodified. A
// macro is reported as the macro, not as its expansion.
func (s *Schedule) Expr() string { return s.expr }

// Matches reports whether the schedule fires during the minute containing t.
// Seconds and smaller are ignored: cron has no sub-minute resolution.
func (s *Schedule) Matches(t time.Time) bool {
	u := t.UTC()
	return s.month[int(u.Month())] &&
		s.matchDay(u) &&
		s.hour[u.Hour()] &&
		s.minute[u.Minute()]
}

// Next returns the first instant strictly after `after` at which the schedule
// fires, and whether there is one.
//
// The second return value is not decoration. "0 0 30 2 *" is a legal
// expression with no instant behind it, and a caller that assumed a match
// would scan forever.
func (s *Schedule) Next(after time.Time) (time.Time, bool) {
	// Strictly after, and aligned to the minute: a schedule handed its own
	// firing time must answer with the following one, not with itself.
	t := after.UTC().Truncate(time.Minute).Add(time.Minute)
	limit := t.Year() + horizonYears

	for t.Year() <= limit {
		switch {
		case !s.month[int(t.Month())]:
			// Skipping to the first of the next month relies on time.Date
			// normalising month 13 into January of the following year.
			t = time.Date(t.Year(), t.Month()+1, 1, 0, 0, 0, 0, time.UTC)
		case !s.matchDay(t):
			t = time.Date(t.Year(), t.Month(), t.Day()+1, 0, 0, 0, 0, time.UTC)
		case !s.hour[t.Hour()]:
			t = time.Date(t.Year(), t.Month(), t.Day(), t.Hour()+1, 0, 0, 0, time.UTC)
		case !s.minute[t.Minute()]:
			t = t.Add(time.Minute)
		default:
			return t, true
		}
	}
	return time.Time{}, false
}

// NextN returns the next n firing times, in order. It returns fewer, possibly
// none, when the schedule runs out before n are found.
func (s *Schedule) NextN(after time.Time, n int) []time.Time {
	if n <= 0 {
		return nil
	}
	out := make([]time.Time, 0, n)
	t := after
	for i := 0; i < n; i++ {
		next, ok := s.Next(t)
		if !ok {
			break
		}
		out = append(out, next)
		t = next
	}
	return out
}

// matchDay combines the two day fields.
//
// This is the rule the whole package is written for, and it is the one every
// reimplementation gets wrong. When BOTH day fields are narrowed the match is
// their union, not their intersection: "0 0 13 * 5" is the 13th of the month
// OR any Friday, which is why a Friday the 13th crontab is written that way
// and still fires on ordinary Fridays. When only one is narrowed the other
// matches everything, so the union and the intersection coincide and there is
// nothing to decide.
func (s *Schedule) matchDay(t time.Time) bool {
	dom := s.dom[t.Day()]
	dow := s.dow[int(t.Weekday())]
	switch {
	case s.domRestricted && s.dowRestricted:
		return dom || dow
	case s.domRestricted:
		return dom
	case s.dowRestricted:
		return dow
	default:
		return true
	}
}

// parseField expands one comma-separated field into a bitmap of size max+1.
func parseField(field string, min, max int, names map[string]int) ([]bool, error) {
	bits := make([]bool, max+1)
	for _, part := range strings.Split(field, ",") {
		if part == "" {
			return nil, errors.New("empty list item")
		}

		rangePart := part
		step := 1
		if i := strings.Index(part, "/"); i >= 0 {
			rangePart = part[:i]
			n, err := strconv.Atoi(part[i+1:])
			if err != nil {
				return nil, errors.New("step is not a number: " + strconv.Quote(part[i+1:]))
			}
			if n < 1 {
				return nil, errors.New("step must be at least 1, got " + strconv.Itoa(n))
			}
			step = n
		}

		lo, hi, err := parseRange(rangePart, min, max, names, step)
		if err != nil {
			return nil, err
		}
		for v := lo; v <= hi; v += step {
			bits[v] = true
		}
	}
	return bits, nil
}

// parseRange resolves the pre-step half of a list item into inclusive bounds.
func parseRange(s string, min, max int, names map[string]int, step int) (int, int, error) {
	if s == "*" {
		return min, max, nil
	}
	if i := strings.Index(s, "-"); i > 0 {
		lo, err := parseValue(s[:i], min, max, names)
		if err != nil {
			return 0, 0, err
		}
		hi, err := parseValue(s[i+1:], min, max, names)
		if err != nil {
			return 0, 0, err
		}
		if lo > hi {
			return 0, 0, errors.New("range runs backwards: " + strconv.Quote(s))
		}
		return lo, hi, nil
	}
	v, err := parseValue(s, min, max, names)
	if err != nil {
		return 0, 0, err
	}
	if step > 1 {
		// "5/20" is shorthand for "5-max/20": a bare value with a step means
		// start here and keep going, not fire once.
		return v, max, nil
	}
	return v, v, nil
}

// parseValue resolves a single number or three-letter name.
func parseValue(s string, min, max int, names map[string]int) (int, error) {
	if names != nil {
		if v, ok := names[strings.ToLower(s)]; ok {
			return v, nil
		}
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return 0, errors.New("not a number or a known name: " + strconv.Quote(s))
	}
	if v < min || v > max {
		return 0, errors.New("out of range " + strconv.Itoa(min) + "-" + strconv.Itoa(max) +
			": " + strconv.Itoa(v))
	}
	return v, nil
}

// fieldError names the field a parse failure came from. A bare "out of range"
// is useless when five fields all accept numbers.
func fieldError(name, field string, err error) error {
	return errors.New("cron: " + name + " field " + strconv.Quote(field) + ": " + err.Error())
}

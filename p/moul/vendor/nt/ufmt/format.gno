package ufmt

import (
	"strconv"
	"unicode/utf8"
)

// This file is the low level: padding, integers, floats, strings. It is a port
// of format.go in Go's fmt, kept close enough to read side by side.

const (
	ldigits = "0123456789abcdefx"
	udigits = "0123456789ABCDEFX"
)

// clearFlags resets everything a verb's specifier sets.
func (p *printer) clearFlags() {
	p.plus, p.minus, p.sharp, p.space, p.zero = false, false, false, false, false
	p.plusV, p.sharpV = false, false
	p.wid, p.prec = 0, 0
	p.widPresent, p.precPresent = false, false
}

// writePadding writes n pad bytes: zeros when the 0 flag is set, else spaces.
func (p *printer) writePadding(n int) {
	if n <= 0 {
		return
	}
	c := byte(' ')
	if p.zero {
		c = '0'
	}
	for i := 0; i < n; i++ {
		p.buf = append(p.buf, c)
	}
}

// pad writes b, padded to the width in runes, on the side the - flag says.
func (p *printer) pad(b []byte) {
	if !p.widPresent || p.wid == 0 {
		p.buf = append(p.buf, b...)
		return
	}
	width := p.wid - utf8.RuneCount(b)
	if !p.minus {
		p.writePadding(width)
		p.buf = append(p.buf, b...)
	} else {
		p.buf = append(p.buf, b...)
		p.writePadding(width)
	}
}

// padString is pad for a string.
func (p *printer) padString(s string) {
	if !p.widPresent || p.wid == 0 {
		p.buf = append(p.buf, s...)
		return
	}
	width := p.wid - utf8.RuneCountInString(s)
	if !p.minus {
		p.writePadding(width)
		p.buf = append(p.buf, s...)
	} else {
		p.buf = append(p.buf, s...)
		p.writePadding(width)
	}
}

// padNoZero pads with spaces whatever the 0 flag says.
func (p *printer) padNoZero(b []byte) {
	oldZero := p.zero
	p.zero = false
	p.pad(b)
	p.zero = oldZero
}

func (p *printer) fmtBoolean(v bool) {
	if v {
		p.padString("true")
	} else {
		p.padString("false")
	}
}

// fmtInteger formats u, the magnitude, in base, with a '-' when negative.
func (p *printer) fmtInteger(u uint64, negative bool, base int, verb rune, digits string) {
	// Fast path: no flags, width or precision, lowercase digits.
	if !p.widPresent && !p.precPresent && !p.plus && !p.space && !p.sharp &&
		verb != 'O' && (base != 16 || digits[10] == 'a') {
		if negative {
			p.buf = append(p.buf, '-')
		}
		p.buf = strconv.AppendUint(p.buf, u, base)
		return
	}

	prec := 0
	if p.precPresent {
		prec = p.prec
		// %.0d of zero prints nothing but its padding.
		if prec == 0 && u == 0 {
			oldZero := p.zero
			p.zero = false
			p.writePadding(p.wid)
			p.zero = oldZero
			return
		}
	} else if p.zero && !p.minus && p.widPresent {
		// Zero padding is a precision in disguise, minus room for the sign.
		prec = p.wid
		if negative || p.plus || p.space {
			prec--
		}
	}

	size := 68 // 64 binary digits, a sign and a 0b/0x/0o prefix
	if prec+4 > size {
		size = prec + 4
	}
	buf := make([]byte, size)
	i := size

	switch base {
	case 10:
		for u >= 10 {
			i--
			next := u / 10
			buf[i] = byte('0' + u - next*10)
			u = next
		}
	case 16:
		for u >= 16 {
			i--
			buf[i] = digits[u&0xF]
			u >>= 4
		}
	case 8:
		for u >= 8 {
			i--
			buf[i] = byte('0' + u&7)
			u >>= 3
		}
	case 2:
		for u >= 2 {
			i--
			buf[i] = byte('0' + u&1)
			u >>= 1
		}
	}
	i--
	buf[i] = digits[u]
	for i > 0 && prec > size-i {
		i--
		buf[i] = '0'
	}

	if p.sharp {
		switch base {
		case 2:
			i--
			buf[i] = 'b'
			i--
			buf[i] = '0'
		case 8:
			if buf[i] != '0' {
				i--
				buf[i] = '0'
			}
		case 16:
			i--
			buf[i] = digits[16]
			i--
			buf[i] = '0'
		}
	}
	if verb == 'O' {
		i--
		buf[i] = 'o'
		i--
		buf[i] = '0'
	}

	if negative {
		i--
		buf[i] = '-'
	} else if p.plus {
		i--
		buf[i] = '+'
	} else if p.space {
		i--
		buf[i] = ' '
	}

	// The zeros, if any, are already in buf: pad the rest with spaces.
	p.padNoZero(buf[i:])
}

// fmtUnicode formats u as "U+0078", or "U+0078 'x'" with the # flag.
func (p *printer) fmtUnicode(u uint64) {
	prec := 4
	if p.precPresent && p.prec > 4 {
		prec = p.prec
	}
	hex := strconv.FormatUint(u, 16)
	b := []byte("U+")
	for n := len(hex); n < prec; n++ {
		b = append(b, '0')
	}
	for i := 0; i < len(hex); i++ {
		c := hex[i]
		if c >= 'a' {
			c -= 'a' - 'A'
		}
		b = append(b, c)
	}
	if p.sharp && u <= utf8.MaxRune && strconv.IsPrint(rune(u)) {
		b = append(b, ' ', '\'')
		b = utf8.AppendRune(b, rune(u))
		b = append(b, '\'')
	}
	p.padNoZero(b)
}

// fmtC formats u as the rune it encodes, or U+FFFD when it encodes none.
func (p *printer) fmtC(u uint64) {
	r := rune(utf8.RuneError)
	if u <= utf8.MaxRune {
		r = rune(u)
	}
	p.pad(utf8.AppendRune(nil, r))
}

// fmtQc formats u as a single-quoted rune literal.
func (p *printer) fmtQc(u uint64) {
	r := rune(utf8.RuneError)
	if u <= utf8.MaxRune {
		r = rune(u)
	}
	if p.plus {
		p.pad(strconv.AppendQuoteRuneToASCII(nil, r))
	} else {
		p.pad(strconv.AppendQuoteRune(nil, r))
	}
}

// fmtFloat formats v, with prec digits (-1 for the shortest) unless the verb
// set its own precision.
func (p *printer) fmtFloat(v float64, size int, verb rune, prec int) {
	if p.precPresent {
		prec = p.prec
	}
	// num[0] is reserved for the sign.
	num := strconv.AppendFloat([]byte{0}, v, byte(verb), prec, size)
	if num[1] == '-' || num[1] == '+' {
		num = num[1:]
	} else {
		num[0] = '+'
	}
	if p.space && num[0] == '+' && !p.plus {
		num[0] = ' '
	}
	// Infinities and NaN do not look like numbers, so they are never zero padded.
	if num[1] == 'I' || num[1] == 'N' {
		oldZero := p.zero
		p.zero = false
		if num[1] == 'N' && !p.space && !p.plus {
			num = num[1:]
		}
		p.pad(num)
		p.zero = oldZero
		return
	}

	// The # flag keeps the decimal point, and for %g the trailing zeros.
	if p.sharp && verb != 'b' {
		digits := 0
		if verb == 'v' || verb == 'g' || verb == 'G' || verb == 'x' {
			digits = prec
			if digits == -1 {
				digits = 6
			}
		}
		var tail []byte
		hasDecimalPoint := false
		sawNonzeroDigit := false
		for i := 1; i < len(num); i++ {
			c := num[i]
			if c == '.' {
				hasDecimalPoint = true
				continue
			}
			if c == 'p' || c == 'P' || ((c == 'e' || c == 'E') && verb != 'x' && verb != 'X') {
				tail = append(tail, num[i:]...)
				num = num[:i]
				break
			}
			if c != '0' {
				sawNonzeroDigit = true
			}
			if sawNonzeroDigit {
				digits--
			}
		}
		if !hasDecimalPoint {
			// A lone leading zero counts as one significant digit.
			if len(num) == 2 && num[1] == '0' {
				digits--
			}
			num = append(num, '.')
		}
		for digits > 0 {
			num = append(num, '0')
			digits--
		}
		num = append(num, tail...)
	}

	if p.plus || num[0] != '+' {
		// Zero padding goes after the sign.
		if p.zero && !p.minus && p.widPresent && p.wid > len(num) {
			p.buf = append(p.buf, num[0])
			p.writePadding(p.wid - len(num))
			p.buf = append(p.buf, num[1:]...)
			return
		}
		p.pad(num)
		return
	}
	p.pad(num[1:])
}

// truncate cuts s to the precision, counted in runes.
func (p *printer) truncate(s string) string {
	if p.precPresent {
		n := p.prec
		for i := range s {
			n--
			if n < 0 {
				return s[:i]
			}
		}
	}
	return s
}

func (p *printer) fmtS(s string) {
	p.padString(p.truncate(s))
}

// fmtSx formats s as hex, two digits a byte. The space flag separates bytes,
// and # prefixes 0x, once or before each byte when spaced.
func (p *printer) fmtSx(s string, digits string) {
	length := len(s)
	if p.precPresent && p.prec < length {
		length = p.prec
	}
	width := 2 * length
	if width > 0 {
		if p.space {
			if p.sharp {
				width *= 2
			}
			width += length - 1
		} else if p.sharp {
			width += 2
		}
	} else {
		if p.widPresent {
			p.writePadding(p.wid)
		}
		return
	}
	if p.widPresent && p.wid > width && !p.minus {
		p.writePadding(p.wid - width)
	}
	if p.sharp {
		p.buf = append(p.buf, '0', digits[16])
	}
	for i := 0; i < length; i++ {
		if p.space && i > 0 {
			p.buf = append(p.buf, ' ')
			if p.sharp {
				p.buf = append(p.buf, '0', digits[16])
			}
		}
		c := s[i]
		p.buf = append(p.buf, digits[c>>4], digits[c&0xF])
	}
	if p.widPresent && p.wid > width && p.minus {
		p.writePadding(p.wid - width)
	}
}

// fmtQ formats s as a double-quoted Go string, backquoted with the # flag when
// it can be, and ASCII only with the + flag.
func (p *printer) fmtQ(s string) {
	s = p.truncate(s)
	if p.sharp && strconv.CanBackquote(s) {
		p.padString("`" + s + "`")
		return
	}
	if p.plus {
		p.pad(strconv.AppendQuoteToASCII(nil, s))
	} else {
		p.pad(strconv.AppendQuote(nil, s))
	}
}

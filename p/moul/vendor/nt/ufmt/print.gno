package ufmt

import (
	"sort"
	"unicode/utf8"
)

// This file is the high level: parsing the format, and choosing how each
// operand prints. It is a port of print.go in Go's fmt, minus reflect.

const (
	commaSpace  = ", "
	nilAngle    = "<nil>"
	nilParen    = "(nil)"
	unhandled   = "(unhandled)"
	percentBang = "%!"
	missing     = "(MISSING)"
	badIndex    = "(BADINDEX)"
	extra       = "%!(EXTRA "
	badWidth    = "%!(BADWIDTH)"
	badPrec     = "%!(BADPREC)"
	noVerb      = "%!(NOVERB)"
)

// printer holds the output and the state of the verb being printed.
type printer struct {
	buf []byte

	// The flags, width and precision of the current verb.
	plus, minus, sharp, space, zero bool
	plusV, sharpV                   bool // %+v and %#v
	wid, prec                       int
	widPresent, precPresent         bool

	arg        any  // the operand being printed, for error messages
	erroring   bool // printing an error message: do not call methods
	reordered  bool // an explicit index was used
	goodArgNum bool // the last index was valid
	wrapErrs   bool // Errorf: %w is allowed
	wrapped    []int
}

func newPrinter() *printer {
	return &printer{}
}

// Write implements State, so a Formatter can write.
func (p *printer) Write(b []byte) (int, error) {
	p.buf = append(p.buf, b...)
	return len(b), nil
}

// WriteString lets a Formatter write a string without a conversion.
func (p *printer) WriteString(s string) (int, error) {
	p.buf = append(p.buf, s...)
	return len(s), nil
}

// Width implements State.
func (p *printer) Width() (int, bool) { return p.wid, p.widPresent }

// Precision implements State.
func (p *printer) Precision() (int, bool) { return p.prec, p.precPresent }

// Flag implements State.
func (p *printer) Flag(c int) bool {
	switch c {
	case '-':
		return p.minus
	case '+':
		return p.plus || p.plusV
	case '#':
		return p.sharp || p.sharpV
	case ' ':
		return p.space
	case '0':
		return p.zero
	}
	return false
}

func (p *printer) writeString(s string) { p.buf = append(p.buf, s...) }
func (p *printer) writeByte(c byte)     { p.buf = append(p.buf, c) }
func (p *printer) writeRune(r rune)     { p.buf = utf8.AppendRune(p.buf, r) }

// doPrint is Sprint: %v, with a space between two operands neither of which is
// a string.
func (p *printer) doPrint(a []any) {
	prevString := false
	for argNum, arg := range a {
		_, isString := arg.(string)
		if argNum > 0 && !isString && !prevString {
			p.writeByte(' ')
		}
		p.printArg(arg, 'v')
		prevString = isString
	}
}

// doPrintln is Sprintln: %v, always a space between operands, then a newline.
func (p *printer) doPrintln(a []any) {
	for argNum, arg := range a {
		if argNum > 0 {
			p.writeByte(' ')
		}
		p.printArg(arg, 'v')
	}
	p.writeByte('\n')
}

// parsenum reads a decimal number at s[start:end].
func parsenum(s string, start, end int) (num int, isnum bool, newi int) {
	if start >= end {
		return 0, false, end
	}
	for newi = start; newi < end && '0' <= s[newi] && s[newi] <= '9'; newi++ {
		if num > 1e6 {
			return 0, false, end // absurdly large: refuse rather than allocate
		}
		num = num*10 + int(s[newi]-'0')
		isnum = true
	}
	return
}

// intFromArg reads a * width or precision from a[argNum].
func intFromArg(a []any, argNum int) (num int, isInt bool, newArgNum int) {
	newArgNum = argNum
	if argNum >= len(a) {
		return
	}
	isInt = true
	switch v := a[argNum].(type) {
	case int:
		num = v
	case int8:
		num = int(v)
	case int16:
		num = int(v)
	case int32:
		num = int(v)
	case int64:
		num = int(v)
	case uint:
		num = int(v)
	case uint8:
		num = int(v)
	case uint16:
		num = int(v)
	case uint32:
		num = int(v)
	case uint64:
		num = int(v)
	default:
		isInt = false
	}
	newArgNum = argNum + 1
	if num > 1e6 || num < -1e6 {
		num = 0
		isInt = false
	}
	return
}

// argNumber reads an explicit index, "[3]", at format[i:].
func (p *printer) argNumber(argNum int, format string, i int, numArgs int) (newArgNum, newi int, found bool) {
	if len(format) <= i || format[i] != '[' {
		return argNum, i, false
	}
	p.reordered = true
	for j := 1; j < len(format)-i; j++ {
		if format[i+j] == ']' {
			width, ok, newi := parsenum(format, i+1, i+j)
			if !ok || newi != i+j {
				p.goodArgNum = false
				return argNum, i + j + 1, true
			}
			index := width - 1
			if index >= 0 && index < numArgs {
				return index, i + j + 1, true
			}
			p.goodArgNum = false
			return argNum, i + j + 1, true
		}
	}
	p.goodArgNum = false
	return argNum, i + 1, false
}

// doPrintf is Sprintf.
func (p *printer) doPrintf(format string, a []any) {
	end := len(format)
	argNum := 0
	afterIndex := false // the previous item was an index like [3]
	p.reordered = false

	for i := 0; i < end; {
		p.goodArgNum = true
		lasti := i
		for i < end && format[i] != '%' {
			i++
		}
		if i > lasti {
			p.writeString(format[lasti:i])
		}
		if i >= end {
			break
		}
		i++ // skip '%'

		p.clearFlags()

		// Fast path: a bare lowercase verb, "%d" or "%s", is most of what any
		// realm prints, and skips the specifier parsing entirely.
		if i < end && 'a' <= format[i] && format[i] <= 'z' && argNum < len(a) {
			verb := rune(format[i])
			if verb == 'w' {
				p.wrapped = append(p.wrapped, argNum)
			}
			p.printArg(a[argNum], verb)
			argNum++
			i++
			continue
		}

	flags:
		for ; i < end; i++ {
			switch format[i] {
			case '#':
				p.sharp = true
			case '0':
				p.zero = !p.minus // zero padding only ever goes on the left
			case '+':
				p.plus = true
			case '-':
				p.minus = true
				p.zero = false
			case ' ':
				p.space = true
			default:
				break flags
			}
		}

		argNum, i, afterIndex = p.argNumber(argNum, format, i, len(a))

		// Width.
		if i < end && format[i] == '*' {
			i++
			p.wid, p.widPresent, argNum = intFromArg(a, argNum)
			if !p.widPresent {
				p.writeString(badWidth)
			}
			if p.wid < 0 {
				p.wid = -p.wid
				p.minus = true
				p.zero = false
			}
			afterIndex = false
		} else {
			p.wid, p.widPresent, i = parsenum(format, i, end)
			if afterIndex && p.widPresent { // "%[3]2d"
				p.goodArgNum = false
			}
		}

		// Precision.
		if i+1 < end && format[i] == '.' {
			i++
			if afterIndex { // "%[3].2d"
				p.goodArgNum = false
			}
			argNum, i, afterIndex = p.argNumber(argNum, format, i, len(a))
			if i < end && format[i] == '*' {
				i++
				p.prec, p.precPresent, argNum = intFromArg(a, argNum)
				if p.prec < 0 {
					p.prec = 0
					p.precPresent = false
				}
				if !p.precPresent {
					p.writeString(badPrec)
				}
				afterIndex = false
			} else {
				p.prec, p.precPresent, i = parsenum(format, i, end)
				if !p.precPresent {
					p.prec = 0
					p.precPresent = true
				}
			}
		}

		if !afterIndex {
			argNum, i, afterIndex = p.argNumber(argNum, format, i, len(a))
		}

		if i >= end {
			p.writeString(noVerb)
			break
		}

		verb, size := rune(format[i]), 1
		if verb >= utf8.RuneSelf {
			verb, size = utf8.DecodeRuneInString(format[i:])
		}
		i += size

		switch {
		case verb == '%': // takes no operand, ignores width and precision
			p.writeByte('%')
		case !p.goodArgNum:
			p.badArgNum(verb)
		case argNum >= len(a):
			p.missingArg(verb)
		default:
			if verb == 'w' {
				p.wrapped = append(p.wrapped, argNum)
			}
			if verb == 'v' || verb == 'w' {
				p.sharpV, p.sharp = p.sharp, false
				p.plusV, p.plus = p.plus, false
			}
			p.printArg(a[argNum], verb)
			argNum++
		}
	}

	// Report unused operands, unless an index made the count meaningless.
	if !p.reordered && argNum < len(a) {
		p.clearFlags()
		p.writeString(extra)
		for i, arg := range a[argNum:] {
			if i > 0 {
				p.writeString(commaSpace)
			}
			if arg == nil {
				p.writeString(nilAngle)
				continue
			}
			p.writeString(typeName(arg))
			p.writeByte('=')
			p.printArg(arg, 'v')
		}
		p.writeByte(')')
	}
}

func (p *printer) badArgNum(verb rune) {
	p.writeString(percentBang)
	p.writeRune(verb)
	p.writeString(badIndex)
}

func (p *printer) missingArg(verb rune) {
	p.writeString(percentBang)
	p.writeRune(verb)
	p.writeString(missing)
}

// badVerb writes "%!d(string=hi)": the verb, the operand's type and its value.
func (p *printer) badVerb(verb rune) {
	p.erroring = true
	p.writeString(percentBang)
	p.writeRune(verb)
	p.writeByte('(')
	switch {
	case p.arg == nil:
		p.writeString(nilAngle)
	default:
		if t := typeName(p.arg); t != "unknown" {
			p.writeString(t)
			p.writeByte('=')
			p.printArg(p.arg, 'v')
		} else {
			p.writeString("unhandled")
		}
	}
	p.writeByte(')')
	p.erroring = false
}

// printArg prints one operand.
func (p *printer) printArg(arg any, verb rune) {
	p.arg = arg

	if arg == nil {
		switch verb {
		case 'T', 'v':
			p.padString(nilAngle)
		default:
			p.badVerb(verb)
		}
		return
	}

	switch verb {
	case 'T':
		p.fmtS(typeName(arg))
		return
	case 'p':
		p.badVerb(verb)
		return
	}

	// The basic types first, exactly as Go: a named type never matches these,
	// so its methods are still found below.
	switch f := arg.(type) {
	case bool:
		p.fmtBool(f, verb)
	case float32:
		p.fmtFloatVerb(float64(f), 32, verb)
	case float64:
		p.fmtFloatVerb(f, 64, verb)
	case int:
		p.fmtSigned(int64(f), verb)
	case int8:
		p.fmtSigned(int64(f), verb)
	case int16:
		p.fmtSigned(int64(f), verb)
	case int32:
		p.fmtSigned(int64(f), verb)
	case int64:
		p.fmtSigned(f, verb)
	case uint:
		p.fmtUnsigned(uint64(f), verb)
	case uint8:
		p.fmtUnsigned(uint64(f), verb)
	case uint16:
		p.fmtUnsigned(uint64(f), verb)
	case uint32:
		p.fmtUnsigned(uint64(f), verb)
	case uint64:
		p.fmtUnsigned(f, verb)
	case string:
		p.fmtString(f, verb)
	case []byte:
		p.fmtBytes(f, verb)
	default:
		if !p.handleMethods(verb) {
			p.printComposite(arg, verb)
		}
	}
}

// handleMethods prints arg with its own Format, GoString, Error or String
// method, in Go's order, and reports whether it did.
func (p *printer) handleMethods(verb rune) (handled bool) {
	if p.erroring {
		return false
	}
	if verb == 'w' {
		// %w is for Errorf, and for an error.
		if _, ok := p.arg.(error); !ok || !p.wrapErrs {
			p.badVerb(verb)
			return true
		}
		verb = 'v'
	}

	if f, ok := p.arg.(Formatter); ok {
		handled = true // stays true if the method panics
		defer p.catchPanic(p.arg, verb, "Format")
		f.Format(p, verb)
		return
	}

	if p.sharpV {
		if g, ok := p.arg.(GoStringer); ok {
			handled = true
			defer p.catchPanic(p.arg, verb, "GoString")
			p.fmtS(g.GoString())
			return
		}
		return false
	}

	switch verb {
	case 'v', 's', 'x', 'X', 'q':
		switch v := p.arg.(type) {
		case error:
			handled = true
			defer p.catchPanic(p.arg, verb, "Error")
			p.fmtString(v.Error(), verb)
			return
		case Stringer:
			handled = true
			defer p.catchPanic(p.arg, verb, "String")
			p.fmtString(v.String(), verb)
			return
		}
	}
	return false
}

// catchPanic turns a panicking method into "%!v(PANIC=String method: msg)".
func (p *printer) catchPanic(arg any, verb rune, method string) {
	r := recover()
	if r == nil {
		return
	}
	if p.erroring {
		panic(r) // the method panicked again while printing its own panic
	}
	p.clearFlags()
	p.writeString(percentBang)
	p.writeRune(verb)
	p.writeString("(PANIC=")
	p.writeString(method)
	p.writeString(" method: ")
	p.erroring = true
	p.printArg(r, 'v')
	p.erroring = false
	p.writeByte(')')
}

func (p *printer) fmtBool(v bool, verb rune) {
	switch verb {
	case 't', 'v':
		p.fmtBoolean(v)
	default:
		p.badVerb(verb)
	}
}

// fmtSigned prints a signed integer. The magnitude of math.MinInt64 does not
// fit an int64, so it is computed without ever negating v itself.
func (p *printer) fmtSigned(v int64, verb rune) {
	if v >= 0 {
		p.fmtIntegerVerb(uint64(v), false, true, verb)
		return
	}
	mag := uint64(-(v + 1)) + 1
	p.fmtIntegerVerb(mag, true, true, verb)
}

func (p *printer) fmtUnsigned(u uint64, verb rune) {
	p.fmtIntegerVerb(u, false, false, verb)
}

func (p *printer) fmtIntegerVerb(u uint64, negative, isSigned bool, verb rune) {
	switch verb {
	case 'v':
		if p.sharpV && !isSigned {
			p.fmt0x64(u, true)
		} else {
			p.fmtInteger(u, negative, 10, verb, ldigits)
		}
	case 'd':
		p.fmtInteger(u, negative, 10, verb, ldigits)
	case 'b':
		p.fmtInteger(u, negative, 2, verb, ldigits)
	case 'o', 'O':
		p.fmtInteger(u, negative, 8, verb, ldigits)
	case 'x':
		p.fmtInteger(u, negative, 16, verb, ldigits)
	case 'X':
		p.fmtInteger(u, negative, 16, verb, udigits)
	case 'c', 'q', 'U':
		if negative {
			u = ^u + 1 // back to two's complement, as Go sees it: never a rune
		}
		switch verb {
		case 'c':
			p.fmtC(u)
		case 'q':
			p.fmtQc(u)
		default:
			p.fmtUnicode(u)
		}
	default:
		p.badVerb(verb)
	}
}

// fmt0x64 prints u in hex with a 0x prefix (leading0x) or without one.
func (p *printer) fmt0x64(u uint64, leading0x bool) {
	sharp := p.sharp
	p.sharp = leading0x
	p.fmtInteger(u, false, 16, 'v', ldigits)
	p.sharp = sharp
}

func (p *printer) fmtFloatVerb(v float64, size int, verb rune) {
	switch verb {
	case 'v':
		p.fmtFloat(v, size, 'g', -1)
	case 'b', 'g', 'G', 'x', 'X':
		p.fmtFloat(v, size, verb, -1)
	case 'f', 'e', 'E':
		p.fmtFloat(v, size, verb, 6)
	case 'F':
		p.fmtFloat(v, size, 'f', 6)
	default:
		p.badVerb(verb)
	}
}

func (p *printer) fmtString(v string, verb rune) {
	switch verb {
	case 'v':
		if p.sharpV {
			p.fmtQ(v)
		} else {
			p.fmtS(v)
		}
	case 's':
		p.fmtS(v)
	case 'x':
		p.fmtSx(v, ldigits)
	case 'X':
		p.fmtSx(v, udigits)
	case 'q':
		p.fmtQ(v)
	default:
		p.badVerb(verb)
	}
}

func (p *printer) fmtBytes(v []byte, verb rune) {
	switch verb {
	case 'v', 'd':
		if p.sharpV {
			p.writeString("[]byte")
			if v == nil {
				p.writeString(nilParen)
				return
			}
			p.writeByte('{')
			for i, c := range v {
				if i > 0 {
					p.writeString(commaSpace)
				}
				p.fmt0x64(uint64(c), true)
			}
			p.writeByte('}')
			return
		}
		p.writeByte('[')
		for i, c := range v {
			if i > 0 {
				p.writeByte(' ')
			}
			p.fmtInteger(uint64(c), false, 10, verb, ldigits)
		}
		p.writeByte(']')
	case 's':
		p.fmtS(string(v))
	case 'x':
		p.fmtSx(string(v), ldigits)
	case 'X':
		p.fmtSx(string(v), udigits)
	case 'q':
		p.fmtQ(string(v))
	default:
		// Every other verb applies to each byte, as for any slice.
		p.writeByte('[')
		for i, c := range v {
			if i > 0 {
				p.writeByte(' ')
			}
			p.fmtUnsigned(uint64(c), verb)
		}
		p.writeByte(']')
	}
}

// printComposite prints the slices and maps gno can see without reflect.
func (p *printer) printComposite(arg any, verb rune) {
	switch v := arg.(type) {
	case []any:
		p.printSlice("[]interface {}", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []string:
		p.printSlice("[]string", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []error:
		p.printSlice("[]error", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []bool:
		p.printSlice("[]bool", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []int:
		p.printSlice("[]int", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []int8:
		p.printSlice("[]int8", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []int16:
		p.printSlice("[]int16", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []int32:
		p.printSlice("[]int32", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []int64:
		p.printSlice("[]int64", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []uint:
		p.printSlice("[]uint", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []uint16:
		p.printSlice("[]uint16", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []uint32:
		p.printSlice("[]uint32", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []uint64:
		p.printSlice("[]uint64", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []float32:
		p.printSlice("[]float32", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case []float64:
		p.printSlice("[]float64", v == nil, len(v), func(i int) any { return v[i] }, verb)
	case map[string]string:
		keys := sortedKeys(len(v), func(add func(string)) {
			for k := range v {
				add(k)
			}
		})
		p.printMap("map[string]string", v == nil, keys, func(k string) any { return v[k] }, verb)
	case map[string]any:
		keys := sortedKeys(len(v), func(add func(string)) {
			for k := range v {
				add(k)
			}
		})
		p.printMap("map[string]interface {}", v == nil, keys, func(k string) any { return v[k] }, verb)
	case map[string]int:
		keys := sortedKeys(len(v), func(add func(string)) {
			for k := range v {
				add(k)
			}
		})
		p.printMap("map[string]int", v == nil, keys, func(k string) any { return v[k] }, verb)
	case map[string]bool:
		keys := sortedKeys(len(v), func(add func(string)) {
			for k := range v {
				add(k)
			}
		})
		p.printMap("map[string]bool", v == nil, keys, func(k string) any { return v[k] }, verb)
	default:
		if verb == 'v' {
			p.padString(unhandled)
		} else {
			p.badVerb(verb)
		}
	}
}

// printSlice prints "[a b]", or "[]T{a, b}" for %#v, each element with verb.
func (p *printer) printSlice(typ string, isNil bool, n int, at func(int) any, verb rune) {
	if p.sharpV {
		p.writeString(typ)
		if isNil {
			p.writeString(nilParen)
			return
		}
		p.writeByte('{')
		for i := 0; i < n; i++ {
			if i > 0 {
				p.writeString(commaSpace)
			}
			p.printElem(at(i), verb)
		}
		p.writeByte('}')
		return
	}
	p.writeByte('[')
	for i := 0; i < n; i++ {
		if i > 0 {
			p.writeByte(' ')
		}
		p.printElem(at(i), verb)
	}
	p.writeByte(']')
}

// printMap prints "map[a:1 b:2]", or "map[string]int{"a":1, "b":2}" for %#v,
// keys sorted as Go sorts them.
func (p *printer) printMap(typ string, isNil bool, keys []string, at func(string) any, verb rune) {
	if p.sharpV {
		p.writeString(typ)
		if isNil {
			p.writeString(nilParen)
			return
		}
		p.writeByte('{')
	} else {
		p.writeString("map[")
	}
	for i, k := range keys {
		if i > 0 {
			if p.sharpV {
				p.writeString(commaSpace)
			} else {
				p.writeByte(' ')
			}
		}
		p.printElem(k, verb)
		p.writeByte(':')
		p.printElem(at(k), verb)
	}
	if p.sharpV {
		p.writeByte('}')
	} else {
		p.writeByte(']')
	}
}

// printElem prints one element of a composite, keeping the outer operand for
// error messages. A nil element prints "<nil>" whatever the verb, as in Go.
func (p *printer) printElem(v any, verb rune) {
	outer := p.arg
	if v == nil {
		if p.sharpV {
			p.writeString("interface {}(nil)")
		} else {
			p.padString(nilAngle)
		}
	} else {
		p.printArg(v, verb)
	}
	p.arg = outer
}

func sortedKeys(n int, each func(add func(string))) []string {
	keys := make([]string, 0, n)
	each(func(k string) { keys = append(keys, k) })
	sort.Strings(keys)
	return keys
}

// typeName is %T for the types gno can name without reflect.
func typeName(v any) string {
	switch v.(type) {
	case bool:
		return "bool"
	case int:
		return "int"
	case int8:
		return "int8"
	case int16:
		return "int16"
	case int32:
		return "int32"
	case int64:
		return "int64"
	case uint:
		return "uint"
	case uint8:
		return "uint8"
	case uint16:
		return "uint16"
	case uint32:
		return "uint32"
	case uint64:
		return "uint64"
	case float32:
		return "float32"
	case float64:
		return "float64"
	case string:
		return "string"
	case []byte:
		return "[]uint8"
	case []any:
		return "[]interface {}"
	case []string:
		return "[]string"
	case []error:
		return "[]error"
	case []bool:
		return "[]bool"
	case []int:
		return "[]int"
	case []int8:
		return "[]int8"
	case []int16:
		return "[]int16"
	case []int32:
		return "[]int32"
	case []int64:
		return "[]int64"
	case []uint:
		return "[]uint"
	case []uint16:
		return "[]uint16"
	case []uint32:
		return "[]uint32"
	case []uint64:
		return "[]uint64"
	case []float32:
		return "[]float32"
	case []float64:
		return "[]float64"
	case map[string]string:
		return "map[string]string"
	case map[string]any:
		return "map[string]interface {}"
	case map[string]int:
		return "map[string]int"
	case map[string]bool:
		return "map[string]bool"
	}
	return "unknown"
}

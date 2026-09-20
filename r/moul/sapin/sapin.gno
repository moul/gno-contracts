package sapin

import "strings"

func Sapin(size int) string {
	if size < 1 {
		return ""
	}
	var b strings.Builder
	for floor := 0; floor < size; floor++ {
		for j := 0; j < floor+4; j++ {
			spaces := size*2 - (floor-1)*2 - j + size - 2
			bodies := j*2 + 1 + floor*4
			b.WriteString(strings.Repeat(" ", spaces))
			b.WriteString(strings.Repeat("*", bodies))
			b.WriteString("\n")
		}
	}

	for i := 0; i < size; i++ {
		spaces := (size-1)*3 + 2
		b.WriteString(strings.Repeat(" ", spaces))
		b.WriteString("|||\n")
	}
	return b.String()
}

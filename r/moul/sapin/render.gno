package sapin

import "strconv"

const defaultSize int = 3

func Render(path string) string {
	size := defaultSize

	if path != "" {
		var err error
		size, err = strconv.Atoi(path)
		if err != nil {
			panic(err)
		}
	}

	sapin := Sapin(size)
	output := "```\n" + sapin + "```\n"
	return output
}

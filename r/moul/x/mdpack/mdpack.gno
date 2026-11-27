package mdpack

const (
	pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
	data  = `{"foo": "bar"}`
	path  = "/r/moul/x/mdpack/v0"
)

// Render demonstrates the MDPack proposal and lets readers inspect its two files.
func Render(route string) string {
	switch route {
	case "":
		return "# MDPack example\n\n" +
			"Pack fences describe a file, its encoding and its media type. " +
			"Gnoweb displays these fences as Markdown code.\n\n" +
			"- [pixel.png (base64)](" + path + ":pixel.png)\n" +
			"- [data.json](" + path + ":data.json)\n\n" +
			"```pack,pixel.png?encoding=base64&mimetype=image/png --\n" + pixel + "\n```\n\n" +
			"```pack,data.json?embed=true --\n" + data + "\n```\n"
	case "pixel.png":
		return "# pixel.png\n\nBase64-encoded PNG.\n\n```text\n" + pixel + "\n```\n"
	case "data.json":
		return "# data.json\n\n```json\n" + data + "\n```\n"
	default:
		return "File not found. [View the example](" + path + ").\n"
	}
}

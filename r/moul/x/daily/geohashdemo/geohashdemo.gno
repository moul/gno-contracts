// Package geohashdemo is a small gnoweb demo of the
// [p/moul/x/daily/geohash](/p/moul/x/daily/geohash/v0) library: it shows a
// point encoded at growing precision, the box a hash actually names, and the
// eight cells around one, including the wrap at the antimeridian.
//
// It contains no geohash logic of its own. Stateless and read-only, so Render
// is fully deterministic and takes nothing from a caller.
package geohashdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/geohash/v0"
)

// The three fixed points the demo encodes. Coordinates only, so nothing here
// depends on the chain, the clock or the caller.
const (
	jutlandLat, jutlandLon = 57.64911, 10.40744
	leonLat, leonLon       = 42.6, -5.6
	sampleHash             = "ezs42"
)

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/")  -> a point at growing precision
//	Render("/cell")           -> the box a hash names
//	Render("/neighbors")      -> the eight cells around one, and the wrap
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Geohash\n\n")
	b.WriteString("Turning a latitude and longitude into a short base32 string, ")
	b.WriteString("demoing the [`p/moul/x/daily/geohash`](/p/moul/x/daily/geohash/v0) library.\n\n")

	switch parseArg(path) {
	case "cell":
		b.WriteString(renderCell())
	case "neighbors":
		b.WriteString(renderNeighbors())
	default:
		b.WriteString(renderPrecision())
	}
	return b.String()
}

// renderPrecision shows one point at every length, which is the property that
// makes a geohash worth storing: the prefix is the same place, zoomed out.
func renderPrecision() string {
	var b strings.Builder
	b.WriteString("## One point, at growing precision\n\n")
	b.WriteString("Jutland, Denmark, at ")
	b.WriteString(coord(jutlandLat, jutlandLon))
	b.WriteString(":\n\n```\n")
	for p := 1; p <= 11; p++ {
		h, err := geohash.Encode(jutlandLat, jutlandLon, p)
		if err != nil {
			return b.String() + "```\n_unexpected error: " + err.Error() + "_\n"
		}
		b.WriteString(pad(strconv.Itoa(p), 2))
		b.WriteString("  ")
		b.WriteString(h)
		b.WriteString("\n")
	}
	b.WriteString("```\n\n")
	b.WriteString("Every character adds five bits and every prefix is itself a valid ")
	b.WriteString("geohash of the same place, so truncating one zooms out. Two hashes ")
	b.WriteString("sharing a long prefix are close together, which is what lets an avl ")
	b.WriteString("tree keyed this way answer \"everything near here\" with a range scan ")
	b.WriteString("and no geometry at all.\n\n")
	b.WriteString("Two more places, at the length each one needs:\n\n")
	b.WriteString(bullet("Null Island", 0, 0, 5))
	b.WriteString(bullet("Leon, Spain", leonLat, leonLon, 5))
	b.WriteString(bullet("Jutland, Denmark", jutlandLat, jutlandLon, 6))
	b.WriteString("\n> Next: [`/cell`](/r/moul/x/daily/geohashdemo/v0:cell) for the box a ")
	b.WriteString("hash names, [`/neighbors`](/r/moul/x/daily/geohashdemo/v0:neighbors) ")
	b.WriteString("for the eight cells around one.\n")
	return b.String()
}

// renderCell shows that a geohash is a box and not a point, which is the thing
// most callers get wrong about it.
func renderCell() string {
	var b strings.Builder
	box, err := geohash.DecodeBox(sampleHash)
	if err != nil {
		return "_unexpected error: " + err.Error() + "_\n"
	}
	b.WriteString("## The box `" + sampleHash + "` names\n\n")
	b.WriteString("A geohash is a box, never a point, and the shorter the hash the bigger ")
	b.WriteString("the box.\n\n```\n")
	b.WriteString("latitude   " + num(box.MinLat) + " .. " + num(box.MaxLat) + "\n")
	b.WriteString("longitude  " + num(box.MinLon) + " .. " + num(box.MaxLon) + "\n")
	b.WriteString("size       " + num(box.HeightDeg()) + " by " + num(box.WidthDeg()) + " degrees\n")
	b.WriteString("```\n\n")
	lat, lon := box.Center()
	b.WriteString("`Decode` reports the centre, " + coord(lat, lon) + ", because the centre ")
	b.WriteString("is the best single point a box can give. The coordinates that produced ")
	b.WriteString("the hash, " + coord(leonLat, leonLon) + ", are inside it: ")
	b.WriteString(yesNo(box.Contains(leonLat, leonLon)) + ".\n\n")
	b.WriteString("Null Island is not: " + yesNo(box.Contains(0, 0)) + ".\n\n")
	b.WriteString("> Next: [`/neighbors`](/r/moul/x/daily/geohashdemo/v0:neighbors).\n")
	return b.String()
}

// renderNeighbors shows the eight cells around one, and the wrap that the
// classic lookup-table implementations do not do.
func renderNeighbors() string {
	var b strings.Builder
	b.WriteString("## The eight cells around `" + sampleHash + "`\n\n```\n")
	// The grid read as a map: north at the top, east on the right. The centre
	// is the hash itself, so it is not a direction.
	rows := [3][]geohash.Direction{
		{geohash.NorthWest, geohash.North, geohash.NorthEast},
		{geohash.West, geohash.East},
		{geohash.SouthWest, geohash.South, geohash.SouthEast},
	}
	for i, row := range rows {
		cells := make([]string, 0, 3)
		for _, d := range row {
			n, err := geohash.Neighbor(sampleHash, d)
			if err != nil {
				return b.String() + "```\n_unexpected error: " + err.Error() + "_\n"
			}
			cells = append(cells, n)
		}
		if i == 1 {
			// Put the hash itself back in the middle of the middle row.
			cells = []string{cells[0], sampleHash, cells[1]}
		}
		b.WriteString(strings.Join(cells, " ") + "\n")
	}
	b.WriteString("```\n\n")
	b.WriteString("Each one is computed by walking exactly one cell from the centre and ")
	b.WriteString("re-encoding. Every bound is an exact binary fraction, so the step lands ")
	b.WriteString("on another centre rather than near one, and stepping back is the identity.\n\n")
	b.WriteString("### The antimeridian is not an edge of the world\n\n")
	east, err := geohash.Neighbor("z", geohash.East)
	if err != nil {
		return b.String() + "_unexpected error: " + err.Error() + "_\n"
	}
	b.WriteString("`z` is the top right corner cell of the world. The cell east of it is ")
	b.WriteString("`" + east + "`, the top left one, because longitude wraps. The classic ")
	b.WriteString("lookup-table implementations report nothing there, which is a property ")
	b.WriteString("of the tables and not of the globe.\n\n")
	around, err := geohash.Neighbors("z")
	if err != nil {
		return b.String() + "_unexpected error: " + err.Error() + "_\n"
	}
	b.WriteString("Latitude genuinely stops, though, so `z` has no northern neighbour and ")
	b.WriteString("`Neighbors` returns " + strconv.Itoa(len(around)) + " cells rather than eight: ")
	b.WriteString("`" + strings.Join(around, "`, `") + "`.\n\n")
	b.WriteString("> Back to [the overview](/r/moul/x/daily/geohashdemo/v0).\n")
	return b.String()
}

// bullet renders one named place as a list item.
func bullet(name string, lat, lon float64, precision int) string {
	h, err := geohash.Encode(lat, lon, precision)
	if err != nil {
		return "- " + name + ": _unexpected error: " + err.Error() + "_\n"
	}
	return "- " + name + " (" + coord(lat, lon) + "): `" + h + "`\n"
}

// coord formats a latitude and longitude pair.
func coord(lat, lon float64) string { return num(lat) + ", " + num(lon) }

// num formats a float with no trailing zeros. Every value this demo prints is
// an exact binary fraction, so the shortest round-trip form is also the exact
// one.
func num(v float64) string { return strconv.FormatFloat(v, 'f', -1, 64) }

// yesNo renders a containment answer as a sentence fragment.
func yesNo(ok bool) string {
	if ok {
		return "yes"
	}
	return "no"
}

// pad right-aligns a short string to width n, so the precision column lines up
// inside the code block.
func pad(s string, n int) string {
	for len(s) < n {
		s = " " + s
	}
	return s
}

// parseArg extracts the first path segment.
func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}

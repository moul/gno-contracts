package geohash

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestEncode(t *testing.T) {
	tests := []struct {
		name      string
		lat, lon  float64
		precision int
		want      string
	}{
		// The two reference vectors every geohash implementation is checked
		// against; both come from the algorithm's public description.
		{"jutland 11 chars", 57.64911, 10.40744, 11, "u4pruydqqvj"},
		{"leon 5 chars", 42.6, -5.6, 5, "ezs42"},
		// Null island sits on both midpoints, so every comparison takes the
		// "greater or equal" branch.
		{"null island", 0, 0, 5, "s0000"},
		{"south west corner", -90, -180, 5, "00000"},
		{"north east corner", 90, 180, 5, "zzzzz"},
		{"precision one", 57.64911, 10.40744, 1, "u"},
		{"shorter hash is a prefix", 57.64911, 10.40744, 4, "u4pr"},
	}
	for _, tt := range tests {
		got, err := Encode(tt.lat, tt.lon, tt.precision)
		uassert.NoError(t, err, tt.name)
		uassert.Equal(t, tt.want, got, tt.name)
	}
}

func TestEncodeErrors(t *testing.T) {
	tests := []struct {
		name      string
		lat, lon  float64
		precision int
	}{
		{"precision zero", 0, 0, 0},
		{"precision negative", 0, 0, -1},
		{"precision too large", 0, 0, MaxPrecision + 1},
		{"latitude above range", 90.1, 0, 5},
		{"latitude below range", -90.1, 0, 5},
		{"longitude above range", 0, 180.1, 5},
		{"longitude below range", 0, -180.1, 5},
	}
	for _, tt := range tests {
		got, err := Encode(tt.lat, tt.lon, tt.precision)
		uassert.Error(t, err, tt.name)
		uassert.Equal(t, "", got, tt.name)
	}
}

func TestDecodeBox(t *testing.T) {
	// The cell the Leon vector lands in. Every bound is an exact binary
	// fraction, which is why they can be compared literally.
	b, err := DecodeBox("ezs42")
	uassert.NoError(t, err)
	uassert.Equal(t, 42.5830078125, b.MinLat)
	uassert.Equal(t, 42.626953125, b.MaxLat)
	uassert.Equal(t, -5.625, b.MinLon)
	uassert.Equal(t, -5.5810546875, b.MaxLon)

	uassert.True(t, b.Contains(42.6, -5.6), "contains its own point")
	uassert.False(t, b.Contains(0, 0), "does not contain null island")

	lat, lon := b.Center()
	uassert.Equal(t, 42.60498046875, lat)
	uassert.Equal(t, -5.60302734375, lon)
}

func TestDecodeIsTheBoxCenter(t *testing.T) {
	lat, lon, err := Decode("ezs42")
	uassert.NoError(t, err)
	b, err := DecodeBox("ezs42")
	uassert.NoError(t, err)
	clat, clon := b.Center()
	uassert.Equal(t, clat, lat)
	uassert.Equal(t, clon, lon)
}

func TestRoundTrip(t *testing.T) {
	// Decoding a hash and re-encoding its centre at the same length gives the
	// hash back: the centre can never fall in a neighbouring cell.
	hashes := []string{"u", "u4", "u4pr", "ezs42", "s0000", "00000", "zzzzz", "u4pruydqqvj"}
	for _, h := range hashes {
		lat, lon, err := Decode(h)
		uassert.NoError(t, err, h)
		got, err := Encode(lat, lon, len(h))
		uassert.NoError(t, err, h)
		uassert.Equal(t, h, got, h)
	}
}

func TestDecodeErrors(t *testing.T) {
	// The alphabet drops a, i, l and o on purpose; anything outside it, and an
	// over-long hash, are refused rather than silently truncated.
	for _, h := range []string{"", "a", "i", "l", "o", "ezs4A", "ezs4 ", "u4pruydqqvjxx"} {
		_, _, err := Decode(h)
		uassert.Error(t, err, h)
	}
}

func TestNeighborIsReversible(t *testing.T) {
	// A cell well inside the grid: stepping away and back is the identity, in
	// all eight directions.
	const h = "ezs42"
	for _, d := range []Direction{North, NorthEast, East, SouthEast, South, SouthWest, West, NorthWest} {
		n, err := Neighbor(h, d)
		uassert.NoError(t, err, d.String())
		uassert.NotEqual(t, h, n, d.String())
		back, err := Neighbor(n, opposite(d))
		uassert.NoError(t, err, d.String())
		uassert.Equal(t, h, back, d.String())
	}
}

func TestNeighborKnownCells(t *testing.T) {
	// Cross-checked against the classic border/neighbour lookup tables, which
	// are a completely different way of computing the same answer.
	tests := []struct {
		dir  Direction
		want string
	}{
		{North, "ezs48"},
		{South, "ezs40"},
		{East, "ezs43"},
		{West, "ezefr"},
		{NorthEast, "ezs49"},
		{SouthWest, "ezefp"},
	}
	for _, tt := range tests {
		got, err := Neighbor("ezs42", tt.dir)
		uassert.NoError(t, err, tt.dir.String())
		uassert.Equal(t, tt.want, got, tt.dir.String())
	}
}

func TestNeighborWrapsLongitude(t *testing.T) {
	// The antimeridian is not an edge of the world: the column east of the
	// last one is the first column again.
	east, err := Neighbor("z", East)
	uassert.NoError(t, err)
	uassert.Equal(t, "b", east)

	west, err := Neighbor("b", West)
	uassert.NoError(t, err)
	uassert.Equal(t, "z", west)
}

func TestNeighborStopsAtThePoles(t *testing.T) {
	// Latitude does not wrap: there is nothing north of the top row.
	_, err := Neighbor("z", North)
	uassert.ErrorIs(t, err, ErrNoNeighbor)

	_, err = Neighbor("0", South)
	uassert.ErrorIs(t, err, ErrNoNeighbor)

	// The same cell still has neighbours sideways and downwards.
	got, err := Neighbor("z", South)
	uassert.NoError(t, err)
	uassert.Equal(t, "x", got)
}

func TestNeighborErrors(t *testing.T) {
	_, err := Neighbor("", North)
	uassert.Error(t, err)

	_, err = Neighbor("ezs4a", North)
	uassert.Error(t, err)

	_, err = Neighbor("ezs42", Direction(42))
	uassert.ErrorIs(t, err, ErrDirection)
}

func TestNeighbors(t *testing.T) {
	got, err := Neighbors("ezs42")
	uassert.NoError(t, err)
	uassert.Equal(t, 8, len(got))
	uassert.Equal(t, "ezs48", got[0]) // North
	uassert.Equal(t, "ezs43", got[2]) // East
	uassert.Equal(t, "ezs40", got[4]) // South
	uassert.Equal(t, "ezefr", got[6]) // West

	// Unique: a repeat would mean the stepping collapsed two directions.
	seen := map[string]bool{}
	for _, n := range got {
		uassert.False(t, seen[n], n)
		seen[n] = true
	}

	// At the pole the row above is missing, and the list is short rather than
	// carrying empty strings a caller would have to filter.
	got, err = Neighbors("z")
	uassert.NoError(t, err)
	uassert.Equal(t, 5, len(got))
	for _, n := range got {
		uassert.NotEqual(t, "", n)
	}
}

func TestDirectionString(t *testing.T) {
	tests := []struct {
		d    Direction
		want string
	}{
		{North, "north"},
		{NorthEast, "north-east"},
		{East, "east"},
		{SouthEast, "south-east"},
		{South, "south"},
		{SouthWest, "south-west"},
		{West, "west"},
		{NorthWest, "north-west"},
		{Direction(42), "unknown"},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, tt.d.String())
	}
}

func TestBoxDimensions(t *testing.T) {
	b, err := DecodeBox("ezs42")
	uassert.NoError(t, err)
	// Five characters is 25 bits: 13 go to longitude, 12 to latitude, and the
	// two halves of the world differ by exactly that factor of two, so the
	// cell comes out square in degrees.
	uassert.Equal(t, 180.0/4096.0, b.HeightDeg())
	uassert.Equal(t, 360.0/8192.0, b.WidthDeg())

	// One more character is five more bits, so the cell is 32 times smaller.
	b6, err := DecodeBox("ezs42d")
	uassert.NoError(t, err)
	uassert.Equal(t, b.HeightDeg()/8, b6.HeightDeg())
	uassert.Equal(t, b.WidthDeg()/4, b6.WidthDeg())
}

// opposite is the test's own inverse of a direction, kept here rather than
// exported so the package surface stays the part callers need.
func opposite(d Direction) Direction {
	return Direction((int(d) + 4) % 8)
}

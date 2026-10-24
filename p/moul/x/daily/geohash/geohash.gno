// Package geohash encodes a latitude/longitude pair into the short base32
// string known as a geohash, decodes one back into the cell it names, and
// walks from a cell to the eight around it.
//
// A geohash is a prefix code: every character narrows the box, so two places
// that share a long prefix are close together, and truncating a hash zooms
// out. That is the whole reason to use one on chain, where an avl tree keyed
// by geohash gives a cheap "everything near here" range scan without storing
// any geometry: Get the prefix, iterate, done.
//
//	hash, _ := geohash.Encode(42.6, -5.6, 5)   // "ezs42"
//	box, _ := geohash.DecodeBox("ezs42")       // the cell it names
//	north, _ := geohash.Neighbor("ezs42", geohash.North)
//
// The alphabet is the standard one and deliberately drops a, i, l and o, so a
// hash survives being read aloud or written down. Anything outside it is
// refused rather than quietly skipped.
//
// Everything here is pure arithmetic on exact binary fractions: both world
// ranges are powers of two divided by powers of two, so every box bound is
// representable in a float64 and two identical calls can never disagree. No
// map is iterated and no value is rounded, which is what makes a Render built
// on this deterministic.
//
// A live demo of this package is at
// [r/moul/x/daily/geohashdemo](/r/moul/x/daily/geohashdemo/v0).
package geohash

import "errors"

// Alphabet is the standard geohash base32 alphabet. It omits a, i, l and o so
// that a hash read aloud or copied by hand stays unambiguous.
const Alphabet = "0123456789bcdefghjkmnpqrstuvwxyz"

// MaxPrecision is the longest hash this package will produce or accept: 12
// characters, 60 bits, a cell well under a millimetre across. Past that the
// extra characters say nothing a float64 can still distinguish.
const MaxPrecision = 12

var (
	// ErrPrecision is returned by Encode for a length outside 1..MaxPrecision.
	ErrPrecision = errors.New("geohash: precision out of range")
	// ErrLatitude is returned by Encode for a latitude outside -90..90.
	ErrLatitude = errors.New("geohash: latitude out of range")
	// ErrLongitude is returned by Encode for a longitude outside -180..180.
	ErrLongitude = errors.New("geohash: longitude out of range")
	// ErrEmpty is returned when a hash is required and none was given.
	ErrEmpty = errors.New("geohash: empty hash")
	// ErrTooLong is returned for a hash longer than MaxPrecision.
	ErrTooLong = errors.New("geohash: hash longer than the maximum precision")
	// ErrInvalidChar is returned for a character outside Alphabet, which
	// includes the four letters the alphabet deliberately leaves out.
	ErrInvalidChar = errors.New("geohash: character is not in the geohash alphabet")
	// ErrDirection is returned by Neighbor for a Direction it does not know.
	ErrDirection = errors.New("geohash: unknown direction")
	// ErrNoNeighbor is returned by Neighbor when the step leaves the world:
	// north of the top row, or south of the bottom one. Longitude wraps and
	// never produces this.
	ErrNoNeighbor = errors.New("geohash: no neighbour in that direction")
)

// Box is the rectangle of latitudes and longitudes a geohash names. A geohash
// is a box, never a point, and the shorter the hash the larger the box.
type Box struct {
	MinLat, MaxLat float64
	MinLon, MaxLon float64
}

// Center returns the midpoint of the box, which is what Decode reports.
func (b Box) Center() (lat, lon float64) {
	return (b.MinLat + b.MaxLat) / 2, (b.MinLon + b.MaxLon) / 2
}

// Contains reports whether a point falls inside the box. The lower and left
// edges belong to the box and the upper and right ones do not, matching how
// Encode assigns a point sitting exactly on a midpoint.
func (b Box) Contains(lat, lon float64) bool {
	return lat >= b.MinLat && lat < b.MaxLat && lon >= b.MinLon && lon < b.MaxLon
}

// HeightDeg is the box's north-south extent in degrees.
func (b Box) HeightDeg() float64 { return b.MaxLat - b.MinLat }

// WidthDeg is the box's east-west extent in degrees.
func (b Box) WidthDeg() float64 { return b.MaxLon - b.MinLon }

// Direction names one of the eight cells around a geohash. The values are
// ordered clockwise from north, so adding four modulo eight is the reverse.
type Direction int

// The eight directions, clockwise from north.
const (
	North Direction = iota
	NorthEast
	East
	SouthEast
	South
	SouthWest
	West
	NorthWest
)

// String returns the lowercase hyphenated name, or "unknown" for a value that
// is not one of the eight.
func (d Direction) String() string {
	switch d {
	case North:
		return "north"
	case NorthEast:
		return "north-east"
	case East:
		return "east"
	case SouthEast:
		return "south-east"
	case South:
		return "south"
	case SouthWest:
		return "south-west"
	case West:
		return "west"
	case NorthWest:
		return "north-west"
	}
	return "unknown"
}

// step returns the latitude and longitude offsets, in whole cells, for a
// direction. The second result is false for a direction that is not one of
// the eight.
func (d Direction) step() (dLat, dLon float64, ok bool) {
	switch d {
	case North:
		return 1, 0, true
	case NorthEast:
		return 1, 1, true
	case East:
		return 0, 1, true
	case SouthEast:
		return -1, 1, true
	case South:
		return -1, 0, true
	case SouthWest:
		return -1, -1, true
	case West:
		return 0, -1, true
	case NorthWest:
		return 1, -1, true
	}
	return 0, 0, false
}

// Encode returns the geohash of a point, precision characters long.
//
// Longitude takes the first bit and the two alternate, so an odd number of
// characters gives longitude one bit more than latitude and the cell comes out
// roughly square in degrees. A point sitting exactly on a dividing line goes
// to the upper, or eastern, half.
func Encode(lat, lon float64, precision int) (string, error) {
	if precision < 1 || precision > MaxPrecision {
		return "", ErrPrecision
	}
	if lat < -90 || lat > 90 {
		return "", ErrLatitude
	}
	if lon < -180 || lon > 180 {
		return "", ErrLongitude
	}

	latMin, latMax := -90.0, 90.0
	lonMin, lonMax := -180.0, 180.0

	out := make([]byte, 0, precision)
	ch, bit, even := 0, 0, true
	for len(out) < precision {
		if even {
			mid := (lonMin + lonMax) / 2
			if lon >= mid {
				ch |= 1 << uint(4-bit)
				lonMin = mid
			} else {
				lonMax = mid
			}
		} else {
			mid := (latMin + latMax) / 2
			if lat >= mid {
				ch |= 1 << uint(4-bit)
				latMin = mid
			} else {
				latMax = mid
			}
		}
		even = !even
		if bit < 4 {
			bit++
			continue
		}
		out = append(out, Alphabet[ch])
		ch, bit = 0, 0
	}
	return string(out), nil
}

// Decode returns the centre of the cell a geohash names. The centre is the
// best single point a hash can give: the cell itself is what was encoded, and
// DecodeBox is how to ask how big it is.
func Decode(hash string) (lat, lon float64, err error) {
	b, err := DecodeBox(hash)
	if err != nil {
		return 0, 0, err
	}
	lat, lon = b.Center()
	return lat, lon, nil
}

// DecodeBox returns the cell a geohash names.
func DecodeBox(hash string) (Box, error) {
	if hash == "" {
		return Box{}, ErrEmpty
	}
	if len(hash) > MaxPrecision {
		return Box{}, ErrTooLong
	}

	b := Box{MinLat: -90, MaxLat: 90, MinLon: -180, MaxLon: 180}
	even := true
	for i := 0; i < len(hash); i++ {
		v, ok := symbol(hash[i])
		if !ok {
			return Box{}, ErrInvalidChar
		}
		for _, mask := range [5]int{16, 8, 4, 2, 1} {
			if even {
				mid := (b.MinLon + b.MaxLon) / 2
				if v&mask != 0 {
					b.MinLon = mid
				} else {
					b.MaxLon = mid
				}
			} else {
				mid := (b.MinLat + b.MaxLat) / 2
				if v&mask != 0 {
					b.MinLat = mid
				} else {
					b.MaxLat = mid
				}
			}
			even = !even
		}
	}
	return b, nil
}

// Neighbor returns the geohash of the cell one step away, at the same
// precision.
//
// It works by walking one whole cell from the centre and re-encoding, which is
// exact: every cell bound is a binary fraction, so the step lands on another
// centre rather than near one.
//
// Longitude wraps, so the cell east of the last column is the first column
// again: the antimeridian is a line on a map, not an edge of the world. The
// classic lookup-table implementations report nothing there, which is a
// property of the tables and not of the globe. Latitude genuinely stops, and
// a step past a pole returns ErrNoNeighbor.
func Neighbor(hash string, d Direction) (string, error) {
	dLat, dLon, ok := d.step()
	if !ok {
		return "", ErrDirection
	}
	b, err := DecodeBox(hash)
	if err != nil {
		return "", err
	}
	lat, lon := b.Center()

	lat += dLat * b.HeightDeg()
	if lat > 90 || lat < -90 {
		return "", ErrNoNeighbor
	}
	lon += dLon * b.WidthDeg()
	if lon > 180 {
		lon -= 360
	}
	if lon < -180 {
		lon += 360
	}
	return Encode(lat, lon, len(hash))
}

// Neighbors returns the cells around a geohash, clockwise from north.
//
// The result is short rather than padded when a direction has no cell, which
// only happens at the poles: a caller iterating the result never has to filter
// an empty string out of it.
func Neighbors(hash string) ([]string, error) {
	if _, err := DecodeBox(hash); err != nil {
		return nil, err
	}
	out := make([]string, 0, 8)
	for d := North; d <= NorthWest; d++ {
		n, err := Neighbor(hash, d)
		if err == ErrNoNeighbor {
			continue
		}
		if err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, nil
}

// symbol maps an alphabet character to its five-bit value. It is a linear scan
// rather than a map because the alphabet is 32 bytes long and a package-level
// map would be one more object for every realm that imports this.
func symbol(c byte) (int, bool) {
	for i := 0; i < len(Alphabet); i++ {
		if Alphabet[i] == c {
			return i, true
		}
	}
	return 0, false
}

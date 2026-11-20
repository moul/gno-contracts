package hyperloglog

// FNV-1a, 64 bit. The same choice and the same reason as
// [p/moul/x/daily/countminsketch](/p/moul/x/daily/countminsketch/v0): the hash
// has to be computed in pure gno, because the only hash a realm gets for free
// is map ordering, and that is not a value two nodes have to agree on.
//
// FNV-1a is not a good hash in the cryptographic sense and nothing here needs
// one. What a sketch needs is avalanche: a one-character change anywhere in
// the input must move the leading bits, because those bits pick the register
// AND supply the run of zeros that is the whole estimate. FNV-1a's weakness is
// the opposite end, the low bits of short inputs, so the final mix below
// matters more here than the hash does.
const (
	fnvOffset64 = 14695981039346656037
	fnvPrime64  = 1099511628211
)

// hash64 returns the mixed FNV-1a hash of s.
func hash64(s string) uint64 {
	h := uint64(fnvOffset64)
	for i := 0; i < len(s); i++ {
		h ^= uint64(s[i])
		h *= fnvPrime64
	}
	return mix64(h)
}

// mix64 is the splitmix64 finalizer. FNV-1a alone leaves short inputs
// clustered in the high bits, which for this structure is not a cosmetic
// problem: the top p bits choose the register, so clustering there means a
// handful of registers absorbing everything and a count that reads far too
// low. Running the result through a finalizer costs three shifts and two
// multiplies and removes the whole failure mode.
func mix64(h uint64) uint64 {
	h ^= h >> 33
	h *= 0xff51afd7ed558ccd
	h ^= h >> 33
	h *= 0xc4ceb9fe1a85ec53
	h ^= h >> 33
	return h
}

// rho returns the 1-based position of the leftmost set bit of w, capped at
// limit+1. The cap is not a rounding convenience: w is the hash with the
// register bits already shifted out, so only its top `limit` bits carry
// information and a longer run of zeros than that is an artefact of the shift
// rather than a property of the element.
func rho(w uint64, limit uint8) uint8 {
	var r uint8 = 1
	for r <= limit {
		if w&(uint64(1)<<63) != 0 {
			return r
		}
		w <<= 1
		r++
	}
	return r
}

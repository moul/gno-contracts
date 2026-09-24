package riscv

import "gno.land/p/moul/x/vm/vmkit/v0"

// Memory is the guest's flat address space, with a snapshot that carries only
// the pages it actually touched.
//
// The shape is the one the bf ladder argued for. Running memory is a flat
// []byte because a load or a store happens on a large fraction of instructions
// and an avl lookup per access would dominate the interpreter the way
// vmkit.Meter.Charge did there. Snapshot cost is solved separately, by a dirty
// bitmap: a program that writes one page pauses in one page, not in a megabyte,
// which is the same trick that lets a bf hello world pause in 43 bytes.
//
// That answers the open question on the design issue ("memory size versus
// snapshot cost") without paying for it on every instruction.
const (
	// PageSize is the snapshot granularity, not an MMU page: there is no
	// address translation here, only bookkeeping about what changed.
	PageSize = 4096

	// MemSize is the address space. 1 MiB is far more than a no_std guest
	// needs and small enough that the flat allocation is not the cost.
	MemSize = 1 << 20

	pageCount = MemSize / PageSize
)

// Memory is a flat address space plus the record of which pages were written.
type Memory struct {
	b     []byte
	dirty []bool
}

// NewMemory returns a zeroed address space.
func NewMemory() *Memory {
	return &Memory{b: make([]byte, MemSize), dirty: make([]bool, pageCount)}
}

// Size returns the address space size.
func (m *Memory) Size() int { return len(m.b) }

// DirtyPages reports how many pages the guest has written, which is what a
// snapshot costs.
func (m *Memory) DirtyPages() int {
	n := 0
	for _, d := range m.dirty {
		if d {
			n++
		}
	}
	return n
}

// inRange reports whether [addr, addr+size) is inside the address space.
//
// Out of range is a trap rather than a wrap. RISC-V leaves the behaviour of an
// access outside physical memory to the platform, and a chain has to pick the
// one that cannot differ between nodes: refusing is deterministic, wrapping
// invites a guest to alias two addresses and get different answers from
// different memory sizes.
func (m *Memory) inRange(addr uint32, size int) bool {
	end := uint64(addr) + uint64(size)
	return end <= uint64(len(m.b))
}

// Load8, Load16 and Load32 read little-endian, which is what RV32 is.
func (m *Memory) Load8(addr uint32) (uint8, bool) {
	if !m.inRange(addr, 1) {
		return 0, false
	}
	return m.b[addr], true
}

func (m *Memory) Load16(addr uint32) (uint16, bool) {
	if !m.inRange(addr, 2) {
		return 0, false
	}
	return uint16(m.b[addr]) | uint16(m.b[addr+1])<<8, true
}

func (m *Memory) Load32(addr uint32) (uint32, bool) {
	if !m.inRange(addr, 4) {
		return 0, false
	}
	return uint32(m.b[addr]) | uint32(m.b[addr+1])<<8 |
		uint32(m.b[addr+2])<<16 | uint32(m.b[addr+3])<<24, true
}

func (m *Memory) Store8(addr uint32, v uint8) bool {
	if !m.inRange(addr, 1) {
		return false
	}
	m.b[addr] = v
	m.dirty[addr/PageSize] = true
	return true
}

func (m *Memory) Store16(addr uint32, v uint16) bool {
	if !m.inRange(addr, 2) {
		return false
	}
	m.b[addr] = uint8(v)
	m.b[addr+1] = uint8(v >> 8)
	m.dirty[addr/PageSize] = true
	m.dirty[(addr+1)/PageSize] = true
	return true
}

func (m *Memory) Store32(addr uint32, v uint32) bool {
	if !m.inRange(addr, 4) {
		return false
	}
	m.b[addr] = uint8(v)
	m.b[addr+1] = uint8(v >> 8)
	m.b[addr+2] = uint8(v >> 16)
	m.b[addr+3] = uint8(v >> 24)
	m.dirty[addr/PageSize] = true
	m.dirty[(addr+3)/PageSize] = true
	return true
}

// WriteImage places a program image at addr and marks the pages it covers, so
// a snapshot taken before the first store still carries the program.
func (m *Memory) WriteImage(addr uint32, img []byte) bool {
	if !m.inRange(addr, len(img)) {
		return false
	}
	copy(m.b[addr:], img)
	for i := 0; i < len(img); i++ {
		m.dirty[(uint64(addr)+uint64(i))/PageSize] = true
	}
	return true
}

// Snapshot writes only the dirty pages, each prefixed by its index.
func (m *Memory) Snapshot(w *vmkit.Writer) {
	w.Uint32(uint32(m.DirtyPages()))
	for i, d := range m.dirty {
		if !d {
			continue
		}
		w.Uint32(uint32(i))
		w.Bytes(m.b[i*PageSize : (i+1)*PageSize])
	}
}

// Restore reads a snapshot written by Snapshot into a zeroed address space.
func (m *Memory) Restore(r *vmkit.Reader) error {
	m.b = make([]byte, MemSize)
	m.dirty = make([]bool, pageCount)
	n := int(r.Uint32())
	if n < 0 || n > pageCount {
		return vmkit.ErrBadSnapshot
	}
	for i := 0; i < n; i++ {
		idx := int(r.Uint32())
		page := r.Bytes()
		if err := r.Err(); err != nil {
			return err
		}
		if idx < 0 || idx >= pageCount || len(page) != PageSize {
			return vmkit.ErrBadSnapshot
		}
		copy(m.b[idx*PageSize:], page)
		m.dirty[idx] = true
	}
	return r.Err()
}

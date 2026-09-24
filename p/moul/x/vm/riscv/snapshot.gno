package riscv

import "gno.land/p/moul/x/vm/vmkit/v0"

// Snapshot serializes the hart: registers, pc, status, and only the memory
// pages the guest has written.
//
// A 1 MiB address space serialized on every pause would make continuations
// cost more than re-running, which is exactly the kill criterion vmkit set for
// them. The dirty bitmap is what avoids it: a guest that has touched two pages
// pauses in about 8 KiB regardless of how much memory it was given.
func (m *Machine) Snapshot() []byte {
	if m.code == nil {
		m.code = &code{}
	}
	w := vmkit.NewWriter(4096)
	w.Uint32(snapMagic)
	w.Byte(snapVersion)
	for i := 0; i < 32; i++ {
		w.Uint32(m.reg[i])
	}
	w.Uint32(m.pc)
	w.Byte(byte(m.status))
	w.String(m.trap)
	w.Int(int64(m.outLen))
	// The text segment's extent, so a restored hart knows which of its pages
	// are code and can predecode them again. The code itself is not written:
	// it is already in the memory pages, which WriteImage marked dirty.
	w.Uint32(m.code.base)
	w.Uint32(m.code.words)
	m.mem.Snapshot(w)
	return w.Out()
}

// Restore loads a snapshot. The program image is not carried separately: it
// lives in the memory pages, which were marked dirty when it was written, so a
// restored hart has its code without the instance storing it twice.
func (m *Machine) Restore(b []byte) error {
	r := vmkit.NewReader(b)
	if r.Uint32() != snapMagic {
		return vmkit.ErrBadSnapshot
	}
	if r.Byte() != snapVersion {
		return vmkit.ErrBadSnapshot
	}
	var reg [32]uint32
	for i := 0; i < 32; i++ {
		reg[i] = r.Uint32()
	}
	pc := r.Uint32()
	status := vmkit.Status(r.Byte())
	trap := r.String()
	outLen := int(r.Int())
	base := r.Uint32()
	words := r.Uint32()
	if err := r.Err(); err != nil {
		return err
	}
	// A text segment that does not fit in the address space is a snapshot this
	// machine did not write, and predecoding it would index past the memory.
	if base%4 != 0 || uint64(base)+uint64(words)*4 > uint64(MemSize) {
		return vmkit.ErrBadSnapshot
	}

	mem := NewMemory()
	if err := mem.Restore(r); err != nil {
		return err
	}
	if err := r.Err(); err != nil {
		return err
	}

	m.reg, m.pc, m.status, m.trap, m.outLen, m.mem = reg, pc, status, trap, outLen, mem
	// Predecode again from the restored pages. This is the work a resume pays
	// for, once, in exchange for not paying a fetch on every instruction after
	// it, and it is why stores into the text segment trap: the arrays and the
	// memory would otherwise be free to disagree.
	m.code = predecode(base, mem.b[base:base+words*4])
	// x0 is hardwired, and a snapshot that claims otherwise is not one this
	// machine wrote.
	m.reg[0] = 0
	return nil
}

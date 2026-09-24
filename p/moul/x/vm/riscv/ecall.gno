package riscv

import "gno.land/p/moul/x/vm/vmkit/v0"

// The syscall table: the entire interface between a guest and the chain.
//
// Register-passing, in the RISC-V Linux convention a compiler already knows:
// a7 (x17) selects the call, a0..a2 (x10..x12) carry arguments, a0 receives the
// result. A guest written against these needs no gno-specific runtime, only the
// three lines of inline assembly every no_std program already has for ecall.
//
// Deliberately small. Every call here maps onto something [vmkit.Host] already
// offers, because the Host is the audited surface and a syscall that reaches
// past it would be a second, unreviewed one.
const (
	sysExit   = 93 // a0 = status. The Linux number, so a guest can reuse its libc shim.
	sysWrite  = 64 // a0 = fd (ignored), a1 = buf, a2 = len -> Host.Output
	sysRead   = 63 // a0 = fd (ignored), a1 = buf, a2 = len <- Host.Input
	sysHeight = 90 // -> block height
	sysNow    = 91 // -> block time, Unix seconds
	sysCaller = 92 // a0 = buf, a1 = len; writes the caller address, returns bytes written
	sysLog    = 94 // a0 = buf, a1 = len -> Host.Log
	sysEmit   = 95 // a0 = type buf, a1 = type len, a2 = body buf, a3 = body len
)

// maxSyscallBytes bounds one call's buffer. A guest asking to write a gigabyte
// is a guest that found the host's allocator, not one with something to say.
const maxSyscallBytes = 64 * 1024

// ecall dispatches a syscall. It returns the machine status and whether the
// machine should stop: only exit stops it, everything else returns to the guest
// with a0 set.
func (m *Machine) ecall(h vmkit.Host) (vmkit.Status, bool) {
	switch m.reg[17] { // a7
	case sysExit:
		// The guest's exit status is not the machine's: a program that returns
		// 1 has halted, it has not trapped. Trapping is for what the machine
		// could not do, and a chain should not confuse "your code said no"
		// with "the VM broke".
		return vmkit.Halted, true

	case sysWrite:
		buf, ok := m.readGuest(m.reg[11], m.reg[12])
		if !ok {
			m.reg[10] = ^uint32(0)
			return vmkit.Running, false
		}
		h.Output(buf)
		m.outLen += len(buf)
		m.reg[10] = uint32(len(buf))

	case sysRead:
		in := h.Input()
		n := int(m.reg[12])
		if n > len(in) {
			n = len(in)
		}
		if n > maxSyscallBytes {
			n = maxSyscallBytes
		}
		if !m.writeGuest(m.reg[11], in[:n]) {
			m.reg[10] = ^uint32(0)
			return vmkit.Running, false
		}
		m.reg[10] = uint32(n)

	case sysHeight:
		m.reg[10] = uint32(h.Height())

	case sysNow:
		m.reg[10] = uint32(h.Now())

	case sysCaller:
		addr := []byte(h.Caller().String())
		n := int(m.reg[11])
		if n > len(addr) {
			n = len(addr)
		}
		if !m.writeGuest(m.reg[10], addr[:n]) {
			m.reg[10] = ^uint32(0)
			return vmkit.Running, false
		}
		m.reg[10] = uint32(n)

	case sysLog:
		buf, ok := m.readGuest(m.reg[10], m.reg[11])
		if !ok {
			m.reg[10] = ^uint32(0)
			return vmkit.Running, false
		}
		h.Log(string(buf))
		m.reg[10] = uint32(len(buf))

	case sysEmit:
		typ, ok1 := m.readGuest(m.reg[10], m.reg[11])
		body, ok2 := m.readGuest(m.reg[12], m.reg[13])
		if !ok1 || !ok2 {
			m.reg[10] = ^uint32(0)
			return vmkit.Running, false
		}
		h.Emit(string(typ), "body", string(body))
		m.reg[10] = 0

	default:
		// An unknown syscall is a trap, not a silent zero. A guest compiled
		// against a newer table must fail loudly on an older host rather than
		// read a success it did not get.
		m.trap = "unknown syscall"
		return vmkit.Trapped, true
	}
	return vmkit.Running, false
}

// readGuest copies a buffer out of guest memory, refusing anything out of range
// or larger than maxSyscallBytes.
func (m *Machine) readGuest(addr, length uint32) ([]byte, bool) {
	if length > maxSyscallBytes || !m.mem.inRange(addr, int(length)) {
		return nil, false
	}
	out := make([]byte, length)
	copy(out, m.mem.b[addr:addr+length])
	return out, true
}

// writeGuest copies into guest memory, marking the pages it touched.
func (m *Machine) writeGuest(addr uint32, b []byte) bool {
	if len(b) > maxSyscallBytes || !m.mem.inRange(addr, len(b)) {
		return false
	}
	copy(m.mem.b[addr:], b)
	for i := 0; i < len(b); i++ {
		m.mem.dirty[(uint64(addr)+uint64(i))/PageSize] = true
	}
	return true
}

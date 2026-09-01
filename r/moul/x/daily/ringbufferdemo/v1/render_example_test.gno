package ringbufferdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Ring Buffer
	//
	// A fixed-capacity FIFO that overwrites its oldest entry, demoing the [`p/moul/x/daily/ringbuffer`](/p/moul/x/daily/ringbuffer/v1) library.
	//
	// Capacity **4**, pushing 6 entries:
	//
	// | push | evicted | contents (oldest → newest) |
	// |---|---|---|
	// | `alpha` | — | `alpha` |
	// | `bravo` | — | `alpha bravo` |
	// | `charlie` | — | `alpha bravo charlie` |
	// | `delta` | — | `alpha bravo charlie delta` |
	// | `echo` | `alpha` | `bravo charlie delta echo` |
	// | `foxtrot` | `bravo` | `charlie delta echo foxtrot` |
	//
	// > The buffer never grows: once full, each push costs the oldest entry. On chain that bound is the point — an unbounded queue is an unbounded storage bill.
}

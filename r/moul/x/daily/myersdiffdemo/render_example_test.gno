package myersdiffdemo

// ExampleRender pins the realm Render output as a testable example.
//
// The block below is copied verbatim from what gno printed, never hand typed:
// every diff line and every count in it is computed by the library under test,
// so a change in the algorithm shows up here as a diff.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Myers diff
	//
	// Demo of the [`p/moul/x/daily/myersdiff`](/p/moul/x/daily/myersdiff/v0) library: the shortest edit script between two documents, the algorithm behind `git diff`.
	//
	// It walks a grid whose diagonals are matching lines, taking the furthest-reaching path at each round, and stops the first time a path reaches the far corner. That round number is the number of edits, and it is minimal because no shorter path was available at any earlier round.
	//
	// ## The scenarios
	//
	// | scenario | edits | minimal | what it shows |
	// | --- | --- | --- | --- |
	// | [patch](/r/moul/x/daily/myersdiffdemo/v0:patch) | 5 | yes | A small patch in a large file |
	// | [insert](/r/moul/x/daily/myersdiffdemo/v0:insert) | 3 | yes | Appending to an empty document |
	// | [move](/r/moul/x/daily/myersdiffdemo/v0:move) | 2 | yes | A moved line is a delete and an insert |
	// | [starved](/r/moul/x/daily/myersdiffdemo/v0:starved) | 10 | no | A budget too small for the answer |
	//
	// ## Context width
	//
	// Append a number to widen or narrow the unchanged lines printed around each change: [`patch/0`](/r/moul/x/daily/myersdiffdemo/v0:patch/0) shows the changes alone, [`patch/6`](/r/moul/x/daily/myersdiffdemo/v0:patch/6) shows the whole file as one hunk. Anything out of range is clamped to 0..6.
	//
	// ## API
	//
	// - `Lines(a, b string) Script` is the whole surface for text.
	// - `Script.Apply(a []string) []string` replays the script, so a stored one can be verified.
	// - `Hunks(s Script, context int) []Hunk` groups the script the way a review tool prints it.
	// - `Unified(a, b string, context int) string` is the two above, as text.
}

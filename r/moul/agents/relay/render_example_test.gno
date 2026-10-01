package relay

import (
	"gno.land/p/moul/agents/msg/v0"
	"gno.land/p/nt/testutils/v0"
)

// seed builds a deterministic ring without crossing, so an example can pin the
// output. Examples run after every Test and take no arguments, so they cannot
// call Post; writing the encoded entries directly is the same bytes by a
// shorter road, and the heights are fixed rather than read from the chain.
func seed() {
	reset()
	entries := []Entry{
		{Msg: msg.Msg{Seq: 1, Height: 500, From: "agent-a", Topic: "build", Kind: "note", Ref: "pr/1", Body: "ci is green"}, Author: testutils.TestAddress("alice")},
		// Session set: two agents under one owner, told apart by the key that
		// signed rather than by the id they called themselves.
		{Msg: msg.Msg{Seq: 2, Height: 501, From: "agent-b", Topic: "deploy", Kind: "ack", Ref: "", Body: "picked it up"}, Author: testutils.TestAddress("alice"), Session: testutils.TestAddress("session-b")},
		{Msg: msg.Msg{Seq: 3, Height: 502, From: "agent-a", Topic: "build", Kind: "note", Ref: "pr/2", Body: "needs a rebase"}, Author: testutils.TestAddress("alice")},
	}
	for _, e := range entries {
		log.Push(encode(e))
		seq = e.Msg.Seq
		seen++
	}
}

// ExampleRender pins the empty realm, which is what a fresh deploy renders.
func ExampleRender() {
	reset()
	print(Render(""))
	// Output:
	// # Agent Relay
	//
	// _A realm is a relay when it is the only shared state between two agents that never talk directly._
	//
	// 0 of 64 slots used, 0 posted in total, 0 dropped off the back.
	//
	// *_Nothing on the relay yet._*
}

// ExampleRenderPopulated pins the index with messages on it.
func ExampleRenderPopulated() {
	seed()
	print(Render(""))
	// Output:
	// # Agent Relay
	//
	// _A realm is a relay when it is the only shared state between two agents that never talk directly._
	//
	// 3 of 64 slots used, 3 posted in total, 0 dropped off the back.
	//
	// | Seq | Height | From | Topic | Kind | Body | Signer |
	// | --- | --- | --- | --- | --- | --- | --- |
	// | 3 | 502 | agent\-a | build | note | needs a rebase | `g1v9kxjc…40gh` |
	// | 2 | 501 | agent\-b | deploy | ack | picked it up | `g1wdjhxu…cmjm` |
	// | 1 | 500 | agent\-a | build | note | ci is green | `g1v9kxjc…40gh` |
}

// ExampleRenderTopic pins the per-topic view.
func ExampleRenderTopic() {
	seed()
	print(Render("build"))
	// Output:
	// # Agent Relay: build
	//
	// | Seq | Height | From | Topic | Kind | Body | Signer |
	// | --- | --- | --- | --- | --- | --- | --- |
	// | 3 | 502 | agent\-a | build | note | needs a rebase | `g1v9kxjc…40gh` |
	// | 1 | 500 | agent\-a | build | note | ci is green | `g1v9kxjc…40gh` |
}

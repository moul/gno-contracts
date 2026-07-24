package life

import (
	"testing"
)

func TestBlinker(t *testing.T) {
	initBoard(7, 7)
	// Horizontal blinker centred at (3,3)
	SetCell(2, 3, true)
	SetCell(3, 3, true)
	SetCell(4, 3, true)

	if population != 3 {
		t.Errorf("initial population: want 3, got %d", population)
	}

	Step()

	// Step 1: vertical at (3,2),(3,3),(3,4)
	if !alive(3, 2) {
		t.Error("want (3,2) alive after step 1")
	}
	if !alive(3, 3) {
		t.Error("want (3,3) alive after step 1")
	}
	if !alive(3, 4) {
		t.Error("want (3,4) alive after step 1")
	}
	if alive(2, 3) || alive(4, 3) {
		t.Error("want (2,3) and (4,3) dead after step 1")
	}
	if population != 3 {
		t.Errorf("population after step 1: want 3, got %d", population)
	}

	Step()

	// Step 2: horizontal again
	if !alive(2, 3) || !alive(3, 3) || !alive(4, 3) {
		t.Error("want horizontal blinker after step 2")
	}
	if alive(3, 2) || alive(3, 4) {
		t.Error("want (3,2) and (3,4) dead after step 2")
	}
	if generation != 2 {
		t.Errorf("generation: want 2, got %d", generation)
	}
}

func TestBlockStillLife(t *testing.T) {
	initBoard(6, 6)
	// 2×2 block at (2,2)
	SetCell(2, 2, true)
	SetCell(3, 2, true)
	SetCell(2, 3, true)
	SetCell(3, 3, true)

	for i := 0; i < 5; i++ {
		Step()
		if population != 4 {
			t.Errorf("step %d: block changed, population=%d", i+1, population)
		}
		if !alive(2, 2) || !alive(3, 2) || !alive(2, 3) || !alive(3, 3) {
			t.Errorf("step %d: block cell died", i+1)
		}
	}
}

func TestGliderSurvives(t *testing.T) {
	initBoard(20, 20)
	LoadPreset("glider")

	if population != 5 {
		t.Errorf("glider initial population: want 5, got %d", population)
	}

	// A glider has period 4 and shifts (1,1) every 4 steps; it should
	// survive many generations on a large-enough board.
	for i := 0; i < 20; i++ {
		Step()
	}
	if population != 5 {
		t.Errorf("glider after 20 steps: want population 5, got %d", population)
	}
	if generation != 20 {
		t.Errorf("generation: want 20, got %d", generation)
	}
}

func TestSetCell(t *testing.T) {
	initBoard(5, 5)

	SetCell(2, 2, true)
	if !alive(2, 2) {
		t.Error("want (2,2) alive after SetCell true")
	}
	if population != 1 {
		t.Errorf("population: want 1, got %d", population)
	}

	SetCell(2, 2, false)
	if alive(2, 2) {
		t.Error("want (2,2) dead after SetCell false")
	}
	if population != 0 {
		t.Errorf("population: want 0, got %d", population)
	}

	// Out-of-bounds should be a no-op
	SetCell(100, 100, true)
	if population != 0 {
		t.Error("out-of-bounds SetCell must not change population")
	}
}

func TestReset(t *testing.T) {
	initBoard(10, 10)
	LoadPreset("block")

	if population == 0 {
		t.Error("want non-zero population after loading block preset")
	}

	Reset(5, 5)

	if population != 0 {
		t.Errorf("want 0 population after reset, got %d", population)
	}
	if generation != 0 {
		t.Errorf("want 0 generation after reset, got %d", generation)
	}
	if width != 5 || height != 5 {
		t.Errorf("want 5×5 board after reset, got %d×%d", width, height)
	}
}

func TestCountNeighbors(t *testing.T) {
	initBoard(5, 5)
	// Live cells at (1,1),(2,1),(3,1) — blinker
	SetCell(1, 1, true)
	SetCell(2, 1, true)
	SetCell(3, 1, true)

	// Centre cell (2,1) has 2 live neighbours: (1,1) and (3,1)
	if n := countNeighbors(2, 1); n != 2 {
		t.Errorf("center of blinker: want 2 neighbours, got %d", n)
	}
	// Cell below center (2,2) has 3 live neighbours
	if n := countNeighbors(2, 2); n != 3 {
		t.Errorf("cell below center: want 3 neighbours, got %d", n)
	}
}

func TestMultiStep(t *testing.T) {
	initBoard(20, 20)
	LoadPreset("glider")

	MultiStep(4)

	if generation != 4 {
		t.Errorf("generation after MultiStep(4): want 4, got %d", generation)
	}
	if population != 5 {
		t.Errorf("glider population after 4 steps: want 5, got %d", population)
	}
}

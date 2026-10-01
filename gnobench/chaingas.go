package main

import (
	vm "github.com/gnolang/gno/gno.land/pkg/sdk/vm"
	types "github.com/gnolang/gno/tm2/pkg/store/types"
)

// What the chain charges for storage I/O, as opposed to what the VM charges
// for interpreting gno.
//
// Every number this suite printed before now came from the VM's gas meter: the
// cost of executing opcodes. That is the minority half. A deployed chain also
// charges at the store boundary, per key read and per key written, and for the
// containers measured here that half is the larger one.
//
// The config is not transcribed, it is the chain's own: tm2's defaults with
// gno.land's genesis vm params applied on top, exactly as
// `gno.land/pkg/gnoland/app.go` builds it. Transcribing the constants would
// make this file quietly wrong the first time upstream repriced anything.
func chainGasConfig() types.GasConfig {
	cfg := types.DefaultGasConfig()
	vm.DefaultParams().ApplyToGasConfig(&cfg)
	return cfg
}

// chainStoreGas converts the counters countStore collects into the gas a
// deployed chain would charge for the same I/O.
//
// The formulas are `tm2/pkg/store/cache/store.go`, the depth-store branches of
// Get, Set and Delete:
//
//	GET    (depth_get   /100) * ReadCostFlat  + ReadCostPerByte  * len(value)
//	SET    (depth_setrd /100) * ReadCostFlat
//	     + (depth_write /100) * WriteCostFlat + WriteCostPerByte * len(value)
//	DELETE (depth_setrd /100) * ReadCostFlat  + (depth_write/100) * WriteCostFlat
//
// Why counting at the flush boundary gives the same answer as charging at the
// cache, which is where the chain actually charges:
//
//   - Reads: countStore sits BELOW the cache, so it observes misses only, and a
//     cache hit costs no gas. The two surfaces see the same events.
//   - Writes: the chain refunds the previous charge on every repeat Set to a
//     key, so a transaction pays once per distinct key, for the final value.
//     The flush emits exactly one Set per dirty key, carrying that final value.
//
// Both halves of that are asserted in TestChainStoreGasMatchesCacheCharging.
func chainStoreGas(cfg types.GasConfig, gets, getBytes, sets, setBytes, dels int64) int64 {
	readFlat := cfg.FixedGetReadDepth100 * int64(cfg.ReadCostFlat) / 100
	setRead := cfg.FixedSetReadDepth100 * int64(cfg.ReadCostFlat) / 100
	writeFlat := cfg.FixedWriteDepth100 * int64(cfg.WriteCostFlat) / 100

	g := gets*readFlat + getBytes*int64(cfg.ReadCostPerByte)
	s := sets*(setRead+writeFlat) + setBytes*int64(cfg.WriteCostPerByte)
	d := dels * (setRead + writeFlat)
	return g + s + d
}

// ChainGas is what a deployed chain would charge this row for storage I/O,
// derived rather than stored: storing it would freeze a gas schedule that
// governance can and does reprice, and old result files would then disagree
// with current main for no visible reason. Zero when the row carries no
// counters, which is every suite but `wiring`.
func (r Row) ChainGas(cfg types.GasConfig) int64 {
	if r.KVSets == 0 && r.KVGets == 0 && r.KVDels == 0 {
		return 0
	}
	return chainStoreGas(cfg, r.KVGets, r.KVGetBytes, r.KVSets, r.KVSetBytes, r.KVDels)
}

// DChainGas prices the baseline-subtracted counters: the I/O of the measured
// operation alone, with building the container taken back out.
func (r Row) DChainGas(cfg types.GasConfig) int64 {
	if r.DKVSets == 0 && r.DKVGets == 0 && r.DKVDels == 0 {
		return 0
	}
	return chainStoreGas(cfg, r.DKVGets, r.DKVGetBytes, r.DKVSets, r.DKVSetBytes, r.DKVDels)
}

// Package gns implements GNS (Gno Name Service): an ENS-equivalent naming
// system expressed as a single Gno-native realm.
//
// The design goal is NOT byte-for-byte ENS compatibility. Instead it provides
// the same user-facing capabilities (registration, renewal, expiry/grace,
// forward & reverse resolution, primary names, typed + arbitrary records,
// subnames with policies, delegated operators, pagination and
// events) through ONE realm, ONE ownership model, ONE record model, ONE
// authorization function and ONE registration lifecycle.
//
// Key deviations from a naive port of the spec, forced by gno semantics:
//
//   - State-mutating exported functions are "crossing" functions: they take
//     `cur realm` as the first parameter and PANIC (abort) on failure rather
//     than returning an error, because in gno only a panic/abort reverts state.
//     Failures panic with a stable machine-readable code (see the error_* set).
//   - Persistent, enumerable collections use avl.Tree (ordered, paginatable)
//     instead of Go maps, so every listing API is bounded and cursor-based.
//   - Names are stored string-native (canonical "label.parent"), not namehashed.
//
// See README.md for the full compatibility statement.
package gns

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strconv"
	"strings"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"
)

// ---------------------------------------------------------------------------
// 2. Constants
// ---------------------------------------------------------------------------

const (
	maxLabelLen = 63
	maxNameLen  = 255
	maxDepth    = 16

	sep = "|" // index-key separator; never appears in names or bech32 addresses
)

// Registration-policy modes.
const (
	ModeClosed    = "closed"
	ModeOwner     = "owner"
	ModeOpen      = "open"
	ModeAllowlist = "allowlist"
	ModePaid      = "paid"
)

// Reserved record namespaces (cannot be used by the generic SetRecord API).
var reservedNamespaces = map[string]bool{
	"gno": true, "addr": true, "text": true, "content": true,
	"abi": true, "interface": true, "system": true,
}

// Stable machine-readable error codes. Messages MAY add context, but client
// logic should depend on these codes.
var (
	errInvalidName        = errors.New("invalid_name")
	errInvalidLabel       = errors.New("invalid_label")
	errNameUnavailable    = errors.New("name_unavailable")
	errNameReserved       = errors.New("name_reserved")
	errNameExpired        = errors.New("name_expired")
	errNameInGrace        = errors.New("name_in_grace")
	errUnauthorized       = errors.New("unauthorized")
	errCommitmentMissing  = errors.New("commitment_missing")
	errCommitmentTooNew   = errors.New("commitment_too_new")
	errCommitmentExpired  = errors.New("commitment_expired")
	errCommitmentMismatch = errors.New("commitment_mismatch")
	errPriceChanged       = errors.New("price_changed")
	errInsufficientPay    = errors.New("insufficient_payment")
	errDurationTooShort   = errors.New("duration_too_short")
	errDurationTooLong    = errors.New("duration_too_long")
	errRecordTooLarge     = errors.New("record_too_large")
	errRecordLimit        = errors.New("record_limit_reached")
	errOperatorLimit      = errors.New("operator_limit_reached")
	errPolicyLocked       = errors.New("policy_locked")
	errParentInvalid      = errors.New("parent_invalid")
	errPaused             = errors.New("paused")
	errNotFound           = errors.New("not_found")
	errNotUser            = errors.New("not_user")
	errSpoofedRealm       = errors.New("spoofed_realm")
	errEmptyAddress       = errors.New("empty_address")
	errRegistrationClosed = errors.New("registration_closed")
	errBadRequest         = errors.New("bad_request")
)

// ---------------------------------------------------------------------------
// 3. Public types
// ---------------------------------------------------------------------------

// Permission enumerates the delegable operator capabilities.
type Permission int

const (
	PermManageRecords Permission = iota
	PermManageOperators
	PermManageSubnames
	PermRenew
	PermTransfer
	PermManagePolicy
)

// Permissions is an operator grant. ExpiresAt == 0 means no expiry.
type Permissions struct {
	ManageRecords   bool
	ManageOperators bool
	ManageSubnames  bool
	Renew           bool
	Transfer        bool
	ManagePolicy    bool
	ExpiresAt       int64
}

func (p Permissions) has(perm Permission) bool {
	switch perm {
	case PermManageRecords:
		return p.ManageRecords
	case PermManageOperators:
		return p.ManageOperators
	case PermManageSubnames:
		return p.ManageSubnames
	case PermRenew:
		return p.Renew
	case PermTransfer:
		return p.Transfer
	case PermManagePolicy:
		return p.ManagePolicy
	}
	return false
}

// ControlPolicy holds the explicit, readable ownership/parent control flags
// that replace ENS Name Wrapper fuses.
type ControlPolicy struct {
	OwnerCanTransfer       bool
	OwnerCanCreateSubnames bool
	RecordsMutable         bool

	ParentCanReclaim      bool
	ParentCanTransfer     bool
	ParentCanDelete       bool
	ParentCanChangePolicy bool

	// Permanent means the policy can only become MORE restrictive. It does not
	// make records immutable by itself.
	Permanent bool
}

// RegistrationPolicy governs how subnames of a name may be created. The
// realm-global config drives second-level registration.
type RegistrationPolicy struct {
	Mode string // closed | owner | open | allowlist | paid

	MinDuration int64
	MaxDuration int64

	PricePerSecond int64
	PaymentDenom   string

	Allowlist *avl.Tree // address string -> bool

	DefaultControlPolicy ControlPolicy
}

// Records is the built-in resolver state for a single name.
type Records struct {
	NativeAddress string
	ContentHash   []byte
	PublicKey     []byte

	Addresses  *avl.Tree // coinType (decimal string) -> []byte
	Text       *avl.Tree // key -> string
	ABIs       *avl.Tree // contentType -> []byte
	Interfaces *avl.Tree // interfaceID -> string
	Arbitrary  *avl.Tree // "namespace/key" -> []byte

	Count int // number of stored entries, for MaxRecordsPerName enforcement
}

func newRecords() *Records {
	return &Records{
		Addresses:  avl.NewTree(),
		Text:       avl.NewTree(),
		ABIs:       avl.NewTree(),
		Interfaces: avl.NewTree(),
		Arbitrary:  avl.NewTree(),
	}
}

// Name is the single object the whole realm operates on.
type Name struct {
	Canonical string
	Owner     address

	CreatedAt   int64
	UpdatedAt   int64
	ExpiresAt   int64 // 0 == permanent subname (follows parent validity)
	GraceEndsAt int64

	Parent string
	Label  string
	Depth  uint8

	TTL uint64

	Generation       uint64
	ParentGeneration uint64

	RegistrationPolicy RegistrationPolicy
	ControlPolicy      ControlPolicy

	Records *Records

	Operators     *avl.Tree // address string -> Permissions
	OperatorCount int

	Revision uint64
	Reserved bool
	Deleted  bool
}

// NameView is the read-only projection returned by GetName.
type NameView struct {
	Canonical   string
	Owner       string
	Status      string
	CreatedAt   int64
	UpdatedAt   int64
	ExpiresAt   int64
	GraceEndsAt int64
	Parent      string
	Label       string
	Depth       uint8
	TTL         uint64
	Generation  uint64
	Revision    uint64
	Reserved    bool
	NativeAddr  string
}

// Config is the realm-global configuration.
type Config struct {
	Admin        address
	PendingAdmin address

	RegistrationOpen bool

	MinCommitAge int64
	MaxCommitAge int64

	MinRegistrationDuration int64
	MaxRegistrationDuration int64

	GracePeriod int64

	BasePricePerSecond int64
	PremiumByLength    map[uint8]int64

	PaymentDenom string
	Treasury     address

	MaxTextValueBytes   uint32
	MaxBinaryValueBytes uint32
	MaxRecordsPerName   uint16
	MaxOperatorsPerName uint16

	PolicyRevision uint64 // bumped whenever pricing/registration rules change
	Paused         bool
}

// PricingConfig is the admin-settable pricing surface.
type PricingConfig struct {
	BasePricePerSecond int64
	PremiumByLength    map[uint8]int64
	PaymentDenom       string
}

// PriceQuote is returned by Price.
type PriceQuote struct {
	Amount     int64
	Denom      string
	ValidUntil int64
	Revision   uint64
}

// RegisterRequest is the reveal payload for Register.
//
// The commitment the client submits via Commit MUST equal
// sha256hex(Name|Owner|Duration|Secret|RecordsHash|PolicyRevision) using the
// same field values. RecordsHash is an opaque client-computed hex digest of
// the intended initial records; it binds the reveal so a front-runner cannot
// change records. NativeAddress/SetPrimary are optional conveniences applied
// after creation.
type RegisterRequest struct {
	Name           string
	Owner          address
	Duration       int64
	Secret         string
	RecordsHash    string
	PolicyRevision uint64

	NativeAddress string
	SetPrimary    bool
}

// RegistrationResult is returned by Register.
type RegistrationResult struct {
	Canonical  string
	Owner      string
	ExpiresAt  int64
	Generation uint64
	Paid       int64
	Refunded   int64
}

// RenewalResult is returned by Renew.
type RenewalResult struct {
	Canonical string
	ExpiresAt int64
	Paid      int64
}

// SubnameOptions configures CreateSubname.
type SubnameOptions struct {
	Duration      int64 // 0 == permanent (follows parent)
	ControlPolicy ControlPolicy
	NativeAddress string
}

// RecordQuery selects which record Resolve should return.
type RecordQuery struct {
	Kind string // "address" | "text" | "coin" | "content" | "pubkey" | "abi" | "interface" | "record"
	Key1 string // text key / coin type / abi content type / interface id / namespace
	Key2 string // arbitrary record key (with namespace in Key1)
}

// ResolveMode selects exact vs inherited resolution.
type ResolveMode int

const (
	Exact ResolveMode = iota
	NearestAncestor
)

// ResolveResult is returned by Resolve.
type ResolveResult struct {
	Found      bool
	Requested  string
	SourceName string
	Value      []byte
	Revision   uint64
	ExpiresAt  int64
}

// Event is an append-only change record for indexers.
type Event struct {
	ID        uint64
	Height    int64
	Timestamp int64

	Type string
	Name string

	Actor  string
	Owner  string
	Target string

	Revision uint64

	Key       string
	OldDigest string
	NewDigest string
}

// Event types.
const (
	EvNameRegistered    = "NameRegistered"
	EvNameRenewed       = "NameRenewed"
	EvNameTransferred   = "NameTransferred"
	EvNameExpired       = "NameExpired"
	EvNameDeleted       = "NameDeleted"
	EvSubnameCreated    = "SubnameCreated"
	EvPolicyChanged     = "PolicyChanged"
	EvOperatorChanged   = "OperatorChanged"
	EvRecordChanged     = "RecordChanged"
	EvPrimaryNameChange = "PrimaryNameChanged"
	EvConfigChanged     = "ConfigChanged"
	EvPaused            = "Paused"
	EvUnpaused          = "Unpaused"
)

// Paged result types (gno avoids generics; concrete types keep it simple).
type StringPage struct {
	Items []string
	Next  string
}

type OperatorView struct {
	Address     string
	Permissions Permissions
}

type OperatorPage struct {
	Items []OperatorView
	Next  string
}

type EventPage struct {
	Items []Event
	Next  string
}

// NameStatus mirrors the lifecycle states.
type NameStatus string

const (
	StatusAvailable NameStatus = "Available"
	StatusCommitted NameStatus = "Committed"
	StatusActive    NameStatus = "Active"
	StatusGrace     NameStatus = "Grace"
	StatusExpired   NameStatus = "Expired"
	StatusDeleted   NameStatus = "Deleted"
	StatusReserved  NameStatus = "Reserved"
)

// CommitmentView is the read projection of a pending commitment.
type CommitmentView struct {
	Exists    bool
	Committer string
	CreatedAt int64
	ReadyAt   int64
	ExpiresAt int64
}

// commitment is the stored commit record.
type commitment struct {
	Committer address
	CreatedAt int64
}

// ---------------------------------------------------------------------------
// 4. Persistent state
// ---------------------------------------------------------------------------

var (
	config      Config
	names       = avl.NewTree() // canonical -> *Name
	commitments = avl.NewTree() // commitment hex -> *commitment
	reverse     = avl.NewTree() // address string -> canonical (primary name)
	events      = avl.NewTree() // zero-padded id -> *Event
	byOwner     = avl.NewTree() // "owner|canonical" -> canonical
	byParent    = avl.NewTree() // "parent|canonical" -> canonical
	nextEventID uint64
)

// ---------------------------------------------------------------------------
// 5. Initialization
// ---------------------------------------------------------------------------

func init() {
	deployer := unsafe.OriginCaller()
	config = Config{
		Admin:            deployer,
		RegistrationOpen: true,

		MinCommitAge: 60,        // 1 minute
		MaxCommitAge: 24 * 3600, // 1 day

		MinRegistrationDuration: 28 * 24 * 3600,       // 28 days
		MaxRegistrationDuration: 10 * 365 * 24 * 3600, // 10 years

		GracePeriod: 90 * 24 * 3600, // 90 days

		BasePricePerSecond: 1, // 1 ugnot / second (deterministic, boring)
		PremiumByLength: map[uint8]int64{
			1: 100,
			2: 25,
			3: 5,
			4: 2,
		},

		PaymentDenom: "ugnot",
		Treasury:     deployer,

		MaxTextValueBytes:   4096,
		MaxBinaryValueBytes: 8192,
		MaxRecordsPerName:   128,
		MaxOperatorsPerName: 32,

		PolicyRevision: 1,
		Paused:         false,
	}
}

// ---------------------------------------------------------------------------
// 6. Normalization
// ---------------------------------------------------------------------------

// Normalize canonicalizes a name: lowercases ASCII, validates every label, and
// enforces length/depth limits. Non-ASCII input is rejected outright.
func Normalize(name string) (string, error) {
	if name == "" {
		return "", errInvalidName
	}
	if len(name) > maxNameLen {
		return "", errInvalidName
	}
	lower := strings.ToLower(name)
	// reject non-ASCII (ToLower only folds ASCII deterministically for us; any
	// byte >= 0x80 is disallowed)
	for i := 0; i < len(lower); i++ {
		if lower[i] >= 0x80 {
			return "", errInvalidName
		}
	}
	labels := strings.Split(lower, ".")
	if len(labels) > maxDepth {
		return "", errInvalidName
	}
	for _, l := range labels {
		if err := validateLabel(l); err != nil {
			return "", err
		}
	}
	return lower, nil
}

func validateLabel(l string) error {
	n := len(l)
	if n < 1 || n > maxLabelLen {
		return errInvalidLabel
	}
	for i := 0; i < n; i++ {
		c := l[i]
		isDigit := c >= '0' && c <= '9'
		isAlpha := c >= 'a' && c <= 'z'
		isHyphen := c == '-'
		if !isDigit && !isAlpha && !isHyphen {
			return errInvalidLabel
		}
		if isHyphen && (i == 0 || i == n-1) {
			return errInvalidLabel // no leading/trailing hyphen
		}
	}
	return nil
}

func mustNormalize(name string) string {
	c, err := Normalize(name)
	if err != nil {
		panic(err)
	}
	return c
}

// splitLabel returns (label, parent) for a canonical name.
func splitLabel(canonical string) (string, string) {
	i := strings.Index(canonical, ".")
	if i < 0 {
		return canonical, ""
	}
	return canonical[:i], canonical[i+1:]
}

func depthOf(canonical string) uint8 {
	return uint8(strings.Count(canonical, ".") + 1)
}

// ---------------------------------------------------------------------------
// 7. Hashing
// ---------------------------------------------------------------------------

// MakeCommitment is the public helper clients use to derive the commitment
// hex to pass to Commit. It normalizes the name first so the value matches what
// Register recomputes at reveal. Returns an error if the name is invalid.
func MakeCommitment(name string, owner address, duration int64, secret, recordsHash string, policyRevision uint64) (string, error) {
	canonical, err := Normalize(name)
	if err != nil {
		return "", err
	}
	return computeCommitment(canonical, owner, duration, secret, recordsHash, policyRevision), nil
}

// computeCommitment derives the canonical commitment hex string. Clients MUST
// compute it identically (see RegisterRequest docs).
func computeCommitment(name string, owner address, duration int64, secret, recordsHash string, policyRev uint64) string {
	preimage := name + sep + owner.String() + sep + strconv.FormatInt(duration, 10) + sep + secret + sep + recordsHash + sep + strconv.FormatUint(policyRev, 10)
	sum := sha256.Sum256([]byte(preimage))
	return hex.EncodeToString(sum[:])
}

// digest returns a short hex digest of a byte value, for event payloads (never
// store full record values in events).
func digest(b []byte) string {
	if len(b) == 0 {
		return ""
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])[:16]
}

func digestStr(s string) string { return digest([]byte(s)) }

// ---------------------------------------------------------------------------
// 8. Time and lifecycle
// ---------------------------------------------------------------------------

func now() int64    { return time.Now().Unix() }
func height() int64 { return runtime.ChainHeight() }

// statusOf computes the lifecycle status of a (possibly nil) name.
func statusOf(n *Name) NameStatus {
	if n == nil {
		return StatusAvailable
	}
	if n.Deleted {
		return StatusDeleted
	}
	if n.Reserved && n.Owner == (address("")) {
		return StatusReserved
	}
	if !parentChainValid(n) {
		return StatusExpired
	}
	t := now()
	if n.ExpiresAt == 0 { // permanent subname; valid while ancestors valid
		return StatusActive
	}
	if t < n.ExpiresAt {
		return StatusActive
	}
	if t < n.GraceEndsAt {
		return StatusGrace
	}
	return StatusExpired
}

func isActive(n *Name) bool { return statusOf(n) == StatusActive }

// parentChainValid verifies every ancestor exists, is active, and matches the
// stored ParentGeneration (recycling safety, invariant 16 & recycling).
func parentChainValid(n *Name) bool {
	if n.Parent == "" {
		return true
	}
	p := getRaw(n.Parent)
	if p == nil || p.Deleted {
		return false
	}
	if n.ParentGeneration != p.Generation {
		return false
	}
	// parent must itself be active (not grace/expired) and its own chain valid
	if p.ExpiresAt != 0 {
		t := now()
		if t >= p.ExpiresAt {
			return false
		}
	}
	return parentChainValid(p)
}

// available reports whether a name may be registered now.
func available(canonical string) bool {
	n := getRaw(canonical)
	if n == nil {
		return true
	}
	if n.Reserved {
		return false
	}
	switch statusOf(n) {
	case StatusExpired, StatusDeleted:
		return true
	default:
		return false
	}
}

// ---------------------------------------------------------------------------
// 9. Pricing
// ---------------------------------------------------------------------------

func lengthMultiplier(label string) int64 {
	l := uint8(len(label))
	if m, ok := config.PremiumByLength[l]; ok {
		return m
	}
	return 1
}

// priceFor computes the deterministic, overflow-checked price.
func priceFor(canonical string, duration int64) (int64, error) {
	if duration <= 0 {
		return 0, errDurationTooShort
	}
	label, _ := splitLabel(canonical)
	mult := lengthMultiplier(label)
	base := config.BasePricePerSecond
	// price = duration * base * mult, checked for overflow at each step.
	p := duration
	var err error
	if p, err = mulChecked(p, base); err != nil {
		return 0, err
	}
	if p, err = mulChecked(p, mult); err != nil {
		return 0, err
	}
	return p, nil
}

func mulChecked(a, b int64) (int64, error) {
	if a == 0 || b == 0 {
		return 0, nil
	}
	c := a * b
	if c/b != a || c < 0 {
		return 0, errRecordTooLarge // reuse as overflow marker; documented
	}
	return c, nil
}

// Price returns a price quote for registering/renewing name for duration.
func Price(name string, duration int64) (PriceQuote, error) {
	canonical, err := Normalize(name)
	if err != nil {
		return PriceQuote{}, err
	}
	amt, err := priceFor(canonical, duration)
	if err != nil {
		return PriceQuote{}, err
	}
	return PriceQuote{
		Amount:     amt,
		Denom:      config.PaymentDenom,
		ValidUntil: now() + config.MaxCommitAge,
		Revision:   config.PolicyRevision,
	}, nil
}

// ---------------------------------------------------------------------------
// 10. Authorization
// ---------------------------------------------------------------------------

// caller authenticates a crossing frame and returns the immediate caller.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic(errSpoofedRealm)
	}
	return cur.Previous().Address()
}

// callerUser authenticates and requires an end-user (EOA) caller.
func callerUser(cur realm) address {
	if !cur.IsCurrent() {
		panic(errSpoofedRealm)
	}
	prev := cur.Previous()
	if !prev.IsUser() {
		panic(errNotUser)
	}
	return prev.Address()
}

// authorize is the single gate for all name mutations. Authority order:
//  1. admin — NOT here (admin has no routine power over user names);
//  2. direct owner of an active name;
//  3. active operator with the matching permission;
//  4. parent authority, when the child policy allows.
func authorize(callerAddr address, n *Name, perm Permission) error {
	if n == nil {
		return errNotFound
	}
	// (2) direct owner, but only while active (invariant 2).
	if n.Owner == callerAddr && isActive(n) {
		return nil
	}
	// (3) operator
	if op, ok := getOperator(n, callerAddr); ok && isActive(n) {
		if op.has(perm) && (op.ExpiresAt == 0 || op.ExpiresAt > now()) {
			return nil
		}
	}
	// (4) parent authority
	if parentAuthorized(callerAddr, n, perm) {
		return nil
	}
	return errUnauthorized
}

func mustAuthorize(callerAddr address, n *Name, perm Permission) {
	if err := authorize(callerAddr, n, perm); err != nil {
		panic(err)
	}
}

// parentAuthorized checks whether callerAddr controls the parent AND the
// child's policy grants the parent that specific power.
func parentAuthorized(callerAddr address, n *Name, perm Permission) bool {
	if n.Parent == "" {
		return false
	}
	p := getRaw(n.Parent)
	if p == nil || !isActive(p) {
		return false
	}
	// caller must control the parent (owner or ManageSubnames operator)
	controls := p.Owner == callerAddr
	if !controls {
		if op, ok := getOperator(p, callerAddr); ok && op.ManageSubnames {
			controls = true
		}
	}
	if !controls {
		return false
	}
	cp := n.ControlPolicy
	switch perm {
	case PermTransfer:
		return cp.ParentCanTransfer || cp.ParentCanReclaim
	case PermManagePolicy:
		return cp.ParentCanChangePolicy
	}
	return false
}

// ---------------------------------------------------------------------------
// 11. Registration
// ---------------------------------------------------------------------------

// Commit stores a registration commitment. The commitment hides the intended
// name; only its hash is recorded together with the committer and timestamp.
func Commit(cur realm, commit string) {
	requireNotPaused()
	c := callerUser(cur)
	if commit == "" {
		panic(errBadRequest)
	}
	if existing, ok := getCommitment(commit); ok {
		// reject only if the existing commitment is still within its usable
		// window; stale ones may be overwritten.
		if now()-existing.CreatedAt <= config.MaxCommitAge {
			panic(errCommitmentMismatch)
		}
	}
	commitments.Set(commit, &commitment{Committer: c, CreatedAt: now()})
}

// Register reveals and consumes a commitment to create a second-level name.
func Register(cur realm, request RegisterRequest) RegistrationResult {
	requireNotPaused()
	c := callerUser(cur)

	if !config.RegistrationOpen {
		panic(errRegistrationClosed)
	}
	canonical, err := Normalize(request.Name)
	if err != nil {
		panic(err)
	}
	// second-level only (no dots) via Register; subnames use CreateSubname.
	if strings.Contains(canonical, ".") {
		panic(errInvalidName)
	}
	if request.PolicyRevision != config.PolicyRevision {
		panic(errPriceChanged)
	}
	if !request.Owner.IsValid() {
		panic(errEmptyAddress)
	}

	// commitment checks
	key := computeCommitment(canonical, request.Owner, request.Duration, request.Secret, request.RecordsHash, request.PolicyRevision)
	cm, ok := getCommitment(key)
	if !ok {
		panic(errCommitmentMissing)
	}
	if cm.Committer != c {
		panic(errUnauthorized)
	}
	age := now() - cm.CreatedAt
	if age < config.MinCommitAge {
		panic(errCommitmentTooNew)
	}
	if age > config.MaxCommitAge {
		panic(errCommitmentExpired)
	}

	// availability + duration
	if !available(canonical) {
		existing := getRaw(canonical)
		switch statusOf(existing) {
		case StatusReserved:
			panic(errNameReserved)
		case StatusGrace:
			panic(errNameInGrace)
		default:
			panic(errNameUnavailable)
		}
	}
	if request.Duration < config.MinRegistrationDuration {
		panic(errDurationTooShort)
	}
	if request.Duration > config.MaxRegistrationDuration {
		panic(errDurationTooLong)
	}

	price, err := priceFor(canonical, request.Duration)
	if err != nil {
		panic(err)
	}
	paid, refunded := collectPayment(cur, price)

	// build/recycle the name
	prev := getRaw(canonical)
	var gen uint64 = 1
	if prev != nil {
		gen = prev.Generation + 1 // recycle: increment generation
	}
	t := now()
	label, parent := splitLabel(canonical)
	n := &Name{
		Canonical:  canonical,
		Owner:      request.Owner,
		CreatedAt:  t,
		UpdatedAt:  t,
		ExpiresAt:  t + request.Duration,
		Parent:     parent,
		Label:      label,
		Depth:      depthOf(canonical),
		Generation: gen,
		Revision:   1,
		Records:    newRecords(),
		Operators:  avl.NewTree(),
		ControlPolicy: ControlPolicy{
			OwnerCanTransfer:       true,
			OwnerCanCreateSubnames: true,
			RecordsMutable:         true,
		},
		RegistrationPolicy: RegistrationPolicy{Mode: ModeClosed},
	}
	n.GraceEndsAt = n.ExpiresAt + config.GracePeriod

	// clear any stale owner index from a previous generation before storing.
	if prev != nil {
		byOwner.Remove(ownerKey(prev.Owner, canonical))
	}
	putName(n)

	// optional convenience records
	if request.NativeAddress != "" {
		setNativeAddressInternal(n, request.NativeAddress)
	}
	if request.SetPrimary && request.NativeAddress != "" && address(request.NativeAddress) == c {
		reverse.Set(c.String(), canonical)
		emit(EvPrimaryNameChange, canonical, c, n.Owner, "")
	}

	commitments.Remove(key)
	emitOwner(EvNameRegistered, n)

	return RegistrationResult{
		Canonical:  canonical,
		Owner:      n.Owner.String(),
		ExpiresAt:  n.ExpiresAt,
		Generation: n.Generation,
		Paid:       paid,
		Refunded:   refunded,
	}
}

// collectPayment reads the attached ugnot, requires it to cover price, and
// forwards price to the treasury while refunding any overpayment.
func collectPayment(cur realm, price int64) (paid, refunded int64) {
	if price <= 0 {
		return 0, 0
	}
	if !cur.Previous().IsUserCall() {
		panic(errNotUser)
	}
	sent := unsafe.OriginSend()
	got := sent.AmountOf(config.PaymentDenom)
	if got < price {
		panic(errInsufficientPay)
	}
	bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	self := cur.Address()
	// forward the price to the treasury
	if config.Treasury != self {
		bk.SendCoins(self, config.Treasury, coins(config.PaymentDenom, price))
	}
	// refund the remainder to the caller
	over := got - price
	if over > 0 {
		bk.SendCoins(self, cur.Previous().Address(), coins(config.PaymentDenom, over))
	}
	return price, over
}

// ---------------------------------------------------------------------------
// 12. Renewal and expiry
// ---------------------------------------------------------------------------

// Renew extends a name's expiry. Anyone may pay to renew (a socially useful
// property: third parties can prevent expiry but gain no authority). Renewal
// is allowed while Active or in Grace, never once fully Expired.
func Renew(cur realm, name string, duration int64) RenewalResult {
	requireNotPaused()
	_ = caller(cur) // authenticate frame; no authority needed to sponsor renewal
	canonical := mustNormalize(name)
	n := getRaw(canonical)
	if n == nil || n.Deleted {
		panic(errNotFound)
	}
	st := statusOf(n)
	if st != StatusActive && st != StatusGrace {
		panic(errNameExpired)
	}
	if n.ExpiresAt == 0 {
		panic(errBadRequest) // permanent subname has no independent expiry
	}
	if duration <= 0 {
		panic(errDurationTooShort)
	}

	// new expiry base: max(now, current expiry) so grace renewals extend from
	// the original expiry, active renewals from current expiry.
	base := n.ExpiresAt
	if st == StatusGrace {
		// during grace, extend from now to avoid free grace time abuse
		base = n.ExpiresAt
	}
	newExpiry := base + duration
	// enforce the maximum expiry horizon (invariant 11).
	maxHorizon := now() + config.MaxRegistrationDuration
	if newExpiry > maxHorizon {
		panic(errDurationTooLong)
	}

	price, err := priceFor(canonical, duration)
	if err != nil {
		panic(err)
	}
	paid, _ := collectPayment(cur, price)

	n.ExpiresAt = newExpiry
	n.GraceEndsAt = newExpiry + config.GracePeriod
	n.UpdatedAt = now()
	n.Revision++
	putName(n)
	emitOwner(EvNameRenewed, n)

	return RenewalResult{Canonical: canonical, ExpiresAt: n.ExpiresAt, Paid: paid}
}

// ---------------------------------------------------------------------------
// 13. Ownership
// ---------------------------------------------------------------------------

// Transfer moves ownership of a name.
func Transfer(cur realm, name string, newOwner address, clearOperators, clearRecords bool) {
	requireNotPaused()
	c := caller(cur)
	canonical := mustNormalize(name)
	n := getRaw(canonical)
	if n == nil {
		panic(errNotFound)
	}
	if !newOwner.IsValid() {
		panic(errEmptyAddress)
	}
	if newOwner == n.Owner {
		panic(errBadRequest) // self-transfer rejected (cleaner than no-op)
	}
	// owner path additionally requires the policy to allow transfer.
	if c == n.Owner && isActive(n) {
		if !n.ControlPolicy.OwnerCanTransfer {
			panic(errPolicyLocked)
		}
	} else {
		mustAuthorize(c, n, PermTransfer)
	}

	old := n.Owner
	byOwner.Remove(ownerKey(old, canonical))

	n.Owner = newOwner
	n.Revision++
	n.UpdatedAt = now()
	if clearOperators {
		n.Operators = avl.NewTree()
		n.OperatorCount = 0
	}
	if clearRecords {
		n.Records = newRecords()
	}
	putName(n)

	// invalidate reverse mappings that no longer pass forward verification.
	invalidateReverseFor(old, canonical)

	emit(EvNameTransferred, canonical, c, newOwner, old.String())
}

// ---------------------------------------------------------------------------
// 14. Subnames and policy
// ---------------------------------------------------------------------------

// CreateSubname creates label.parent according to the parent registration
// policy.
func CreateSubname(cur realm, parent string, label string, owner address, options SubnameOptions) {
	requireNotPaused()
	c := callerUser(cur)

	pcanon := mustNormalize(parent)
	if err := validateLabel(strings.ToLower(label)); err != nil {
		panic(err)
	}
	label = strings.ToLower(label)
	canonical := label + "." + pcanon
	if len(canonical) > maxNameLen {
		panic(errInvalidName)
	}
	if depthOf(canonical) > maxDepth {
		panic(errInvalidName)
	}

	p := getRaw(pcanon)
	if p == nil || !isActive(p) {
		panic(errParentInvalid)
	}
	if !owner.IsValid() {
		panic(errEmptyAddress)
	}
	if !available(canonical) {
		panic(errNameUnavailable)
	}

	pol := p.RegistrationPolicy
	// authorize + charge according to policy mode.
	switch pol.Mode {
	case ModeClosed, "":
		panic(errRegistrationClosed)
	case ModeOwner:
		mustAuthorize(c, p, PermManageSubnames)
	case ModeOpen:
		// anyone
	case ModeAllowlist:
		if pol.Allowlist == nil || !allowlistHas(pol.Allowlist, c) {
			panic(errUnauthorized)
		}
	case ModePaid:
		charge := int64(0)
		if pol.PricePerSecond > 0 && options.Duration > 0 {
			var err error
			if charge, err = mulChecked(pol.PricePerSecond, options.Duration); err != nil {
				panic(err)
			}
		}
		denom := pol.PaymentDenom
		if denom == "" {
			denom = config.PaymentDenom
		}
		collectPaymentDenom(cur, charge, denom, p.Owner)
	default:
		panic(errBadRequest)
	}

	t := now()
	prev := getRaw(canonical)
	var gen uint64 = 1
	if prev != nil {
		gen = prev.Generation + 1
		byOwner.Remove(ownerKey(prev.Owner, canonical))
	}
	cpol := options.ControlPolicy
	if (cpol == ControlPolicy{}) {
		cpol = pol.DefaultControlPolicy
	}
	n := &Name{
		Canonical:          canonical,
		Owner:              owner,
		CreatedAt:          t,
		UpdatedAt:          t,
		Parent:             pcanon,
		Label:              label,
		Depth:              depthOf(canonical),
		Generation:         gen,
		ParentGeneration:   p.Generation,
		Revision:           1,
		Records:            newRecords(),
		Operators:          avl.NewTree(),
		ControlPolicy:      cpol,
		RegistrationPolicy: RegistrationPolicy{Mode: ModeClosed},
	}
	if options.Duration > 0 {
		n.ExpiresAt = t + options.Duration
		n.GraceEndsAt = n.ExpiresAt + config.GracePeriod
	} // else permanent (ExpiresAt == 0)

	putName(n)
	if options.NativeAddress != "" {
		setNativeAddressInternal(n, options.NativeAddress)
	}
	emit(EvSubnameCreated, canonical, c, owner, pcanon)
}

// DeleteSubname removes a subname. Callable by the owner, or by the parent when
// ParentCanDelete is set.
func DeleteSubname(cur realm, name string) {
	requireNotPaused()
	c := caller(cur)
	canonical := mustNormalize(name)
	n := getRaw(canonical)
	if n == nil || n.Deleted {
		panic(errNotFound)
	}
	if n.Parent == "" {
		panic(errBadRequest) // not a subname
	}
	authorized := false
	if c == n.Owner && isActive(n) {
		authorized = true
	} else if p := getRaw(n.Parent); p != nil && isActive(p) && n.ControlPolicy.ParentCanDelete {
		if p.Owner == c {
			authorized = true
		} else if op, ok := getOperator(p, c); ok && op.ManageSubnames {
			authorized = true
		}
	}
	if !authorized {
		panic(errUnauthorized)
	}
	deleteName(n)
	emit(EvNameDeleted, canonical, c, n.Owner, "")
}

// SetRegistrationPolicy sets the subname-issuance policy for a name.
func SetRegistrationPolicy(cur realm, name string, policy RegistrationPolicy) {
	requireNotPaused()
	c := caller(cur)
	canonical := mustNormalize(name)
	n := getRaw(canonical)
	if n == nil {
		panic(errNotFound)
	}
	if c == n.Owner && isActive(n) {
		if !n.ControlPolicy.OwnerCanCreateSubnames && policy.Mode != ModeClosed {
			panic(errPolicyLocked)
		}
	} else {
		mustAuthorize(c, n, PermManagePolicy)
	}
	n.RegistrationPolicy = policy
	n.UpdatedAt = now()
	n.Revision++
	putName(n)
	emit(EvPolicyChanged, canonical, c, n.Owner, "registration")
}

// LockPolicy makes a name's control policy strictly more restrictive
// (emancipation). Flags may only move true->false; once Permanent, no field
// may be relaxed. Only the owner may lock.
func LockPolicy(cur realm, name string, restrictions ControlPolicy) {
	requireNotPaused()
	c := caller(cur)
	canonical := mustNormalize(name)
	n := getRaw(canonical)
	if n == nil {
		panic(errNotFound)
	}
	if c != n.Owner || !isActive(n) {
		panic(errUnauthorized)
	}
	cur0 := n.ControlPolicy
	if cur0.Permanent && !restrictions.Permanent {
		panic(errPolicyLocked)
	}
	next := mergeRestrictive(cur0, restrictions)
	n.ControlPolicy = next
	n.UpdatedAt = now()
	n.Revision++
	putName(n)
	emit(EvPolicyChanged, canonical, c, n.Owner, "control")
}

// mergeRestrictive returns a policy where each boolean can only go from
// permissive (true) to restrictive (false); Permanent can only be turned on.
func mergeRestrictive(cur, req ControlPolicy) ControlPolicy {
	andRestrict := func(cur, req bool) bool { return cur && req }
	return ControlPolicy{
		OwnerCanTransfer:       andRestrict(cur.OwnerCanTransfer, req.OwnerCanTransfer),
		OwnerCanCreateSubnames: andRestrict(cur.OwnerCanCreateSubnames, req.OwnerCanCreateSubnames),
		RecordsMutable:         andRestrict(cur.RecordsMutable, req.RecordsMutable),
		ParentCanReclaim:       andRestrict(cur.ParentCanReclaim, req.ParentCanReclaim),
		ParentCanTransfer:      andRestrict(cur.ParentCanTransfer, req.ParentCanTransfer),
		ParentCanDelete:        andRestrict(cur.ParentCanDelete, req.ParentCanDelete),
		ParentCanChangePolicy:  andRestrict(cur.ParentCanChangePolicy, req.ParentCanChangePolicy),
		Permanent:              cur.Permanent || req.Permanent,
	}
}

// SetOperator grants (or updates) an operator's permissions on a name.
func SetOperator(cur realm, name string, operator address, permissions Permissions) {
	requireNotPaused()
	c := caller(cur)
	canonical := mustNormalize(name)
	n := getRaw(canonical)
	if n == nil {
		panic(errNotFound)
	}
	mustAuthorizeOwnerOrOp(c, n, PermManageOperators)
	if !operator.IsValid() {
		panic(errEmptyAddress)
	}
	_, existed := getOperator(n, operator)
	if !existed {
		if int(config.MaxOperatorsPerName) > 0 && n.OperatorCount >= int(config.MaxOperatorsPerName) {
			panic(errOperatorLimit)
		}
		n.OperatorCount++
	}
	n.Operators.Set(operator.String(), permissions)
	n.UpdatedAt = now()
	n.Revision++
	putName(n)
	emit(EvOperatorChanged, canonical, c, operator, "set")
}

// RemoveOperator revokes an operator.
func RemoveOperator(cur realm, name string, operator address) {
	requireNotPaused()
	c := caller(cur)
	canonical := mustNormalize(name)
	n := getRaw(canonical)
	if n == nil {
		panic(errNotFound)
	}
	mustAuthorizeOwnerOrOp(c, n, PermManageOperators)
	if _, removed := n.Operators.Remove(operator.String()); removed {
		n.OperatorCount--
		n.UpdatedAt = now()
		n.Revision++
		putName(n)
		emit(EvOperatorChanged, canonical, c, operator, "remove")
	}
}

// mustAuthorizeOwnerOrOp allows the active owner directly or an operator with
// the given permission (used for record/operator management).
func mustAuthorizeOwnerOrOp(c address, n *Name, perm Permission) {
	if c == n.Owner && isActive(n) {
		return
	}
	if op, ok := getOperator(n, c); ok && isActive(n) && op.has(perm) && (op.ExpiresAt == 0 || op.ExpiresAt > now()) {
		return
	}
	panic(errUnauthorized)
}

// ---------------------------------------------------------------------------
// 15. Records
// ---------------------------------------------------------------------------

func requireRecordsMutable(n *Name) {
	if !n.ControlPolicy.RecordsMutable {
		panic(errPolicyLocked)
	}
	// records may not be mutated during grace (spec: normal updates disabled in
	// grace, except clearing reverse).
	if statusOf(n) != StatusActive {
		panic(errNameExpired)
	}
}

func bumpRecords(n *Name) {
	n.UpdatedAt = now()
	n.Revision++
	putName(n)
}

func (n *Name) recordCountGuard(added int) {
	if config.MaxRecordsPerName > 0 && n.Records.Count+added > int(config.MaxRecordsPerName) {
		panic(errRecordLimit)
	}
}

// recordMutation is the shared preamble for every typed record setter: pause
// gate, caller authentication, name resolution, record-management authority,
// and records-mutable check. Returns the name and the caller address.
func recordMutation(cur realm, name string) (*Name, address) {
	requireNotPaused()
	c := caller(cur)
	n := mustName(name)
	mustAuthorizeOwnerOrOp(c, n, PermManageRecords)
	requireRecordsMutable(n)
	return n, c
}

// SetAddress sets the native address record.
func SetAddress(cur realm, name string, addr string) {
	n, c := recordMutation(cur, name)
	if addr != "" && !address(addr).IsValid() {
		panic(errEmptyAddress)
	}
	setNativeAddressInternal(n, addr)
	bumpRecords(n)
	emitRecord(EvRecordChanged, n, c, "addr", digestStr(addr))
}

func setNativeAddressInternal(n *Name, addr string) {
	n.Records.NativeAddress = addr
}

// Address returns the native address record.
func Address(name string) (string, bool) {
	n := resolvableName(name)
	if n == nil || n.Records.NativeAddress == "" {
		return "", false
	}
	return n.Records.NativeAddress, true
}

// SetCoinAddress sets a multichain address for coinType (decimal string).
func SetCoinAddress(cur realm, name string, coinType string, value []byte) {
	n, c := recordMutation(cur, name)
	guardBinary(value)
	if !n.Records.Addresses.Has(coinType) {
		n.recordCountGuard(1)
		n.Records.Count++
	}
	n.Records.Addresses.Set(coinType, value)
	bumpRecords(n)
	emitRecord(EvRecordChanged, n, c, "coin:"+coinType, digest(value))
}

// CoinAddress returns a multichain address.
func CoinAddress(name string, coinType string) ([]byte, bool) {
	n := resolvableName(name)
	if n == nil {
		return nil, false
	}
	if v, ok := treeGet(n.Records.Addresses, coinType); ok {
		return v.([]byte), true
	}
	return nil, false
}

// SetText sets a text record; empty value deletes it (physical removal).
func SetText(cur realm, name string, key string, value string) {
	n, c := recordMutation(cur, name)
	if key == "" {
		panic(errBadRequest)
	}
	if value == "" {
		if _, removed := n.Records.Text.Remove(key); removed {
			n.Records.Count--
			bumpRecords(n)
			emitRecord(EvRecordChanged, n, c, "text:"+key, "")
		}
		return
	}
	if uint32(len(value)) > config.MaxTextValueBytes {
		panic(errRecordTooLarge)
	}
	if !n.Records.Text.Has(key) {
		n.recordCountGuard(1)
		n.Records.Count++
	}
	n.Records.Text.Set(key, value)
	bumpRecords(n)
	emitRecord(EvRecordChanged, n, c, "text:"+key, digestStr(value))
}

// Text returns a text record.
func Text(name string, key string) (string, bool) {
	n := resolvableName(name)
	if n == nil {
		return "", false
	}
	if v, ok := treeGet(n.Records.Text, key); ok {
		return v.(string), true
	}
	return "", false
}

// SetContentHash sets the content hash record.
func SetContentHash(cur realm, name string, value []byte) {
	n, c := recordMutation(cur, name)
	guardBinary(value)
	n.Records.ContentHash = value
	bumpRecords(n)
	emitRecord(EvRecordChanged, n, c, "content", digest(value))
}

// ContentHash returns the content hash record.
func ContentHash(name string) ([]byte, bool) {
	n := resolvableName(name)
	if n == nil || len(n.Records.ContentHash) == 0 {
		return nil, false
	}
	return n.Records.ContentHash, true
}

// SetPublicKey sets the public key record.
func SetPublicKey(cur realm, name string, value []byte) {
	n, c := recordMutation(cur, name)
	guardBinary(value)
	n.Records.PublicKey = value
	bumpRecords(n)
	emitRecord(EvRecordChanged, n, c, "pubkey", digest(value))
}

// PublicKey returns the public key record.
func PublicKey(name string) ([]byte, bool) {
	n := resolvableName(name)
	if n == nil || len(n.Records.PublicKey) == 0 {
		return nil, false
	}
	return n.Records.PublicKey, true
}

// SetABI sets an ABI blob by content type.
func SetABI(cur realm, name string, contentType string, value []byte) {
	n, c := recordMutation(cur, name)
	guardBinary(value)
	if !n.Records.ABIs.Has(contentType) {
		n.recordCountGuard(1)
		n.Records.Count++
	}
	n.Records.ABIs.Set(contentType, value)
	bumpRecords(n)
	emitRecord(EvRecordChanged, n, c, "abi:"+contentType, digest(value))
}

// ABI returns an ABI blob.
func ABI(name string, contentType string) ([]byte, bool) {
	n := resolvableName(name)
	if n == nil {
		return nil, false
	}
	if v, ok := treeGet(n.Records.ABIs, contentType); ok {
		return v.([]byte), true
	}
	return nil, false
}

// SetInterface sets an interface target by interface ID.
func SetInterface(cur realm, name string, interfaceID string, target string) {
	n, c := recordMutation(cur, name)
	if !n.Records.Interfaces.Has(interfaceID) {
		n.recordCountGuard(1)
		n.Records.Count++
	}
	n.Records.Interfaces.Set(interfaceID, target)
	bumpRecords(n)
	emitRecord(EvRecordChanged, n, c, "interface:"+interfaceID, digestStr(target))
}

// Interface returns an interface target.
func Interface(name string, interfaceID string) (string, bool) {
	n := resolvableName(name)
	if n == nil {
		return "", false
	}
	if v, ok := treeGet(n.Records.Interfaces, interfaceID); ok {
		return v.(string), true
	}
	return "", false
}

// SetRecord sets an arbitrary namespaced record. Reserved namespaces are
// rejected; use the typed setters for those.
func SetRecord(cur realm, name string, namespace string, key string, value []byte) {
	n, c := recordMutation(cur, name)
	if namespace == "" || key == "" {
		panic(errBadRequest)
	}
	if reservedNamespaces[namespace] {
		panic(errBadRequest)
	}
	guardBinary(value)
	k := namespace + "/" + key
	if !n.Records.Arbitrary.Has(k) {
		n.recordCountGuard(1)
		n.Records.Count++
	}
	n.Records.Arbitrary.Set(k, value)
	bumpRecords(n)
	emitRecord(EvRecordChanged, n, c, "record:"+k, digest(value))
}

// Record returns an arbitrary namespaced record.
func Record(name string, namespace string, key string) ([]byte, bool) {
	n := resolvableName(name)
	if n == nil {
		return nil, false
	}
	if v, ok := treeGet(n.Records.Arbitrary, namespace+"/"+key); ok {
		return v.([]byte), true
	}
	return nil, false
}

// SetTTL sets the name's TTL metadata.
func SetTTL(cur realm, name string, ttl uint64) {
	n, c := recordMutation(cur, name)
	n.TTL = ttl
	bumpRecords(n)
	emitRecord(EvRecordChanged, n, c, "ttl", strconv.FormatUint(ttl, 10))
}

func guardBinary(value []byte) {
	if config.MaxBinaryValueBytes > 0 && uint32(len(value)) > config.MaxBinaryValueBytes {
		panic(errRecordTooLarge)
	}
}

// Resolve returns a record either at the exact name or from the nearest valid
// ancestor (wildcard-style). Inheritance is explicit, never implicit in the
// primitive getters.
func Resolve(name string, query RecordQuery, mode ResolveMode) ResolveResult {
	canonical, err := Normalize(name)
	if err != nil {
		return ResolveResult{Requested: name}
	}
	cur := canonical
	for {
		n := resolvableName(cur)
		if n != nil {
			if val, ok := lookupRecord(n, query); ok {
				return ResolveResult{
					Found:      true,
					Requested:  canonical,
					SourceName: cur,
					Value:      val,
					Revision:   n.Revision,
					ExpiresAt:  n.ExpiresAt,
				}
			}
		}
		if mode == Exact {
			break
		}
		_, parent := splitLabel(cur)
		if parent == "" {
			break
		}
		cur = parent
	}
	return ResolveResult{Requested: canonical}
}

func lookupRecord(n *Name, q RecordQuery) ([]byte, bool) {
	switch q.Kind {
	case "address":
		if n.Records.NativeAddress != "" {
			return []byte(n.Records.NativeAddress), true
		}
	case "text":
		if v, ok := treeGet(n.Records.Text, q.Key1); ok {
			return []byte(v.(string)), true
		}
	case "coin":
		if v, ok := treeGet(n.Records.Addresses, q.Key1); ok {
			return v.([]byte), true
		}
	case "content":
		if len(n.Records.ContentHash) > 0 {
			return n.Records.ContentHash, true
		}
	case "pubkey":
		if len(n.Records.PublicKey) > 0 {
			return n.Records.PublicKey, true
		}
	case "abi":
		if v, ok := treeGet(n.Records.ABIs, q.Key1); ok {
			return v.([]byte), true
		}
	case "interface":
		if v, ok := treeGet(n.Records.Interfaces, q.Key1); ok {
			return []byte(v.(string)), true
		}
	case "record":
		if v, ok := treeGet(n.Records.Arbitrary, q.Key1+"/"+q.Key2); ok {
			return v.([]byte), true
		}
	}
	return nil, false
}

// ---------------------------------------------------------------------------
// 16. Reverse resolution and primary names
// ---------------------------------------------------------------------------

// SetPrimaryName sets the caller's primary (reverse) name. The name must be
// active and forward-resolve (Address) to the caller.
func SetPrimaryName(cur realm, name string) {
	requireNotPaused()
	c := callerUser(cur)
	canonical := mustNormalize(name)
	n := getRaw(canonical)
	if n == nil || !isActive(n) {
		panic(errNotFound)
	}
	if n.Records.NativeAddress != c.String() {
		panic(errUnauthorized)
	}
	reverse.Set(c.String(), canonical)
	emit(EvPrimaryNameChange, canonical, c, n.Owner, "")
}

// PrimaryName returns the verified primary name for an address, checking that
// (1) a reverse record exists, (2) the name is active, and (3) forward
// resolution still matches. Any failure returns not-found.
func PrimaryName(addr string) (string, bool) {
	v, ok := treeGet(reverse, addr)
	if !ok {
		return "", false
	}
	canonical := v.(string)
	n := getRaw(canonical)
	if n == nil || !isActive(n) {
		return "", false
	}
	if n.Records.NativeAddress != addr {
		return "", false
	}
	return canonical, true
}

// ClearPrimaryName clears the caller's reverse record.
func ClearPrimaryName(cur realm) {
	c := caller(cur) // allowed even when paused / during grace
	if _, removed := reverse.Remove(c.String()); removed {
		emit(EvPrimaryNameChange, "", c, "", "cleared")
	}
}

// invalidateReverseFor lazily clears a reverse record if the just-changed name
// no longer forward-verifies for the old owner. PrimaryName also re-verifies,
// so this is best-effort cleanup.
func invalidateReverseFor(oldOwner address, canonical string) {
	if v, ok := treeGet(reverse, oldOwner.String()); ok && v.(string) == canonical {
		n := getRaw(canonical)
		if n == nil || n.Records.NativeAddress != oldOwner.String() {
			reverse.Remove(oldOwner.String())
		}
	}
}

// ---------------------------------------------------------------------------
// 17. Enumeration (bounded, cursor-based)
// ---------------------------------------------------------------------------

func capLimit(limit uint16) int {
	const hardCap = 200
	if limit == 0 || int(limit) > hardCap {
		return hardCap
	}
	return int(limit)
}

// NamesByOwner lists canonical names owned by owner.
func NamesByOwner(owner string, cursor string, limit uint16) StringPage {
	prefix := owner + sep
	start := prefix
	if cursor != "" {
		start = prefix + cursor
	}
	max := capLimit(limit)
	items := []string{}
	next := ""
	byOwner.Iterate(start, prefixEnd(prefix), func(k string, v any) bool {
		if cursor != "" && k <= prefix+cursor {
			return false
		}
		if len(items) == max {
			next = strings.TrimPrefix(k, prefix)
			return true
		}
		items = append(items, v.(string))
		return false
	})
	return StringPage{Items: items, Next: next}
}

// Subnames lists direct subnames of parent.
func Subnames(parent string, cursor string, limit uint16) StringPage {
	pcanon, err := Normalize(parent)
	if err != nil {
		return StringPage{}
	}
	prefix := pcanon + sep
	start := prefix
	if cursor != "" {
		start = prefix + cursor
	}
	max := capLimit(limit)
	items := []string{}
	next := ""
	byParent.Iterate(start, prefixEnd(prefix), func(k string, v any) bool {
		if cursor != "" && k <= prefix+cursor {
			return false
		}
		if len(items) == max {
			next = strings.TrimPrefix(k, prefix)
			return true
		}
		items = append(items, v.(string))
		return false
	})
	return StringPage{Items: items, Next: next}
}

// TextKeys lists text-record keys for a name.
func TextKeys(name string, cursor string, limit uint16) StringPage {
	n := mustName(name)
	return treeKeys(n.Records.Text, cursor, limit)
}

// CoinTypes lists multichain coin types set for a name.
func CoinTypes(name string, cursor string, limit uint16) StringPage {
	n := mustName(name)
	return treeKeys(n.Records.Addresses, cursor, limit)
}

// Operators lists operators and their permissions for a name.
func Operators(name string, cursor string, limit uint16) OperatorPage {
	n := mustName(name)
	max := capLimit(limit)
	items := []OperatorView{}
	next := ""
	n.Operators.Iterate(cursor, "", func(k string, v any) bool {
		if cursor != "" && k <= cursor {
			return false
		}
		if len(items) == max {
			next = k
			return true
		}
		items = append(items, OperatorView{Address: k, Permissions: v.(Permissions)})
		return false
	})
	return OperatorPage{Items: items, Next: next}
}

func treeKeys(tree *avl.Tree, cursor string, limit uint16) StringPage {
	max := capLimit(limit)
	items := []string{}
	next := ""
	tree.Iterate(cursor, "", func(k string, v any) bool {
		if cursor != "" && k <= cursor {
			return false
		}
		if len(items) == max {
			next = k
			return true
		}
		items = append(items, k)
		return false
	})
	return StringPage{Items: items, Next: next}
}

// ---------------------------------------------------------------------------
// 18. Events
// ---------------------------------------------------------------------------

func eventKey(id uint64) string {
	// zero-pad to 20 digits for lexicographic ordering.
	s := strconv.FormatUint(id, 10)
	return strings.Repeat("0", 20-len(s)) + s
}

func recordEvent(e *Event) {
	nextEventID++
	e.ID = nextEventID
	e.Height = height()
	e.Timestamp = now()
	events.Set(eventKey(e.ID), e)
	// also surface as a native gno event for tx-level indexers.
	chain.Emit(e.Type, "name", e.Name, "actor", e.Actor, "id", strconv.FormatUint(e.ID, 10))
}

func emit(typ, name string, actor address, owner interface{}, key string) {
	ownerStr := ""
	switch o := owner.(type) {
	case address:
		ownerStr = o.String()
	case string:
		ownerStr = o
	}
	recordEvent(&Event{Type: typ, Name: name, Actor: actor.String(), Owner: ownerStr, Key: key})
}

func emitOwner(typ string, n *Name) {
	recordEvent(&Event{Type: typ, Name: n.Canonical, Actor: n.Owner.String(), Owner: n.Owner.String(), Revision: n.Revision})
}

func emitRecord(typ string, n *Name, actor address, key, newDigest string) {
	recordEvent(&Event{Type: typ, Name: n.Canonical, Actor: actor.String(), Owner: n.Owner.String(), Revision: n.Revision, Key: key, NewDigest: newDigest})
}

// EventsAfter returns events with ID strictly greater than id.
func EventsAfter(id uint64, limit uint16) EventPage {
	max := capLimit(limit)
	items := []Event{}
	next := ""
	start := eventKey(id + 1)
	events.Iterate(start, "", func(k string, v any) bool {
		if len(items) == max {
			next = k
			return true
		}
		items = append(items, *v.(*Event))
		return false
	})
	return EventPage{Items: items, Next: next}
}

// EventsForName returns events for a specific name with ID greater than after.
func EventsForName(name string, after uint64, limit uint16) EventPage {
	canonical, err := Normalize(name)
	if err != nil {
		return EventPage{}
	}
	max := capLimit(limit)
	items := []Event{}
	next := ""
	start := eventKey(after + 1)
	events.Iterate(start, "", func(k string, v any) bool {
		e := v.(*Event)
		if e.Name != canonical {
			return false
		}
		if len(items) == max {
			next = k
			return true
		}
		items = append(items, *e)
		return false
	})
	return EventPage{Items: items, Next: next}
}

// ---------------------------------------------------------------------------
// 19. Administration
// ---------------------------------------------------------------------------

func requireAdmin(cur realm) address {
	c := caller(cur)
	if c != config.Admin {
		panic(errUnauthorized)
	}
	return c
}

func requireNotPaused() {
	if config.Paused {
		panic(errPaused)
	}
}

// SetPaused toggles the global pause. Paused blocks registration, subname
// creation, transfers and record mutation; reads, renewals and primary-name
// clearing remain available. It never confiscates or mutates ownership.
func SetPaused(cur realm, paused bool) {
	requireAdmin(cur)
	config.Paused = paused
	if paused {
		emit(EvPaused, "", config.Admin, "", "")
	} else {
		emit(EvUnpaused, "", config.Admin, "", "")
	}
}

// SetRegistrationOpen toggles whether new second-level registrations are open.
func SetRegistrationOpen(cur realm, open bool) {
	requireAdmin(cur)
	config.RegistrationOpen = open
	emit(EvConfigChanged, "", config.Admin, "", "registration_open")
}

// SetPricing updates future pricing and bumps the policy revision so pending
// commitments that priced against the old rules are rejected at reveal.
func SetPricing(cur realm, pricing PricingConfig) {
	requireAdmin(cur)
	if pricing.BasePricePerSecond < 0 {
		panic(errBadRequest)
	}
	config.BasePricePerSecond = pricing.BasePricePerSecond
	if pricing.PremiumByLength != nil {
		config.PremiumByLength = pricing.PremiumByLength
	}
	if pricing.PaymentDenom != "" {
		config.PaymentDenom = pricing.PaymentDenom
	}
	config.PolicyRevision++
	emit(EvConfigChanged, "", config.Admin, "", "pricing")
}

// SetTreasury updates the treasury address.
func SetTreasury(cur realm, treasury address) {
	requireAdmin(cur)
	if !treasury.IsValid() {
		panic(errEmptyAddress)
	}
	config.Treasury = treasury
	emit(EvConfigChanged, "", config.Admin, "", "treasury")
}

// ReserveName reserves (or unreserves) an unregistered name so it cannot be
// publicly registered. Admin may not reserve an actively-owned name.
func ReserveName(cur realm, name string, reserved bool) {
	requireAdmin(cur)
	canonical := mustNormalize(name)
	n := getRaw(canonical)
	if n != nil && isActive(n) && n.Owner != (address("")) {
		panic(errNameUnavailable) // cannot confiscate an active name
	}
	if n == nil {
		label, parent := splitLabel(canonical)
		n = &Name{
			Canonical: canonical,
			Label:     label,
			Parent:    parent,
			Depth:     depthOf(canonical),
			Records:   newRecords(),
			Operators: avl.NewTree(),
			CreatedAt: now(),
		}
	}
	// If unreserving a bare placeholder (never registered), physically remove
	// it so the name becomes Available again rather than lingering as an
	// ExpiresAt==0 node (which statusOf would read as a permanent Active name).
	if !reserved && !n.Owner.IsValid() {
		names.Remove(canonical)
		emit(EvConfigChanged, canonical, config.Admin, "", "reserve")
		return
	}
	n.Reserved = reserved
	names.Set(canonical, n)
	emit(EvConfigChanged, canonical, config.Admin, "", "reserve")
}

// TransferAdmin begins a two-step admin handover.
func TransferAdmin(cur realm, next address) {
	requireAdmin(cur)
	if !next.IsValid() {
		panic(errEmptyAddress)
	}
	config.PendingAdmin = next
	emit(EvConfigChanged, "", config.Admin, next, "transfer_admin")
}

// AcceptAdmin completes the two-step admin handover.
func AcceptAdmin(cur realm) {
	c := caller(cur)
	if config.PendingAdmin == (address("")) || c != config.PendingAdmin {
		panic(errUnauthorized)
	}
	config.Admin = c
	config.PendingAdmin = address("")
	emit(EvConfigChanged, "", c, "", "accept_admin")
}

// SetLimits updates operational storage/abuse limits (future registrations and
// mutations). Existing names are unaffected until next mutation.
func SetLimits(cur realm, maxRecords, maxOperators uint16, maxText, maxBinary uint32) {
	requireAdmin(cur)
	config.MaxRecordsPerName = maxRecords
	config.MaxOperatorsPerName = maxOperators
	config.MaxTextValueBytes = maxText
	config.MaxBinaryValueBytes = maxBinary
	emit(EvConfigChanged, "", config.Admin, "", "limits")
}

// ---------------------------------------------------------------------------
// 20. Read API (status/lookup)
// ---------------------------------------------------------------------------

// Status returns the lifecycle status of a name.
func Status(name string) NameStatus {
	canonical, err := Normalize(name)
	if err != nil {
		return StatusAvailable
	}
	return statusOf(getRaw(canonical))
}

// Exists reports whether a name currently resolves to a live registration.
func Exists(name string) bool {
	canonical, err := Normalize(name)
	if err != nil {
		return false
	}
	n := getRaw(canonical)
	if n == nil {
		return false
	}
	switch statusOf(n) {
	case StatusActive, StatusGrace:
		return true
	}
	return false
}

// OwnerOf returns the owner of an active/grace name.
func OwnerOf(name string) (string, bool) {
	canonical, err := Normalize(name)
	if err != nil {
		return "", false
	}
	n := getRaw(canonical)
	if n == nil {
		return "", false
	}
	switch statusOf(n) {
	case StatusActive, StatusGrace:
		return n.Owner.String(), true
	}
	return "", false
}

// GetName returns a read-only view of a name.
func GetName(name string) (NameView, bool) {
	canonical, err := Normalize(name)
	if err != nil {
		return NameView{}, false
	}
	n := getRaw(canonical)
	if n == nil {
		return NameView{}, false
	}
	return NameView{
		Canonical:   n.Canonical,
		Owner:       n.Owner.String(),
		Status:      string(statusOf(n)),
		CreatedAt:   n.CreatedAt,
		UpdatedAt:   n.UpdatedAt,
		ExpiresAt:   n.ExpiresAt,
		GraceEndsAt: n.GraceEndsAt,
		Parent:      n.Parent,
		Label:       n.Label,
		Depth:       n.Depth,
		TTL:         n.TTL,
		Generation:  n.Generation,
		Revision:    n.Revision,
		Reserved:    n.Reserved,
		NativeAddr:  n.Records.NativeAddress,
	}, true
}

// CommitmentStatus returns the state of a pending commitment.
func CommitmentStatus(commit string) CommitmentView {
	cm, ok := getCommitment(commit)
	if !ok {
		return CommitmentView{}
	}
	return CommitmentView{
		Exists:    true,
		Committer: cm.Committer.String(),
		CreatedAt: cm.CreatedAt,
		ReadyAt:   cm.CreatedAt + config.MinCommitAge,
		ExpiresAt: cm.CreatedAt + config.MaxCommitAge,
	}
}

// ---------------------------------------------------------------------------
// 21. Rendering
// ---------------------------------------------------------------------------

// Render is a human-readable explorer. It never mutates state.
func Render(path string) string {
	path = strings.TrimPrefix(path, "/")
	switch {
	case path == "":
		return renderHome()
	case strings.HasPrefix(path, "name/"):
		return renderName(strings.TrimPrefix(path, "name/"))
	case strings.HasPrefix(path, "address/"):
		return renderAddress(strings.TrimPrefix(path, "address/"))
	case strings.HasPrefix(path, "available/"):
		return renderAvailable(strings.TrimPrefix(path, "available/"))
	case path == "events":
		return renderEvents()
	case path == "help":
		return renderHelp()
	default:
		return "# GNS\n\nUnknown route. See [/help](/r/moul/gns/v1:help).\n"
	}
}

func renderHome() string {
	var b strings.Builder
	b.WriteString("# GNS — Gno Name Service\n\n")
	b.WriteString("A single-realm, ENS-equivalent naming system for gno.land.\n\n")
	b.WriteString(ufmt.Sprintf("- Registered names: **%d**\n", names.Size()))
	b.WriteString(ufmt.Sprintf("- Events: **%d**\n", int(nextEventID)))
	b.WriteString(ufmt.Sprintf("- Registration open: **%t**\n", config.RegistrationOpen))
	b.WriteString(ufmt.Sprintf("- Paused: **%t**\n\n", config.Paused))
	b.WriteString("## Routes\n\n")
	b.WriteString("- `/name/<name>` — details for a name\n")
	b.WriteString("- `/address/<g1...>` — primary name + owned names\n")
	b.WriteString("- `/available/<name>` — availability and price\n")
	b.WriteString("- `/events` — recent events\n")
	b.WriteString("- `/help` — public API summary\n")
	return b.String()
}

func renderName(name string) string {
	canonical, err := Normalize(name)
	if err != nil {
		return "# " + name + "\n\nInvalid name: " + err.Error() + "\n"
	}
	n := getRaw(canonical)
	if n == nil {
		return "# " + canonical + "\n\n_Available._ See [/available/" + canonical + "](/r/moul/gns/v1:available/" + canonical + ").\n"
	}
	var b strings.Builder
	b.WriteString("# " + canonical + "\n\n")
	b.WriteString("Owner: `" + n.Owner.String() + "`\n\n")
	b.WriteString("Status: " + string(statusOf(n)) + "\n\n")
	if n.ExpiresAt > 0 {
		b.WriteString(ufmt.Sprintf("Expires: %s\n\n", time.Unix(n.ExpiresAt, 0).UTC().Format("2006-01-02")))
	} else {
		b.WriteString("Expires: never (permanent subname)\n\n")
	}
	b.WriteString(ufmt.Sprintf("Generation: %d · Revision: %d\n\n", int(n.Generation), int(n.Revision)))
	if n.Records.NativeAddress != "" {
		b.WriteString("Primary address: `" + n.Records.NativeAddress + "`\n\n")
	}
	// text records
	b.WriteString("## Records\n\n")
	hasText := false
	n.Records.Text.Iterate("", "", func(k string, v any) bool {
		b.WriteString("- " + k + ": " + v.(string) + "\n")
		hasText = true
		return false
	})
	if !hasText {
		b.WriteString("_No text records._\n")
	}
	// subnames
	b.WriteString("\n## Subnames\n\n")
	subs := Subnames(canonical, "", 50)
	if len(subs.Items) == 0 {
		b.WriteString("_None._\n")
	} else {
		for _, s := range subs.Items {
			b.WriteString("- " + s + "\n")
		}
	}
	return b.String()
}

func renderAddress(addr string) string {
	var b strings.Builder
	b.WriteString("# " + addr + "\n\n")
	if pn, ok := PrimaryName(addr); ok {
		b.WriteString("Primary name: **" + pn + "**\n\n")
	} else {
		b.WriteString("_No verified primary name._\n\n")
	}
	b.WriteString("## Owned names\n\n")
	page := NamesByOwner(addr, "", 50)
	if len(page.Items) == 0 {
		b.WriteString("_None._\n")
	} else {
		for _, s := range page.Items {
			b.WriteString("- " + s + "\n")
		}
	}
	return b.String()
}

func renderAvailable(name string) string {
	canonical, err := Normalize(name)
	if err != nil {
		return "# " + name + "\n\nInvalid: " + err.Error() + "\n"
	}
	var b strings.Builder
	b.WriteString("# " + canonical + "\n\n")
	if available(canonical) {
		b.WriteString("**Available.**\n\n")
		q, _ := Price(canonical, config.MinRegistrationDuration)
		b.WriteString(ufmt.Sprintf("Price for %d seconds: %d %s\n", int(config.MinRegistrationDuration), int(q.Amount), q.Denom))
	} else {
		b.WriteString("**Not available** (status: " + string(Status(canonical)) + ").\n")
	}
	return b.String()
}

func renderEvents() string {
	var b strings.Builder
	b.WriteString("# Recent events\n\n")
	from := uint64(0)
	if nextEventID > 20 {
		from = nextEventID - 20
	}
	page := EventsAfter(from, 20)
	if len(page.Items) == 0 {
		b.WriteString("_No events yet._\n")
		return b.String()
	}
	b.WriteString("| ID | Type | Name | Actor |\n| ---: | --- | --- | --- |\n")
	for _, e := range page.Items {
		b.WriteString(ufmt.Sprintf("| %d | %s | %s | `%s` |\n", int(e.ID), e.Type, e.Name, e.Actor))
	}
	return b.String()
}

func renderHelp() string {
	return "# GNS API\n\n" +
		"Read: `Normalize`, `Status`, `Exists`, `OwnerOf`, `GetName`, `Resolve`, " +
		"`Address`, `CoinAddress`, `Text`, `ContentHash`, `PublicKey`, `ABI`, " +
		"`Interface`, `Record`, `PrimaryName`, `Price`, `CommitmentStatus`, " +
		"`NamesByOwner`, `Subnames`, `TextKeys`, `CoinTypes`, `Operators`, " +
		"`EventsAfter`, `EventsForName`.\n\n" +
		"Mutations (crossing, panic on failure): `Commit`, `Register`, `Renew`, " +
		"`Transfer`, `CreateSubname`, `DeleteSubname`, `SetRegistrationPolicy`, " +
		"`LockPolicy`, `SetOperator`, `RemoveOperator`, `SetPrimaryName`, " +
		"`ClearPrimaryName`, and the typed record setters.\n\n" +
		"Admin: `SetPaused`, `SetRegistrationOpen`, `SetPricing`, `SetTreasury`, " +
		"`ReserveName`, `TransferAdmin`, `AcceptAdmin`, `SetLimits`.\n"
}

// ---------------------------------------------------------------------------
// 22. Internal storage helpers
// ---------------------------------------------------------------------------

func coins(denom string, amount int64) chain.Coins {
	return chain.NewCoins(chain.NewCoin(denom, amount))
}

// treeGet adapts the avl v0 API (Get returns a single value; existence is via
// Has) to the (value, ok) idiom used throughout this file.
func treeGet(t *avl.Tree, key string) (any, bool) {
	if !t.Has(key) {
		return nil, false
	}
	return t.Get(key), true
}

func getRaw(canonical string) *Name {
	v, ok := treeGet(names, canonical)
	if !ok {
		return nil
	}
	return v.(*Name)
}

// resolvableName returns the name only if it is currently Active (records
// resolve only for active names).
func resolvableName(name string) *Name {
	canonical, err := Normalize(name)
	if err != nil {
		return nil
	}
	n := getRaw(canonical)
	if n == nil || !isActive(n) {
		return nil
	}
	return n
}

// mustName returns an existing name or panics with not_found.
func mustName(name string) *Name {
	canonical := mustNormalize(name)
	n := getRaw(canonical)
	if n == nil {
		panic(errNotFound)
	}
	return n
}

func putName(n *Name) {
	names.Set(n.Canonical, n)
	byOwner.Set(ownerKey(n.Owner, n.Canonical), n.Canonical)
	if n.Parent != "" {
		byParent.Set(n.Parent+sep+n.Canonical, n.Canonical)
	}
}

func deleteName(n *Name) {
	n.Deleted = true
	byOwner.Remove(ownerKey(n.Owner, n.Canonical))
	if n.Parent != "" {
		byParent.Remove(n.Parent + sep + n.Canonical)
	}
	names.Remove(n.Canonical)
}

func ownerKey(owner address, canonical string) string {
	return owner.String() + sep + canonical
}

func getCommitment(key string) (*commitment, bool) {
	v, ok := treeGet(commitments, key)
	if !ok {
		return nil, false
	}
	return v.(*commitment), true
}

func getOperator(n *Name, addr address) (Permissions, bool) {
	if n.Operators == nil {
		return Permissions{}, false
	}
	v, ok := treeGet(n.Operators, addr.String())
	if !ok {
		return Permissions{}, false
	}
	return v.(Permissions), true
}

func allowlistHas(tree *avl.Tree, addr address) bool {
	v, ok := treeGet(tree, addr.String())
	return ok && v.(bool)
}

func collectPaymentDenom(cur realm, price int64, denom string, treasury address) {
	if price <= 0 {
		return
	}
	if !cur.Previous().IsUserCall() {
		panic(errNotUser)
	}
	sent := unsafe.OriginSend()
	got := sent.AmountOf(denom)
	if got < price {
		panic(errInsufficientPay)
	}
	bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	self := cur.Address()
	if treasury != self {
		bk.SendCoins(self, treasury, coins(denom, price))
	}
	if over := got - price; over > 0 {
		bk.SendCoins(self, cur.Previous().Address(), coins(denom, over))
	}
}

func prefixEnd(prefix string) string {
	if prefix == "" {
		return ""
	}
	b := []byte(prefix)
	for i := len(b) - 1; i >= 0; i-- {
		if b[i] < 0xff {
			b[i]++
			return string(b[:i+1])
		}
	}
	return "" // prefix is all 0xff; iterate to end
}

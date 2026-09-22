package wesh

import "encoding/binary"

// DefaultRotationInterval is weshnet's rendezvous rotation period, in seconds
// (rendezvous.DefaultRotationInterval = 24h). The rendezvous point an account
// announces on changes once per interval, so an observer who learns one point
// does not learn every future one.
const DefaultRotationInterval int64 = 86400

// RoundPeriod returns the start of the rotation period containing unixSec.
// Mirrors weshnet's rendezvous.RoundTimePeriod.
func RoundPeriod(unixSec, interval int64) int64 {
	if interval < 0 {
		interval = -interval
	}
	if interval == 0 {
		panic("wesh: rotation interval must not be zero")
	}
	return (unixSec / interval) * interval
}

// NextPeriod returns the start of the period after the one containing unixSec.
// Mirrors weshnet's rendezvous.NextTimePeriod.
func NextPeriod(unixSec, interval int64) int64 {
	if interval < 0 {
		interval = -interval
	}
	return RoundPeriod(unixSec, interval) + interval
}

// RendezvousPoint derives the rotating DHT topic an account announces on
// during the period starting at periodStart.
//
// It reproduces weshnet's rendezvous.GenerateRendezvousPointForPeriod exactly:
//
//	HMAC-SHA256(key = topic ‖ seed, msg = big-endian uint64(periodStart))
//
// For contact requests, weshnet passes the account public key as the topic and
// the public rendezvous seed as the seed (see swiper.WatchTopic in
// contact_request_manager.go), which is what [Contact.RendezvousPointAt] does.
//
// Deriving this on chain is what makes a published identity checkable: anyone
// can confirm that the seed in the directory really is the one the account is
// announcing under, without trusting the directory.
func RendezvousPoint(topic, seed []byte, periodStart int64) []byte {
	key := make([]byte, 0, len(topic)+len(seed))
	key = append(key, topic...)
	key = append(key, seed...)

	buf := make([]byte, 8)
	binary.BigEndian.PutUint64(buf, uint64(periodStart))

	return HMACSHA256(key, buf)
}

// RendezvousPointAt returns the contact's rendezvous point for the rotation
// period containing unixSec.
func (c Contact) RendezvousPointAt(unixSec, interval int64) ([]byte, error) {
	if err := c.Validate(); err != nil {
		return nil, err
	}
	return RendezvousPoint(c.AccountPK, c.Seed, RoundPeriod(unixSec, interval)), nil
}

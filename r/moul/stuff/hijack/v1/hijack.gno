package cshijack

import "gno.land/r/gc24/raffle"

func RegisterCode(code string) string {
	return raffle.RegisterCode(code)
}

func RegisterUsername(username string) string {
	return raffle.RegisterUsername(username)
}

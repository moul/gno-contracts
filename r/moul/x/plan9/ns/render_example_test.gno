package ns

import "gno.land/p/nt/avl/v0"

// resetForExample rebuilds the whole realm state. Realm globals persist for
// the entire test binary and examples run after every Test, so without this an
// example would pin whatever the last test happened to leave behind.
func resetForExample() {
	services = avl.NewTree()
	spaces = avl.NewTree()
	seedDemo()
}

// ExampleRender pins the realm's front page.
func ExampleRender() {
	resetForExample()
	print(Render(""))
	// Output:
	// # plan9: namespaces for gno
	//
	// A Plan 9 namespace server. Every account owns a private mount table over [9P-shaped](https://9p.io/sys/doc/9.html) file trees: realms post trees into `/srv`, you `bind` them where you want them, and a name means what *you* bound it to.
	//
	// ## /srv
	//
	// _No service is posted yet._
	//
	// ## The demo namespace
	//
	// ```
	// mount #s /srv
	// bind -ac /usr/glenda/bin /bin
	// cd /usr/glenda
	// ```
	//
	// `/bin` is a union: the system `/bin` first, then `/usr/glenda/bin`, with `-c` so new files land in the second. Listing it shows both members because a Plan 9 union is a concatenation, so shadowing stays visible.
	//
	// - [ns](:ns) · [ls /](:ls) · [ls /bin](:ls/bin) · [cat /tmp/greeting](:cat/tmp/greeting) · [walk /bin/rc](:walk/bin/rc)
	// - any read-only command: [`rc?c=ls -l /srv`](:rc?c=ls%20-l%20/srv)
	//
	// ## Your own namespace
	//
	// ```
	// gnokey maketx call -pkgpath gno.land/r/moul/x/plan9/ns/v0 \
	//   -func Exec -args 'bind -ac /srv/dev /dev; echo hi > /tmp/f'
	// ```
	//
	// Then browse it with `?u=<your address>`. `Reset` throws it away.
	//
	// ## Namespaces
	//
	// - [`demo`](:ns?u=demo)
	//
	// Design and analysis: [moul/gno-contracts#136](https://github.com/moul/gno-contracts/issues/136).
	//
	// _Not affiliated with Plan 9. Plan 9 from Bell Labs is the work of the Computing Science Research Center at Bell Labs; the name and the marks are theirs, and the copyright is held by the [Plan 9 Foundation](https://p9f.org). This realm borrows the vocabulary and none of the code: it is an homage, asking what that ecosystem's spirit looks like on a chain._
}

// ExampleRender_ls pins a union directory listing.
func ExampleRender_ls() {
	resetForExample()
	print(Render("ls/bin"))
	// Output:
	// # ls /bin
	//
	// namespace: `demo`
	//
	// ```
	// -rw-r--r-- demo         demo          10 ls
	// -rw-r--r-- demo         demo          10 rc
	// ```
	//
	// [namespace](:ns?u=demo) · [root](:ls?u=demo) · [home](:)
}

// ExampleRender_walk pins a resolution trace, which is where a bind becomes
// visible: the union column widens exactly at the bound name.
func ExampleRender_walk() {
	resetForExample()
	print(Render("walk/bin/rc"))
	// Output:
	// # walk /bin/rc
	//
	// namespace: `demo`
	//
	// ```
	// /                        (1 5 d) drwxr-xr-x union=1
	// /bin                     (a 1 d) drwxr-xr-x union=2
	// /bin/rc                  (9 1 f) -rw-r--r-- union=1
	// ```
	//
	// [namespace](:ns?u=demo) · [root](:ls?u=demo) · [home](:)
}

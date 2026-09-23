// Command gnoblog drives the gno.land/r/moul/blog realm from local markdown.
//
// The realm stores posts in chain storage rather than in its code, so
// publishing is one small transaction and never a redeploy. This tool is the
// local half of that loop:
//
//	gnoblog posts     list the local posts, with dates, sizes and hashes
//	gnoblog preview   render the index, or one post, the way the realm will
//	gnoblog status    diff the local markdown against what is on chain
//	gnoblog tx        publish exactly what differs, in one transaction
//
// # Where the markdown lives
//
// Nowhere in this repository, and there is no default pointing at it: pass
// -content, or set GNOBLOG_CONTENT. The realm is public and its posts are
// public once published, but the drafts are the author's, and a tool that
// shipped a path to them would be publishing where they are kept.
//
// A content directory is flat:
//
//	<slug>.md   a post: `---` front matter (title, date, tags) then markdown
//	intro.md    the markdown shown above the index; no front matter
//
// # It holds no key
//
// Reads go over plain JSON-RPC abci_query, standard library only. A write is
// built as an unsigned transaction document and handed to gnokey, which signs
// it and prompts on your terminal for a passphrase this process never sees.
// `status` is the review step and `-print` writes the commands out instead of
// running them; the copy-paste in between was never a third gate, and a
// document's signature covers the account sequence, so the gap it opened was a
// window in which anything else this key signed voided the document.
//
// Deploying the realm itself is NOT here: that is `gnopm publish`.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
)

// Defaults mirror the realm. Keep them in step with r/moul/blog/blog.gno.
const (
	defaultRealm   = "gno.land/r/moul/blog"
	defaultRemote  = "https://rpc.gno.land:443"
	defaultChainID = "gnoland-1"
	defaultKey     = "moul"
	defaultOwner   = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"
)

type config struct {
	contentDir string
	realm      string
	remote     string
	chainID    string
	key        string
	owner      string
}

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "gnoblog: "+err.Error())
		os.Exit(1)
	}
}

func usage(out *os.File) {
	fmt.Fprint(out, `gnoblog drives gno.land/r/moul/blog from local markdown.

  gnoblog posts              the local posts: slug, date, bytes, hash
  gnoblog preview [-post S]  render the index, or one post
  gnoblog status             diff the local markdown against the chain
  gnoblog tx [-all] [-prune] publish the difference, in one transaction

The content directory is not defaulted: pass -content, or set GNOBLOG_CONTENT.

  -content DIR   where the markdown lives (or $GNOBLOG_CONTENT)
  -realm PATH    realm package path (default `+defaultRealm+`)
  -remote URL    RPC endpoint (default `+defaultRemote+`)
  -chainid ID    chain id for the emitted commands (default `+defaultChainID+`)
  -key NAME      gnokey key name (default `+defaultKey+`)
  -owner ADDR    signing address (default `+defaultOwner+`)

tx flags:
  -all           push every post, not only what differs. This is what a
                 redeploy needs: a private realm redeploy wipes the posts
  -print         write the sign and broadcast commands out, run nothing
  -prune         also emit Delete for a post on chain with no local file
  -out FILE      where to write the transaction document
  -gas-wanted N  override the per-message gas estimate
  -gas-fee F     override the fee (default: 0.01 ugnot per gas)
  -max-deposit D storage deposit ceiling, e.g. 1000000ugnot
`)
}

func run(args []string, out *os.File) error {
	if len(args) == 0 || args[0] == "-h" || args[0] == "--help" || args[0] == "help" {
		usage(out)
		return nil
	}
	cmd, rest := args[0], args[1:]

	fs := flag.NewFlagSet("gnoblog "+cmd, flag.ContinueOnError)
	var cfg config
	fs.StringVar(&cfg.contentDir, "content", os.Getenv("GNOBLOG_CONTENT"), "directory holding the post markdown")
	fs.StringVar(&cfg.realm, "realm", defaultRealm, "realm package path")
	fs.StringVar(&cfg.remote, "remote", defaultRemote, "RPC endpoint")
	fs.StringVar(&cfg.chainID, "chainid", defaultChainID, "chain id, for the emitted gnokey commands")
	fs.StringVar(&cfg.key, "key", defaultKey, "gnokey key name, for the emitted gnokey commands")
	fs.StringVar(&cfg.owner, "owner", defaultOwner, "signing address")

	var (
		postSlug   string
		all        bool
		opt        txOptions
		batchOut   string
		previewOut string
	)
	switch cmd {
	case "preview":
		fs.StringVar(&postSlug, "post", "", "render this post instead of the index")
		fs.StringVar(&previewOut, "out", "", "write the render to this file instead of stdout")
	case "tx":
		fs.BoolVar(&all, "all", false, "push every post, not only what differs")
		fs.BoolVar(&opt.prune, "prune", false, "emit Delete for a post on chain with no local file")
		fs.BoolVar(&opt.print, "print", false, "write the sign and broadcast commands out instead of running them")
		fs.StringVar(&batchOut, "out", "", "where to write the transaction document (default: <content>/../.gnoblog-tx.json)")
		fs.Int64Var(&opt.gasWanted, "gas-wanted", 0, "override the per-message gas estimate")
		fs.StringVar(&opt.gasFee, "gas-fee", "", "override the gas fee")
		fs.StringVar(&opt.maxDeposit, "max-deposit", "", "storage deposit ceiling, e.g. 1000000ugnot")
	}
	if err := fs.Parse(rest); err != nil {
		return err
	}

	if cfg.contentDir == "" {
		return fmt.Errorf("no content directory: pass -content DIR or set GNOBLOG_CONTENT " +
			"(this repository deliberately ships no default path to it)")
	}
	posts, err := loadPosts(cfg.contentDir)
	if err != nil {
		return err
	}

	switch cmd {
	case "posts":
		return listPosts(out, posts)
	case "preview":
		body := preview(posts, postSlug)
		if previewOut != "" {
			return os.WriteFile(previewOut, []byte(body), 0o644)
		}
		fmt.Fprint(out, body)
		return nil
	case "status":
		return status(out, cfg, posts)
	case "tx":
		changes, err := changesFor(cfg, posts, all, opt.prune)
		if err != nil {
			return err
		}
		if batchOut == "" {
			abs, err := filepath.Abs(cfg.contentDir)
			if err != nil {
				return err
			}
			batchOut = filepath.Join(filepath.Dir(abs), ".gnoblog-tx.json")
		}
		return publishBatch(out, cfg, changes, opt, batchOut)
	default:
		usage(out)
		return fmt.Errorf("unknown command %q", cmd)
	}
}

func listPosts(out *os.File, posts []postFile) error {
	if len(posts) == 0 {
		fmt.Fprintln(out, "no markdown found")
		return nil
	}
	for _, p := range newestFirst(posts) {
		fmt.Fprintf(out, "%-10s  %-28s  %6d B  %s  %s\n",
			p.date, p.slug, len(p.body), short(p.hash), p.title)
	}
	for _, p := range posts {
		if p.isIntro() {
			fmt.Fprintf(out, "%-10s  %-28s  %6d B  %s  (index header)\n",
				"", introFile, len(p.body), short(p.hash))
		}
	}
	return nil
}

func status(out *os.File, cfg config, posts []postFile) error {
	remote, err := fetchManifest(cfg.remote, cfg.realm)
	if err != nil {
		return err
	}
	changes := diff(posts, remote)
	if len(changes) == 0 {
		fmt.Fprintf(out, "up to date: %d post(s) match %s on %s\n",
			countPosts(posts), cfg.realm, cfg.chainID)
		return nil
	}
	for _, c := range changes {
		fmt.Fprintf(out, "%-9s %-28s %s\n", c.kind, c.slug, c.detail)
	}
	fmt.Fprintf(out, "\n%d change(s); `gnoblog tx` writes the transaction\n", len(changes))
	return nil
}

// changesFor decides what tx will act on. -all skips the chain read entirely,
// which is the point: after a redeploy the manifest is empty and asking it
// what changed answers "everything", one round trip later.
func changesFor(cfg config, posts []postFile, all, prune bool) ([]change, error) {
	if all {
		return allChanges(posts), nil
	}
	remote, err := fetchManifest(cfg.remote, cfg.realm)
	if err != nil {
		return nil, err
	}
	changes := diff(posts, remote)
	if prune {
		return changes, nil
	}
	out := changes[:0]
	for _, c := range changes {
		if c.kind != kindExtra {
			out = append(out, c)
		}
	}
	return out, nil
}

func countPosts(posts []postFile) int {
	n := 0
	for _, p := range posts {
		if !p.isIntro() {
			n++
		}
	}
	return n
}

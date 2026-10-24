# software-dev

Optional. The software-development toolchain, kept out of the main ladder because
none of it is needed for a working niri session: the main ladder builds a
session, this builds somewhere to write code in it. **Nothing in the main ladder
depends on this**, and it can be removed without touching anything else.

It is its own ladder, run with the same runner from the repo root:

```
bun run ladder software-dev list
bun run ladder software-dev plan
bun run ladder software-dev up
```

Both installation modes apply, as everywhere else: `ROOT_MNT` in `.env` or
`--live` decides whether it writes into a mounted target root or into the running
system.

- `10-toolchain` — cmake, unzip, autoconf; fnm with the latest Node LTS, pnpm
  from that npm, and Command Code from pnpm; rustup; Zed; uv for Python; and
  ripgrep, fd and just.
- `20-git` — the git presentation config: the `stat` and `https-to-ssh` aliases,
  delta as the pager with its colours, and the global ignore file; plus the
  `git-delta` and `bat` packages, and identity and SSH commit signing from
  `.env`.
- `30-brave-search` — `bx`, the Brave Search CLI, as a pnpm global. The API key
  is yours to set; the step says how.
- `40-forges` — `gh` and `glab`, the GitHub and GitLab CLIs, from the
  repositories. Logging in is left to you, because a token is not something a
  repository should hold.
- `50-cloudflare` — `cf`, the Cloudflare CLI, as a pnpm global. Still a 1.0
  beta; it installs both `cf` and `cloudflare`.

## What it installs, and where

| tool | from | lives in |
| --- | --- | --- |
| `cmake`, `unzip`, `autoconf`, `zed`, `uv`, `ripgrep`, `fd`, `just` | the repositories | `/usr` |
| `fnm` | the repositories | `/usr/bin/fnm` |
| Node LTS | `fnm install --lts` | `~/.local/share/fnm` |
| `pnpm` | `npm install -g`, using the fnm node | `~/.local/share/fnm/aliases/default/bin` |
| `command-code` | `pnpm add -g` | `~/.local/share/pnpm` |
| `rustup` | rustup.rs, `--no-modify-path` | `~/.cargo`, `~/.rustup` |
| `git-delta`, `bat` | the repositories | `/usr` |
| git aliases, delta pager | `files/git/config` + `.env` | `~/.config/git/config` |
| global gitignore | `files/git/ignore` | `~/.config/git/ignore` |
| `github-cli`, `glab` | the repositories | `/usr/bin/gh`, `/usr/bin/glab` |
| `bx` | `pnpm add -g` | `~/.local/share/pnpm` |
| `cf`, `cloudflare` | `pnpm add -g` | `~/.local/share/pnpm` |

Node's version is fnm's, not the repositories', so it can be switched per project.
`pnpm` is installed with the npm that comes *with* that Node, so the two stay
paired.

## PATH

A fish `conf.d` snippet is written to
`~/.config/fish/conf.d/software-dev.fish`, prepending `~/.cargo/bin`,
`~/.local/bin` — where uv puts the shims for `uv tool install` — and
`~/.local/share/pnpm`, and sourcing `fnm env --use-on-cd --shell fish`. It is a
separate file rather than an edit to `config.fish`, because `90-fish` in the main
ladder owns that file; `down` deletes the snippet and nothing else. The snippet
was called `sdks.fish` before the ladder was renamed, and `up` removes that old
file if it is still there.

Open a new shell afterwards. The step itself does not touch the running one.

## rustup is not a distro package, on purpose

`105-niri-gestures` in the main ladder builds the patched niri with rustup's
cargo. It calls the same `ensureRustup()` helper this ladder uses, so the main
ladder still works end to end without this one having run — and no distro `rust`
is ever installed. If you do have the repositories' `rust` package for some other
reason, `sudo pacman -Rns rust` removes it; nothing here needs it.

One consequence worth knowing, since it caused a real build failure: makepkg's
`lto` option compiles C with `-flto=auto`, and rustup's rustc links with
`rust-lld`, which cannot read GCC's LTO bytecode. The niri PKGBUILD therefore
sets `options=('!lto')`.

## Git

`20-git` writes `~/.config/git/config` — the XDG location, not `~/.gitconfig`.
Git reads both, and `~/.gitconfig` wins for single-valued keys, so a hand-written
`~/.gitconfig` can sit beside it without either file overwriting the other.

The vendored `files/git/config` carries only what is the same everywhere: the two
aliases, `core.pager = delta`, `interactive.diffFilter`, the `[delta]` colours and
`merge.conflictStyle = zdiff3`. Identity comes from `.env`:

| key | becomes |
| --- | --- |
| `GIT_NAME`, `GIT_EMAIL` | `[user] name`, `email`; skip both and there is no `[user]` section |
| `GIT_SIGNING_KEY` | `user.signingkey`, plus `gpg.format = ssh`, `commit.gpgsign`, `tag.gpgSign` |

Setting `GIT_SIGNING_KEY` is what turns signing on. Signing needs the matching
*private* key next to it and `ssh-keygen` on PATH; the step warns if the public
key it was given is unreadable, because otherwise every commit fails later with a
much worse message.

`core.excludesFile` is deliberately not set: git's default excludes path is
`$XDG_CONFIG_HOME/git/ignore`, which is exactly where the ignore file goes.

## Credentials

Nothing here logs in for you, and that is deliberate rather than unfinished:
`gh`, `glab`, `bx` and `cf` all keep their tokens in the account's home, and a
token written into a repository is a leaked token even when the file is
gitignored.

| tool | command | keeps it in |
| --- | --- | --- |
| `gh` | `gh auth login` | `~/.config/gh/hosts.yml` |
| `glab` | `glab auth login` | `~/.config/glab-cli/config.yml` |
| `bx` | `bx config set-key` | `~/.config/brave-search/config.json` |
| `cf` | `cf auth login` | `~/.config/cloudflare` |

`down` removes packages and leaves those files, because a credential is the one
thing in this ladder that cannot be re-derived from the repository.

## Undo

`down` removes the fish snippet, the global `command-code` and `pnpm`, rustup
(through `rustup self uninstall`), `~/.local/share/fnm` and
`~/.local/share/pnpm`, then the packages. Node versions and pnpm's store live
inside those two directories, so they go with them.

`20-git`'s `down` restores whatever `~/.config/git/{config,ignore}` held before
the first run — or removes them if there was nothing — and uninstalls `git-delta`
and `bat`.

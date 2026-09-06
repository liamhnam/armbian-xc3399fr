# Relationship to upstream Armbian

This repository is a **product build**. It is not a fork and it must never
become one. Everything that is true of the board belongs upstream; only things
that are true of *the product we sell* live here.

    generic truth about the XC3399FR  ->  armbian/build
    true only for units we ship       ->  this repository

Keeping that line sharp is what made the port cheap: when the upstream PR
merged, most of this repository simply went away.

---

## 1. What is upstream

Both PRs merged on **2026-09-06**.

| PR | Repo | Contents | Merged |
|---|---|---|---|
| [#10619](https://github.com/armbian/build/pull/10619) | `armbian/build` | `config/boards/xc3399fr.csc` + `rk3399-xc3399fr.dts` for rockchip64 6.18 / 7.2 / 7.3 | 08:59 UTC, commit `66dbc7af`, approved by `EvilOlaf`, merged by `igorpecovnik` |
| [#440](https://github.com/armbian/armbian.github.io/pull/440) | `armbian/armbian.github.io` | board photo + ProEmbed vendor logo | 07:23 UTC, approved and merged by `igorpecovnik` |

The order mattered: `#440` had to land first, because the only failing check on
the board PR was `Verify assets for newly added boards`, which fails until the
assets exist in the website repo. Nothing in the port itself was ever contested;
zero review threads were left unresolved.

### What that gets, automatically

`.csc` means **community-maintained**. Per Armbian's
[board support rules](https://docs.armbian.com/contribute/board-support-rules/),
that tier is entitled to published images through the mirror network and daily
rolling builds — with no further action from us. The pipeline classifies the
board from the config file alone: `.csc` -> `community-maintained`, arm64 with
video output -> `community-maintained-fast-hdmi`, and `KERNEL_TEST_TARGET`
pins the branch to `current`. The board is in neither automation blacklist.

Expected output, matching what the sibling `fine3399` board gets:

    Armbian_community_<ver>_Xc3399fr_trixie_current_<kver>_minimal.img.xz
    Armbian_community_<ver>_Xc3399fr_<rel>_current_<kver>_xfce_desktop.img.xz

Timing, measured from three boards merged just before this one:
`xiaomi-sheng` took 6 days from merge to first published image,
`nanopi-neo3-plus` 8 days, `lubancat-4` at most 9. So expect the first official
image around **2026-09-12 to 2026-09-15** in the
[`armbian/community`](https://github.com/armbian/community/releases) releases.

### One thing that needs a human

An hourly bot job, `Data: Sync maintainers`, regenerates every board's
`BOARD_MAINTAINER` from Armbian's own maintainer database and opens a PR with
the result — [#10642](https://github.com/armbian/build/pull/10642) is the one
that blanks ours. It is not a rejection: the database simply has no entry for
`liamhnam` yet, and Armbian's rules require a maintainer to
[reveal their identity](https://www.armbian.com/update-data/) to project
management even when operating under a pseudonym.

**Losing `BOARD_MAINTAINER` does not stop images from being built** — the build
matrix is generated from `find config/boards/*.{conf,wip,tvb,csc}` with no
maintainer filter; the maintainer list only populates a dropdown for manual
one-off builds. What it costs is attribution, the `armbian.com/authors` listing,
and being review-requested when someone touches the board. Register at
armbian.com/update-data to have the next hourly sync restore the name instead of
clearing it.

---

## 2. Considered and rejected: blacklisting the `7825:a2a4` bridge upstream

Armbian keeps a global UAS blacklist, and its own comment invites additions:

`packages/bsp/common/usr/lib/armbian/armbian-hardware-optimization`:

    # UAS blacklist Norelsys NS1068X and NS1066X since broken. Can be removed once
    # they're blacklisted upstream
    [ -s ${TMPFILE} ] || echo "0x2537:0x1066:u,0x2537:0x1068:u" > ${TMPFILE}

Adding our bridge would be one line, and for a while this document recommended
doing it. **It was dropped, on purpose.** The reasoning is recorded here so
nobody re-proposes it without new evidence.

### Why not

**The evidence does not support a global blacklist.** What was measured is that
the bridge misbehaves *on RK3399, behind a Synopsys dwc3 xHCI*: one SoC, one
board, one SSD, two cables. Section 1 of `storage.md` argues at length that UAS
is a negotiation between the bridge **and the host controller**, and that
bridges which are solid on x86 misbehave on ARM SBCs routinely. That cuts both
ways: the fault may well be the *interaction*, not the device.

Armbian's list is applied to every board it builds, x86 included. Pushing an
entry there on RK3399-only data would force BOT - and a 4-11x random IOPS
penalty - on people whose setup works fine. A reviewer would be right to ask
"tested on any other host?", and the honest answer is no.

**It also does not help this product.** The cable is no longer bundled, so no
customer is affected. And it would work slightly *against* the units we run
ourselves: if merged, our own images would default that bridge to BOT and every
box that wants UAS would need an `armbianEnv.txt` override.

### What would be correct, if anyone wants to pursue it

Report rather than blacklist: a description to `linux-usb@vger.kernel.org` with
the logs and reproduction steps, so people with other host controllers can
confirm or contradict it. If several hosts reproduce it, the right home for a
quirk is `unusual_uas.h` in mainline, not a distro script - and at that point
Armbian's list stops being needed at all, which is exactly what its comment
anticipates.

A ready-to-send draft is kept outside this repository at
`XC3399FR/upstream/PR-uas-blacklist.md`. It is deliberately not sent.

---

## 3. What still lives here, and why

The device trees are **gone from this repository**. They come from
`armbian/build` now. Do not re-add a copy: two copies drift, and the whole point
of upstreaming was to stop maintaining them here. Device-tree changes go to
`armbian/build` as a PR, applied identically to all three kernel branches.

`userpatches/config/boards/xc3399fr.csc` is an **overlay**, not a replacement.
Armbian's `config_source_board_file()` collects the board file from
`${SRC}/config/boards` *and* `${USERPATCHES_PATH}/config/boards` and sources
both in that order, so the overlay only has to carry what differs:

| Item | Reason |
|---|---|
| `KERNEL_TARGET="current"` (upstream: `current,edge,bleedingedge`) | Customers get the LTS kernel the board was validated on. Upstream offers the others so testers can use them; a customer box must not track a moving kernel. |
| `post_family_tweaks__xc3399fr_watchdog` | The RK3399 watchdog exists and the kernel exposes `/dev/watchdog0`, but nothing feeds it. On an unattended 24/7 box a kernel hang would otherwise be permanent. **No Armbian board sets `RuntimeWatchdogSec`** - it is not a convention, so it did not belong in the board PR, but it is right for this product. |
| Comment block on why no smartd config ships | Documentation only. An earlier revision configured `smartd` for the USB-SATA bridge; it was removed once testing showed the config did not work and could not be made generic (`install.md`). |
| Comment block on why `usbstoragequirks` is unset | Documentation only. An earlier revision pinned the formerly-bundled `7825:a2a4` bridge to BOT; it went away when the cable stopped shipping. |

Everything else - `BOARD_NAME`, `BOARDFAMILY`, `BOOTCONFIG`, `BOOT_FDT_FILE`,
`BOOT_SCENARIO`, `FULL_DESKTOP` - is inherited and stays in step with upstream
automatically. Adding any of them back here would silently pin a stale value.

One detail about `usbstoragequirks` is easy to get wrong, and was in fact wrong
here for a while. `armbian-hardware-optimization` installs Armbian's own UAS
blacklist **only when the variable is empty**:

    [ -s ${TMPFILE} ] || echo "0x2537:0x1066:u,0x2537:0x1068:u" > ${TMPFILE}

So writing a bare `usbstoragequirks=7825:a2a4:u` does not *add* a bridge to that
list - it *replaces* the list, and a customer plugging in a Norelsys enclosure
silently loses the protection Armbian ships for it.

That is a second reason, on top of no longer bundling the cable, to leave the
variable unset: it is the only value for which Armbian's own protection stays
in effect. If you ever do need to pin a bridge on a specific unit, carry the two
Norelsys entries alongside yours - `tools/board/storage-transport.sh` does.

---

## 4. Keeping in step from here

The framework checkout is pinned in `.github/workflows/build-image.yml`
(`ARMBIAN_REF`), currently `66dbc7af` - the commit that merged the board. Bump
it deliberately, not on a schedule: a pinned ref is what makes an image
reproducible, and a customer box is not the place to discover an upstream
regression. When bumping, rebuild and re-run `docs/testing.md` before shipping.

Still true, and worth not forgetting:

* **Keep every document in `docs/`.** The measurements and the refuted
  hypotheses are the part that took the time; they did not become obsolete when
  the code moved upstream.
* **Nothing else is pending upstream.** Section 2 records the one change that
  was considered and deliberately not sent.
* If a future device-tree fix lands upstream, this repository needs no change at
  all - the next build picks it up when `ARMBIAN_REF` is bumped.

# Relationship to upstream Armbian

This repository is a **product build**. It is not a fork and it must never
become one. Everything that is true of the board belongs upstream; only things
that are true of *the product we sell* live here.

    generic truth about the XC3399FR  ->  armbian/build
    true only for units we ship       ->  this repository

Keeping that line sharp is what makes the port cheap to maintain: when the
upstream PR merges, most of this repository can be deleted.

---

## 1. What is upstream right now

| PR | Repo | Contents | State |
|---|---|---|---|
| [#10619](https://github.com/armbian/build/pull/10619) | `armbian/build` | `config/boards/xc3399fr.csc` + `rk3399-xc3399fr.dts` for rockchip64 6.18 / 7.2 / 7.3 | open, mergeable, awaiting review |
| [#440](https://github.com/armbian/armbian.github.io) | `armbian/armbian.github.io` | board assets (photo, description) | open, awaiting review |

`#440` is the blocker, not the code. The only failing check on `#10619` is
`Verify assets for newly added boards`, which fails until the assets exist in
the website repo. Nothing in the board port itself is contested.

**Do not add anything to #10619 to "improve" it.** It is four files - one 20
line board config and three identical device trees - which is exactly the shape
Armbian reviewers expect for a board port. Every extra line is review friction.

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

## 3. Divergence from upstream, and why each item exists

The device trees in `userpatches/kernel/` are **byte-identical** to the ones in
PR #10619. Keep them that way. If you change one, change both, or the port
starts drifting and the eventual merge becomes a merge conflict.

`userpatches/config/boards/xc3399fr.csc` differs from upstream in exactly four
ways, all deliberate:

| Difference | Reason |
|---|---|
| `KERNEL_TARGET="current"` (upstream: `current,edge,bleedingedge`) | Customers get the LTS kernel the board was validated on. Upstream offers the others so testers can use them. |
| `post_family_tweaks__xc3399fr_watchdog` | The RK3399 watchdog exists and the kernel exposes `/dev/watchdog0`, but nothing feeds it. On an unattended 24/7 box a kernel hang would otherwise be permanent. **No Armbian board sets `RuntimeWatchdogSec`** - it is not a convention, so it does not belong in the board PR, but it is right for this product. |
| Comment block explaining why no smartd config is shipped | Documentation only. An earlier revision configured `smartd` for the USB-SATA bridge; it was removed once testing showed the config did not actually work and could not be made generic (`install.md`). |
| Comment block explaining why `usbstoragequirks` is unset | Documentation only. There is no third hook: an earlier revision pinned the formerly-bundled `7825:a2a4` bridge to BOT, and it was removed when the cable stopped shipping. |

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

## 4. When PR #10619 merges

1. Delete `userpatches/kernel/archive/rockchip64-*/dt/rk3399-xc3399fr.dts` -
   the device tree then comes from Armbian.
2. Reduce `userpatches/config/boards/xc3399fr.csc` to the watchdog hook plus the
   `KERNEL_TARGET` override. The build framework merges `userpatches` over the
   shipped board config, so the rest is redundant.
3. Keep every document in `docs/`. The measurements and the refuted hypotheses
   are the part that took the time; they do not become obsolete when the code
   moves upstream.
Nothing else is pending upstream. Section 2 records the one change that was
considered and deliberately not sent.

# RF-0012 Retail Test Runbook

Feature: `026-canonical-idempotent-corrections` — canonical idempotent dispute
corrections.

Status: **READY FOR MANUAL RETAIL TESTING** (no observation has been executed
yet).

This runbook is the operator guide for the manual multi-client Retail
validation required by T041. It is usable directly during a WoW session. It
does **not** activate the feature for players: the canonical correction path
stays closed in the stable release, and the pre-release candidate used for
this session is the only build in which it can be exercised.

The observation record itself lives in
[rf-0012-retail-validation.md](rf-0012-retail-validation.md). This runbook
tells you what to do; that file tells you what to write down.

---

## 0. Before you start — read this

| Rule | Why |
|---|---|
| Use a **dedicated test guild** only. | The validation creates and corrects real ledger rows. |
| Use **test characters** only. | No live production accounting may be touched. |
| Never point a client at a player's real `RCLootCouncil_dibsDB`. | The validation writes guild-scoped accounting. |
| Take a **backup on every client** before a destructive scenario. | The scenarios deliberately corrupt projections. |
| Keep the **stable release** out of the test guild. | It must stay closed and must visibly refuse. |
| A test that cannot be performed is recorded as `PENDING`, never as `PASS`. | A simulated result is not a Retail result. |

---

## 1. Prepare the environment

### 1.1 Guild and roster

Create a dedicated test guild with at least four characters:

| Slot | Rank needed | Purpose |
|---|---|---|
| Coordinator | Guild Master | The only client that accepts a canonical correction. |
| Officer | Officer | Proposes corrections; must never accept one locally. |
| Follower | Member | Compatible client. Receives and projects commits. |
| Reconnecting | Member | Goes offline before a correction, reconnects after. |

Verify the roster inside the game: the Officer must be a real guild officer
(rank index 1) and the Coordinator a real Guild Master (rank index 0). A
claimed role is not authority; the addon reads the live roster.

### 1.2 Accounts and permissions

Each character needs a **separate game account** (or a separate WoW game
directory) so that each client has its own independent SavedVariables. Four
characters on one account share one SavedVariables file and would make the
convergence observations meaningless.

### 1.3 Build the pre-release candidate

The canonical path is release-controlled by the constant
`Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED` in `src/Core.lua`.

- **Stable release**: the constant is `false`. It cannot be enabled at
  runtime. Use it as the *incompatible peer* in scenario S4.
- **Pre-release candidate**: the constant is `true`. The release owner
  changes that one line and builds. There is **no** runtime toggle, no slash
  command, and no SavedVariables value that opens the path.

> The candidate must be a build that only the release owner produces. Do not
> hand-edit an installed addon folder to flip the flag for a shared build; the
> flag is meant to change only in a reviewed source revision.

### 1.4 Copy the addon into the WoW test environment

Find the interface directory of each test client:

| Platform | Path |
|---|---|
| Windows | `<WoW install>\Interface\AddOns\` |
| macOS | `~/Library/Application Support/World of Warcraft/Interface/AddOns/` |
| Linux (Wine) | `<prefix>/drive_c/users/<user>/Documents/My Games/World of Warcraft/Interface/AddOns/` |

The repository ships the addon sources under `src/`. The packaged addon
directory must contain:

```text
RCLootCouncil_dibs/
├── RCLootCouncil_dibs.toc
├── embeds.xml
├── Core.lua
├── locales/
├── modules/
├── integrations/
└── ui/
```

That is exactly the content of `src/`. Copy the **contents** of `src/` into
the `RCLootCouncil_dibs/` addon folder, so that
`RCLootCouncil_dibs/RCLootCouncil_dibs.toc` exists.

```powershell
# Example for a Windows test client
$source = 'C:\path\to\RCLootCouncil_dibs\src'
$target = 'C:\Games\World of Warcraft\Interface\AddOns\RCLootCouncil_dibs'
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Path $target | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force
```

Nothing is deployed automatically. Copy, then start WoW manually.

> Verify the load order in `RCLootCouncil_dibs.toc` before the first client
> starts. The order is fixed: `embeds.xml`, `Core.lua`, `locales/enUS.lua`,
> `locales/frFR.lua`, then `modules/`, then `integrations/`, then `ui/`.
> `Core.lua` defines `Dibs` and the release flag; `modules/Ledger.lua` and
> `modules/SyncV2.lua` depend on it. A reordered TOC breaks the addon.

### 1.5 Verify the addon loads

On **each** client, before any scenario:

1. Start WoW and log into the test guild.
2. Type `/dibs overview` and confirm the addon answers.
3. Type `/dibs help` and confirm the command list appears.
4. Open the Officer window (`/dibs officer`) and confirm it renders.

If the addon failed to load, WoW shows a Lua error on the login screen. A
`has more than 60 upvalues` error means a Lua 5.1 compilation limit was hit.
Reproduce it offline with:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\powershell\Test-DibsLua51Compilation.ps1 -LuacPath <path-to-luac-5.1.exe>
```

**PASS** = the addon answers `/dibs overview` on every client and no Lua
error appeared at login.

#### Building a Lua 5.1.5 compiler (reproducible)

The guard needs a **real** Lua 5.1 compiler. Lua 5.4 is not a substitute:
it does not reproduce the 60-upvalue ceiling. Build the upstream 5.1.5
source with MSVC.

1. Download the official tarball and **verify its SHA-256 against the
   value published on <https://www.lua.org/ftp/>** before building:

   ```powershell
   $expected = '2640FC56A795F29D28EF15E13C34A47E223960B0240E8CB0A82D9B0738695333'
   Invoke-WebRequest -Uri 'https://www.lua.org/ftp/lua-5.1.5.tar.gz' -OutFile "$env:TEMP\lua-5.1.5.tar.gz"
   if ((Get-FileHash "$env:TEMP\lua-5.1.5.tar.gz" -Algorithm SHA256).Hash -ne $expected) {
     throw 'Lua 5.1.5 checksum mismatch; refusing to build.'
   }
   tar -xzf "$env:TEMP\lua-5.1.5.tar.gz" -C $env:TEMP
   ```

   The published value is the SHA-256
   `2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333`
   for a 221 213-byte file. Do not build an unverified tarball.

2. Build `luac` with the Visual Studio Build Tools. The `src/` folder
   holds two `main` definitions (`lua.c` and `luac.c`), so build the
   compiler only and include `loadlib.c` and `print.c`:

   ```bat
   call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
   cd /d %TEMP%\lua-5.1.5\src
   cl /nologo /O2 /DLUA_USE_WINDOWS /DNO_WINDOWS_OLD /D_CRT_SECURE_NO_DEPRECATE ^
      lapi.c lcode.c ldebug.c ldo.c ldump.c lfunc.c lgc.c llex.c lmem.c lobject.c ^
      lopcodes.c lparser.c lstate.c lstring.c ltable.c ltm.c lundump.c lvm.c lzio.c ^
      lauxlib.c lbaselib.c ldblib.c liolib.c lmathlib.c loslib.c ltablib.c lstrlib.c ^
      linit.c loadlib.c print.c luac.c /Fe:luac51.exe /link /INCREMENTAL:NO
   ```

3. Confirm the version and run the guard:

   ```powershell
   & "$env:TEMP\lua-5.1.5\src\luac51.exe" -v
   # Lua 5.1.5  Copyright (C) 1994-2012 Lua.org, PUC-Rio
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\powershell\Test-DibsLua51Compilation.ps1 -LuacPath "$env:TEMP\lua-5.1.5\src\luac51.exe"
   ```

The guard is **skipped, never silently passed**, when no Lua 5.1
compiler is available, and it exits non-zero on a file that exceeds the
limit.

### 1.6 If a Lua 5.1 error appears at login

A Retail client can report a Lua error at login that the automated suite
cannot see, because Fengari is a Lua 5.4-compatible interpreter and does not
reproduce the Lua 5.1 upvalue ceiling of 60. The message looks like:

```text
1x LUA_WARNING: RCLootCouncil_dibs/ui/OfficerUI.lua:1
RCLootCouncil_dibs/ui/OfficerUI.lua:8362: function at line 4982 has more than 60 upvalues
```

The **definition line** in that message identifies the deployed build. If the
deployed copy is older than the current source, the line numbers will not
match the current file, and the deployed copy must be refreshed:

1. Re-copy the current `src/` content into
   `Interface\AddOns\RCLootCouncil_dibs\` (section 1.4).
2. Confirm the copy took effect by checking the deployed file's size and
   timestamp, and by searching it for the extracted function:

   ```powershell
   $deployed = 'C:\Games\World of Warcraft\Interface\AddOns\RCLootCouncil_dibs\ui\OfficerUI.lua'
   Select-String -Path $deployed -Pattern 'local function renderOfficerRoute|local function renderRoute'
   ```

   The current source has a thin `renderRoute` wrapper that delegates to
   `renderOfficerRoute`. A deployed copy that still has one large
   `renderRoute` is stale.
3. Verify the deployed copy itself compiles under Lua 5.1:

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\powershell\Test-DibsLua51Compilation.ps1 `
       -Root 'C:\Games\World of Warcraft\Interface\AddOns\RCLootCouncil_dibs' `
       -LuacPath <path-to-luac-5.1.exe>
   ```

   Point `-Root` at the deployed addon folder, not the repository. The guard
   expects a `src` subfolder; for a deployed addon, point it at the folder
   that contains `ui/`, `modules/`, and `Core.lua`.
4. `/reload` and confirm the error is gone.

A stale deployed build is the most common cause of an error that the
repository no longer reproduces. Always compare the **definition line** in
the message against the current source before investigating further.

---

## 2. Prepare the four clients

On each client, in this order:

1. `/dibs season create` (Coordinator only) — create a test season.
2. `/dibs season list` — note the season id; use it for every grant below.
3. `/dibs grant <Character> 10` (Coordinator only) — give the Follower and
   the Reconnecting member a synthetic balance to correct later.
4. `/dibs backup` (Coordinator only) — take a guild backup. Repeat on every
   client so each has a restore point.

Record the following for each client before starting:

| Field | Coordinator | Officer | Follower | Reconnecting |
|---|---|---|---|---|
| Character name | | | | |
| Addon version (`/dibs overview` shows it) | | | | |
| Build type (candidate / stable) | | | | |
| Season id | | | | |
| Starting balance of each test character | | | | |

**PASS** = every client loads, reports the same addon version, and a backup
exists on each.

---

## 3. Scenario order

Run the scenarios in this order. Each one depends on the state left by the
previous one. If a scenario fails, **stop**, record the failure in the
observation file, and restore the affected client from its backup before
continuing.

| ID | Scenario | Client | Observations covered |
|---|---|---|---|
| S1 | Authority and permission check | All | 1 |
| S2 | Officer proposes a correction | Officer | 2 |
| S3 | Coordinator accepts the correction | Coordinator | 3, 4, 5, 6, 7, 17 |
| S4 | Follower receives the commit | Follower | 8, 9 |
| S5 | Incompatible client stays behind | Stable client | 14 |
| S6 | Gap and catch-up | Reconnecting | 10, 11, 12 |
| S7 | Duplicate delivery is idempotent | Follower | 9 |
| S8 | Conflicting operation is refused | Coordinator | 16 |
| S9 | Unverifiable original is refused | Coordinator | 17 |
| S10 | Stale epoch and wrong ledger are refused | Coordinator | 15 |
| S11 | Reload recovery and projection rebuild | Coordinator | 12, 13 |
| S12 | Historical report is read-only | Coordinator | 18 |
| S13 | Officer UI status and reason | Officer | 19 |
| S14 | Guild and privacy isolation | All | 20 |

---

## 4. Scenario details

For every scenario: **preconditions**, **actions**, **expected result**,
**failure result**, **data to collect**, **how to return to the initial
state**. Those six parts are required for every observation.

### S1 — Authority and permission check

- **Preconditions:** all four clients online in the test guild, candidate
  build installed on Coordinator, Officer, and Follower.
- **Actions:**
  1. On the Coordinator, open the Officer window, then **Synchronization**.
  2. Confirm the displayed coordinator name is the actual Guild Master.
  3. On the Officer, open the Officer window and confirm the request queue
     is visible but the Guild Configuration actions are not.
  4. On the Follower, confirm the same request is **not** visible.
- **Expected:** the Coordinator sees the real Guild Master as coordinator; the
  Officer sees a read-only officer view; the Follower sees nothing.
- **Failure:** a different name is shown as coordinator, or the Follower sees
  the request, or the Officer can reach Guild Configuration.
- **Collect:** the coordinator display name per client; a screenshot of the
  Synchronization page.
- **Reset:** none needed; this scenario changes nothing.

### S2 — Officer proposes a correction

- **Preconditions:** S1 passed. A request exists that references a real
  transaction id. To get one, note a transaction id from the ledger
  (`/dibs history` on the Coordinator) and file a report that references it.
- **Actions:**
  1. On the **Follower**, create a report about a real transaction (Requests
     view, attach the transaction).
  2. On the **Officer**, open the request. Note the request id and the
     **revision** shown in the detail header.
  3. On the **Officer**, use **Adjust Dibs**, enter the amount, enter a
     reason, tick the acknowledgement, press **Review**, then **Confirm
     action**.
  4. Immediately record the Officer's balance and the transaction count
     before and after.
- **Expected:** the Officer's own client does **not** change any balance and
  does not append a transaction. The request shows as still open on the
  Officer, with a proposal sent to the coordinator. The Officer sees no
  "saved" or "synchronized" wording.
- **Failure:** the Officer's balance changes, a transaction appears on the
  Officer, or the Officer reports the correction as accepted.
- **Collect:** the request id; the request revision; the Officer's balance
  before and after; the Officer's transaction count before and after; the
  exact refusal or pending wording shown.
- **Reset:** none needed; the Officer must not have changed anything. If it
  did, restore that client from its backup.

### S3 — Coordinator accepts the correction

- **Preconditions:** S2 passed and the request is visible on the Coordinator.
- **Actions:**
  1. On the **Coordinator**, open the same request. Confirm the revision is
     the one the Officer proposed.
  2. Use **Adjust Dibs**, enter the amount, enter a reason, tick the
     acknowledgement, press **Review**, then **Confirm action**.
  3. Record the visible outcome label and its full explanation text.
  4. Record the affected character's balance and the transaction count.
  5. Record the canonical state: epoch, sequence, and root hash. They are
     visible in the Officer window under Synchronization, or through the
     Diagnostics page.
  6. Open the ledger history of the corrected character and confirm the
     original row is still present and unmodified.
- **Expected:** exactly **one** new transaction appears. The original
  transaction is unchanged. The canonical sequence advanced by exactly one
  and the root hash changed once. The visible outcome is one of
  *Accepted in Session*, *Replayed*, or *Rejected* — never a claim that the
  change was saved to disk or received by everyone.
- **Failure:** two or more transactions, a modified original row, a sequence
  that advanced by more than one, or a wording that claims a disk save or a
  guild-wide receipt.
- **Collect:** the request id and revision; the outcome label and explanation
  verbatim; the balance before and after; the transaction count before and
  after; the epoch, sequence, and root hash before and after; a screenshot of
  the outcome panel and of the ledger history.
- **Reset:** the Coordinator's `/dibs backup` taken in section 1.5.

### S4 — Follower receives the commit

- **Preconditions:** S3 passed.
- **Actions:**
  1. On the **Follower**, wait for the commit to arrive. Watch the
     Synchronization page.
  2. Record the Follower's epoch, sequence, and root hash.
  3. Record the Follower's balance for the corrected character and its
     transaction count.
  4. Confirm the Follower's ledger history shows the same new transaction id
     as the Coordinator's.
- **Expected:** the Follower's epoch, sequence, root hash, balance, and
  transaction id are **identical** to the Coordinator's. The Follower reports
  itself as current; it does not report a gap.
- **Failure:** the Follower shows a different balance, a different sequence, a
  different root hash, or a different transaction id, or it stays behind.
- **Collect:** the Follower's epoch, sequence, root hash, balance, and
  transaction id; the Coordinator's matching values.
- **Reset:** none needed.

### S5 — Incompatible client stays behind

- **Preconditions:** S4 passed. A **stable** release client is installed on a
  fifth character in the same guild.
- **Actions:**
  1. On the **stable** client, open Synchronization.
  2. Record the client status and the peer list.
  3. Create and accept one more small correction on the Coordinator.
  4. Re-check the stable client's status.
- **Expected:** the stable client does **not** advertise the
  `ledgerOperationCommit` capability. It refuses the operation record with an
  explicit diagnostic, applies **no part** of it, and shows a visible
  behind/incompatible status. It does not silently apply the familiar parts.
- **Failure:** the stable client applies the correction, shows no status, or
  claims to be current.
- **Collect:** the stable client's status text and diagnostic; a screenshot.
- **Reset:** none needed.

### S6 — Gap and catch-up

- **Preconditions:** S4 and S5 passed.
- **Actions:**
  1. Take the **Reconnecting** member offline (log out or disconnect).
  2. On the Coordinator, accept one more correction. Note the new sequence.
  3. Bring the Reconnecting member back online.
  4. Wait for the catch-up, then record its epoch, sequence, root hash,
     balance, and transaction count.
  5. Trigger a reload on the Reconnecting member (`/reload`) and record the
     values again.
- **Expected:** the Reconnecting member applies the missing commits **in
  order** and converges to the Coordinator's epoch, sequence, root hash, and
  balance. After the reload the values are unchanged and no transaction is
  duplicated.
- **Failure:** the Reconnecting member applies the commit out of order, shows
  a permanent gap, has a different balance or root hash, or has a duplicated
  transaction after the reload.
- **Collect:** the Reconnecting member's epoch, sequence, root hash, balance,
  and transaction count before, after the catch-up, and after the reload; the
  Coordinator's matching values.
- **Reset:** the Reconnecting member's backup if the catch-up failed.

### S7 — Duplicate delivery is idempotent

- **Preconditions:** S4 passed.
- **Actions:**
  1. On the Coordinator, re-submit **the same** correction for the same
     request and revision.
  2. Record the outcome label.
  3. Record the transaction count and the canonical sequence.
- **Expected:** the outcome is **Replayed**. The transaction count does not
  change, the sequence does not advance, and the balance does not change.
- **Failure:** a second transaction appears, or the sequence advances, or the
  outcome is not Replayed.
- **Collect:** the outcome label; the transaction count and sequence before
  and after.
- **Reset:** the Coordinator's backup if a second transaction appeared.

### S8 — Conflicting operation is refused

- **Preconditions:** S7 passed.
- **Actions:**
  1. On the Coordinator, attempt a correction for the same request with a
     **different** amount than the accepted one.
  2. Record the refusal reason.
- **Expected:** the attempt is refused with an explicit conflict reason. No
  balance, transaction, sequence, or root hash changes.
- **Failure:** the second amount is applied, or the refusal has no reason.
- **Collect:** the refusal reason verbatim; the balance, transaction count,
  sequence, and root hash before and after.
- **Reset:** the Coordinator's backup if a change was applied.

### S9 — Unverifiable original is refused

- **Preconditions:** S8 passed.
- **Actions:**
  1. On the Coordinator, file a new report that references a transaction id
     that does **not** exist.
  2. Attempt a balance correction on it.
  3. Record the refusal reason and the balance before and after.
- **Expected:** the correction is refused with an explicit reason that names
  the missing original. No balance, transaction, sequence, or root hash
  changes, and the dossier does not become resolved.
- **Failure:** the correction applies, or the dossier resolves anyway.
- **Collect:** the refusal reason verbatim; the before/after values.
- **Reset:** the Coordinator's backup.

### S10 — Stale epoch and wrong ledger are refused

- **Preconditions:** S9 passed. A second approved ledger exists
  (**Guild Configuration → Guild Ledgers**) if the guild has one.
- **Actions:**
  1. On the Coordinator, attempt a correction whose original transaction
     lives in the other ledger while a different ledger is active.
  2. Record the refusal reason.
  3. If a coordinator handoff is available in the test guild, repeat after
     the handoff so the epoch changes.
- **Expected:** each attempt is refused with an explicit reason naming the
  scope or epoch problem. Nothing is written to the active ledger, and no
  balance changes anywhere.
- **Failure:** the correction is applied to the active ledger, or the ledger
  scope is silently changed.
- **Collect:** the refusal reasons verbatim; the before/after balances and
  transaction counts per ledger.
- **Reset:** the Coordinator's backup.

### S11 — Reload recovery and projection rebuild

- **Preconditions:** S10 passed.
- **Actions:**
  1. On the Coordinator, note the transaction count, the balance, the
     canonical sequence, and the root hash.
  2. Type `/reload`.
  3. After the reload, record the same four values and the operation state
     shown in the Officer window.
  4. Check the Synchronization page for a visible recovery classification.
- **Expected:** the same values are still present. The operation state is
  reported as observed after reload or recovered, and never as
  "persistence unconfirmed" once the reload has observed it. No second
  canonical commit is created.
- **Failure:** a value is lost, a duplicate commit appears, or the state is
  reported as current without verification.
- **Collect:** the four values before and after; the operation state text; the
  recovery classification text.
- **Reset:** the Coordinator's backup.

### S12 — Historical report is read-only

- **Preconditions:** S11 passed.
- **Actions:**
  1. On the Coordinator, open the historical correction report (Diagnostics
     or the History page, per the officer guide).
  2. Record the classification counts shown.
  3. Record the transaction count, the balance, the sequence, and the root
     hash before and after opening the report.
- **Expected:** the report classifies the candidates (complete, partial,
  ambiguous, local-only, unverifiable) and applies nothing. The four values
  are unchanged. No historical transaction is edited.
- **Failure:** the report applies a correction, a balance moves, or a
  historical row changes.
- **Collect:** the classification counts; the before/after values; a
  screenshot of the report.
- **Reset:** the Coordinator's backup.

### S13 — Officer UI status and reason

- **Preconditions:** S12 passed.
- **Actions:**
  1. On the **Officer**, open the request detail in the **narrow** window
     layout, then widen the window.
  2. Confirm the status and its reason are fully readable in both widths.
  3. Open the historical report view and confirm every classification has
     its own visible label and that the report is marked read-only.
  4. Confirm the empty state when there is no correction candidate.
- **Expected:** no clipped or ambiguous status, the reason is plain visible
  text (not only a hover tooltip), each classification has a distinct label,
  and the empty state is explicit.
- **Failure:** the status is truncated, the reason is only reachable by
  hovering, two classifications share a label, or the empty state is blank.
- **Collect:** screenshots of the narrow and wide layouts, the outcome panel,
  the historical report, and the empty state.
- **Reset:** none needed.

### S14 — Guild and privacy isolation

- **Preconditions:** S13 passed.
- **Actions:**
  1. Note the request id from S2.
  2. On the **Follower** (a different guild, if available) and on a character
     in another guild, try to read that request id.
  3. On the Officer, open a request in a live raid and confirm no loot
     candidate, vote, or session data appears in the correction view.
- **Expected:** the request is not readable outside its guild. The correction
  view exposes no live loot candidate, vote, or session data.
- **Failure:** a dossier is readable from another guild, or live loot data
  appears in the correction view.
- **Collect:** the result of the cross-guild read; a screenshot of the
  correction view.
- **Reset:** none needed.

---

## 5. Collecting diagnostics

Every observation needs the same evidence so two runs can be compared.

**In-game, on the client that observed the event:**

- `/dibs overview` — the addon version and the current operational summary.
- `/dibs debug report` — the built-in debug report. It contains the addon
  version, the SavedVariables schema version, the guild key, and the service
  states. Copy it into the observation notes.
- `/dibs sync report <Character>` — the synchronization report for one peer.
  It shows the protocol major/minor, the advertised capabilities (including
  whether `ledgerOperationCommit` is present), and the sync state.
- `/dibs readiness` — the readiness report with the current blockers and
  warnings.
- The Officer window → **Synchronization** — the coordinator name, the peer
  list, and the client state (current, behind, or incompatible).
- The Officer window → **Diagnostics** — the Data Health Dashboard, which
  reports persistence, readiness, RCLootCouncil, synchronization, and backup
  health.

**On disk:** the client SavedVariables files, one per client. Copy them
*after* the session, and keep them as the raw evidence for the observations.
They contain the guild ledger, the dispute dossiers, the canonical commits, and
the operation states. Do not edit them.

**Screenshots:** the outcome panel, the ledger history, the Synchronization
page, the Diagnostics page, the historical report, and the narrow and wide
layouts.

---

## 6. Identifying divergences

Compare the coordinator and each follower on these six values. A difference
in any of them is a divergence, and the first one that differs is where the
investigation starts.

| Value | Where to read it |
|---|---|
| Canonical epoch | Synchronization / Diagnostics |
| Canonical sequence | Synchronization / Diagnostics |
| Root hash | Synchronization / Diagnostics |
| Balance of each affected character | `/dibs balance` or the Officer window |
| Transaction ids of the corrected rows | Ledger history |
| Operation id of the accepted operation | The request detail, and the commit |

Common divergences and their first checks:

| Symptom | First check |
|---|---|
| Follower is behind | `/dibs sync report <Coordinator>` — is the `ledgerOperationCommit` capability present on both sides? |
| Follower is behind but capable | Is the sequence gap visible? Does the follower show a behind reason? |
| Balance differs, sequence matches | A projection is missing. Run the recovery classification and check the index. |
| Sequence differs | A commit was applied out of order, or a duplicate was appended. |
| Root hash differs with the same sequence | The hash chain diverged; do not repair it manually. |
| Operation id differs | The same correction was proposed twice with different identities. |
| Client reports current but the values differ | A visibility bug: the state is reported without verification. |

Never repair a divergence by hand-editing SavedVariables. Restore the client
from its backup and report the observation.

---

## 7. Returning to the initial state

The validation must leave the test guild as it was found.

1. **Restore each client from its backup** taken in section 1.5, using
   **Guild Configuration → Backups** (or the Officer window's backup page).
   Use the **preview** before confirming, and read what it says is kept
   local.
2. **Reload** every client after the restore and confirm the balances and the
   transaction counts are the recorded starting values.
3. **Delete the synthetic requests** if the dossier list still shows them,
   and confirm no terminal dossier was lost.
4. **Archive the test season** rather than deleting it, so the history stays
   auditable.
5. **Remove the candidate build** from the test clients and reinstall the
   stable release, then confirm the stable client again refuses the
   canonical path.
6. **Keep the SavedVariables copies** as the raw evidence. Do not delete them
   before the observations are written up.

---

## 8. PASS / FAIL criteria

### A scenario is PASS when

- the expected result was observed verbatim on the specified client;
- the collected data is complete for every value the scenario names;
- the recorded failure condition did **not** occur;
- no unexpected balance, transaction, sequence, or root-hash change was
  observed anywhere.

### A scenario is FAIL when

- the expected result did not occur;
- a refusal, error, or Lua error appeared that the scenario did not expect;
- a balance, transaction count, canonical sequence, or root hash changed when
  the scenario said it must not;
- the client reported a state it had not verified;
- any data required by the scenario could not be collected.

### A scenario is PENDING (not FAIL) when

- the required character, rank, peer, or build was not available;
- the environment prevented the step (for example the stable build was not
  installed on a peer);
- the step was not reached because an earlier scenario failed.

A `PENDING` observation is **not** a pass. It keeps T041 open.

### Criteria that block the release

Any of the following blocks the release regardless of the other results:

| Blocker | Why |
|---|---|
| Any scenario is FAIL. | A data-integrity or convergence defect is proven. |
| Any observation that must be executed is PENDING. | The Retail gate is not met (FR-041). |
| The stable release can be made to accept a canonical correction. | The activation lock is broken (FR-028). |
| A client applied only part of a correction. | The all-or-reject rule is broken (FR-009). |
| A client applied a correction twice. | Idempotence is broken (FR-012). |
| The original transaction was modified. | Append-only history is broken (FR-015). |
| A cross-guild dossier was readable. | Guild isolation is broken (FR-038). |
| The Lua 5.1 compilation guard fails. | The addon does not load in Retail. |
| An out-of-order commit was applied. | The sequence rule is broken (FR-027). |

---

## 9. Observation tracker

Copy this table into the observation file
([rf-0012-retail-validation.md](rf-0012-retail-validation.md)) and fill it in
during the session. One row per observation.

| # | Observation | Client | Preconditions met | Result | Evidence collected | Reset done |
|---|---|---|---|---|---|---|
| 1 | Guild identity and rank resolved | | | PENDING | | |
| 2 | Officer proposal created, no local effect | | | PENDING | | |
| 3 | Proposal identity preserved at the coordinator | | | PENDING | | |
| 4 | One canonical commit, one transaction | | | PENDING | | |
| 5 | Original history preserved | | | PENDING | | |
| 6 | Commit announced without a later fetch | | | PENDING | | |
| 7 | Coordinator balance matches the approved correction | | | PENDING | | |
| 8 | Follower converged on epoch, sequence, root, balance | | | PENDING | | |
| 9 | Duplicate delivery changed nothing | | | PENDING | | |
| 10 | Out-of-order commit refused, behind state visible | | | PENDING | | |
| 11 | Reconnecting member caught up in order | | | PENDING | | |
| 12 | Reload retained the accepted operation | | | PENDING | | |
| 13 | Interrupted projection rebuilt, one commit | | | PENDING | | |
| 14 | Incompatible client refused and stayed behind | | | PENDING | | |
| 15 | Stale epoch and wrong ledger refused | | | PENDING | | |
| 16 | Conflicting operation id refused | | | PENDING | | |
| 17 | Unverifiable original refused | | | PENDING | | |
| 18 | Historical report read-only | | | PENDING | | |
| 19 | Outcome and reason visible in the UI | | | PENDING | | |
| 20 | No live loot or cross-guild data exposed | | | PENDING | | |

**All twenty rows must read `PASS` before T041 can be closed, and before the
release version is incremented (T042) or the release flag is enabled (T043).**

---

## 10. Quick reference — the commands used in this runbook

Every command below exists in `src/Core.lua` (`Dibs.HandleSlashCommand`). No
command in this runbook is invented.

| Command | What it does |
|---|---|
| `/dibs help` | Lists the available commands. |
| `/dibs overview` | One-line operational summary. |
| `/dibs season create` / `/dibs season list` | Manage test seasons. |
| `/dibs grant <Character> <amount>` | Give a synthetic allocation. |
| `/dibs balance` | Show the local balance. |
| `/dibs history` | Show the audit history. |
| `/dibs backup` | Create a backup. |
| `/dibs data` | Open the data page (backup, restore, import/export). |
| `/dibs officer` | Open the Officer window. |
| `/dibs requests` | Open the player Requests view. |
| `/dibs review` | Open the officer review queue. |
| `/dibs readiness` | Open the readiness report. |
| `/dibs sync report <Character>` | Synchronization report for one peer. |
| `/dibs sync probe <Character>` | Send a synchronization probe. |
| `/dibs debug report` | Built-in debug report for the issue tracker. |
| `/dibs debug logs` | Open the log window. |
| `/dibs sync repair <Character\|guild>` | Request a non-destructive recovery. |
| `/reload` | WoW reload; used to observe persistence and recovery. |

`/dibs sync repair` is non-destructive, but it is only used when a scenario
explicitly asks for a catch-up, and the observation file records it.

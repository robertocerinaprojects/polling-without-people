## Script 16
### Purpose: Aggregate 2024 House election results to CD-level vote shares

Process MIT Election Lab's 2024 House results into CD-level vote counts and shares. These shares serve as the dependent variable (outcome) in the CART inheritance model, which learns the demographics-to-vote mapping from 2024 CDs and applies it to 2026 CDs.

Split across two sub-scripts:
- **Script 16A**: Aggregate vote counts by CD; produces `dem_votes`, `rep_votes`, `other_votes`, `total_house_votes`
- **Script 16B**: Convert counts to shares using CD voting-age population as denominator; produces `dem_share`, `rep_share`, `other_share`, `no_vote_share` (all four sum to 1 per CD)

### Inputs

| Source | File | Description |
|---|---|---|
| MIT Election Data and Science Lab | `1976-2024-house.tab` | 33,805 rows of U.S. House election results from 1976-2024 |
| MIT Election Data and Science Lab | `codebook-us-house-1976-2024.md` | Codebook for the above |
| Script 15 | `cd_demographics.rds` | Provides `cd_pop` denominator for Script 16B |

MIT dataset available at: https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/IG0UN2

### Output

`cd_house_2024.rds` — 435 rows, one per state-district combo for 2024.

| Column | Type | Description |
|---|---|---|
| state_cd | character | "TX-1", "CA-12", etc. Matches PUMS/CES harmonization |
| dem_votes | integer | Total Democratic votes in CD |
| rep_votes | integer | Total Republican votes in CD |
| other_votes | integer | Third party + independent + write-in votes |
| total_house_votes | integer | dem + rep + other |
| dem_two_party_share | numeric | dem_votes / (dem_votes + rep_votes) (diagnostic column) |
| cd_pop | numeric | Citizen voting-age population from PUMS (joined in 16B) |
| dem_share | numeric | dem_votes / cd_pop |
| rep_share | numeric | rep_votes / cd_pop |
| other_share | numeric | other_votes / cd_pop |
| no_vote_share | numeric | (cd_pop - total_house_votes) / cd_pop |

---

### Script 16A — Vote count aggregation

#### Methodological decisions

**Party categorization (3-way: Dem / Rep / Other)**

The MIT dataset lists candidates by their ballot-designated party. These are mapped to three categories:

| Category | Parties included |
|---|---|
| dem | DEMOCRAT (48 states), DEMOCRATIC-FARMER-LABOR (Minnesota), DEMOCRATIC-NONPARTISAN LEAGUE (North Dakota) |
| rep | REPUBLICAN |
| other | Third parties (Libertarian, Green, Constitution, etc.), independents (Independent, Unaffiliated), fusion parties (Working Families, Conservative), write-ins with NA party |

DFL (Minnesota) and DNL (North Dakota) are state affiliates of the Democratic Party — they behave identically to DEMOCRAT for our purposes.

**Fusion tickets: candidate aggregation approach**

In fusion-voting states (NY, CT, NJ, SC), a single candidate can appear under multiple party labels on the ballot. For example, in NY a Democratic candidate might also appear under the WORKING FAMILIES party line. Each row in the MIT data represents votes received under one party line, so a candidate's total votes are split across multiple rows.

The naive approach — sum by party label — would count the WORKING FAMILIES votes as "Other," artificially inflating the third-party share and deflating the major-party share. In NY, this can misestimate the Democratic share by 2-5 percentage points per CD.

**Our approach** (Script 16A, Sections 3-6):

1. **Aggregate by candidate**: For each (state_cd, candidate), sum votes across all party lines.
2. **Identify primary party**: For each (state_cd, candidate), find the party under which they received the most votes. This is their "primary party."
3. **Map primary party to 3-way category**: Attribute the candidate's total vote count (from step 1) to their primary party's category (from step 2).

Example: If Jane Smith got 80,000 votes as DEMOCRAT and 5,000 as WORKING FAMILIES, we identify DEMOCRAT as her primary party and attribute the full 85,000 to "dem."

**Tradeoff**: "Primary party" is a heuristic. In rare edge cases (e.g., a true independent who happens to win more votes under a fusion party line than under the INDEPENDENT line), this could misclassify. Such cases are rare and the heuristic produces correct results in 99%+ of cases.

**Write-ins**

119 write-in rows in 2024 have `candidate = "WRITEIN"` and `party = NA`. Under the candidate-aggregation approach, all write-ins in a single CD get grouped together (they share the candidate name "WRITEIN"). Their primary party is NA, which maps to "other." Write-in totals are typically small (a handful to hundreds of votes per CD).

**At-large districts**

The MIT dataset uses `district = 0` for at-large states (AK, DE, ND, SD, VT, WY). Our PUMS/CES geography uses `district = 1` for the same states. We recode `district = 0 → 1` for consistency with the rest of the pipeline.

**DC exclusion**

DC has only a non-voting delegate, not a House seat. Excluded from `cd_house_2024`.

**Special elections and runoffs**

Filtered via `stage == "GEN"`. The 2024 data has 0 special elections and 0 runoffs, so no additional handling was needed. Any future re-runs on other years would need to inspect this.

#### Vote total validation

For each CD, `dem_votes + rep_votes + other_votes = total_house_votes`. The script confirms:

- 435 unique state_cd values (expected)
- No CDs with 0 total votes (or fully null rows)
- CD-per-state counts match known House delegation sizes
- Two-party Dem share distribution is sensible (top 5 most Dem and top 5 most Rep CDs look correct)

Edge-case diagnostics also flag:
- CDs with abnormally low total votes (< 50,000) — mostly at-large states with small populations
- CDs with 0 Democratic votes — no Democrat on ballot
- CDs with 0 Republican votes — no Republican on ballot, or California top-two Democrat-vs-Democrat races

---

### Script 16B — Vote shares with cd_pop denominator

#### Why cd_pop as denominator

Vote shares could be computed against `total_house_votes` (conditional on voting) or `cd_pop` (unconditional). With `cd_pop`:
dem_share     = dem_votes   / cd_pop
rep_share     = rep_votes   / cd_pop
other_share   = other_votes / cd_pop
no_vote_share = (cd_pop - total_house_votes) / cd_pop

All four shares sum to 1 per CD. This structure lets the CART model jointly predict all four outcomes — including the turnout component — as a proper simplex.

The alternative (conditional shares) can't express the turnout outcome and would need a separate model for `no_vote_share`. The 4-way approach against `cd_pop` is cleaner for the downstream CART step.

#### Steps

**Section 1**: Load `cd_house_2024.rds` (from 16A) and `cd_demographics.rds` (for `cd_pop`).

**Section 2**: Defensively drop any existing share columns (protects against re-runs), then attach `cd_pop` from `cd_demographics` via `left_join()` on `state_cd`. Compute the four shares.

**Section 3**: Validate. For each CD, the four shares should sum to 1.0 within floating-point tolerance.

**Section 4**: Diagnostic distributions. Print min/median/mean/max for each share across all 435 CDs.

**Section 5**: Save (overwrites `cd_house_2024.rds` with the added share columns).

### Validation findings

Expected properties confirmed on the final `cd_house_2024`:

| Check | Result |
|---|---|
| Row count | 435 |
| Unique state_cd values | 435 |
| dem_share + rep_share + other_share + no_vote_share per CD | 1.0 ± rounding |
| Zero missing values in shares | Confirmed |

Distribution notes:
- `no_vote_share` typically ranges 0.5-0.7, reflecting that most of the voting-age population doesn't vote in House elections (~40-50% turnout in a presidential year at CD level, lower than the presidential turnout because of undervoting further down the ballot).
- Uncontested CDs (0 votes for one major party) have inflated `no_vote_share` values because their `total_house_votes` is artificially low. These CDs are handled as "uncontested" via a separate contestation flag in a later script.

### Note on training eligibility

An earlier version of this pipeline included a `training_eligible` flag here (Script 16B). This was removed in favor of a later contestation flag with a different threshold (>10 votes for both major parties, plus known 2026 uncontested overrides). The flag is now added in a downstream script closer to the CART model itself.

`cd_house_2024` includes all 435 CDs regardless of contestation status. Filtering for training happens later.

### Downstream use

`cd_house_2024.rds` feeds into:
- The CART inheritance model (fit on 2024 CD data to learn demographics → vote share mapping)
- The 2026 CD prediction step (applies the fit CART to 2026 demographic frames)

The four share columns are the CART model's target variables.
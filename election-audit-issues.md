# Election data audit for Polling Without People

Reviewed 21 November 2026 against [main at commit `7f8d796`][commit]. District counts include 435 voting seats and the DC delegate.

**Two findings change 2026 data under the repository’s own rules.** DC counts a write-in-only candidate as a ballot nominee. Arizona credits marks for unqualified write-ins to Other. I found no substantive error in the checked 2024 returns, lineups, incumbency flags, or application of the district-boundary rules. Two small 2024 documentation corrections are listed below.

## 1. DC counts one extra Other nominee in 2026

The annual roster counts eligible named ballot nominees and explicitly excludes write-in-only candidates. The October House Clerk list includes David Solana as an independent. The DC Board of Elections puts him on its write-in list. The printed federal ballot offers Robert White (Democratic), Denise Rosado (Republican), and Kymone Freeman (Statehood Green). The rebuilt roster includes all four people. [Roster rule][roster-rule] · [Clerk list][clerk26] · [DC federal ballot][dc-ballot] · [DC write-in list][dc-writeins]

| District and field | Repository | Verified value |
|---|---:|---:|
| DC delegate, Democratic nominees | 1 | 1 |
| DC delegate, Republican nominees | 1 | 1 |
| DC delegate, Other nominees | 2 | **1** |
| Eligible nominees nationwide, including DC | 1,161 | **1,160** |

**Correction.** Record Solana as write-in-only in the Step 08 corrections table, verify the revised 2026 roster fingerprint, update the documented national nominee total, and rebuild the annual predictors. The affected predictor is `nominee_count` on DC’s Other row. Freeman gives Other ballot presence, so `lineup=DRO` and `on_ballot=1` for Other are correct. All three incumbency flags are zero. DC’s 2024 scenario uses its own 2024 roster. [Corrections table][corrections] · [Roster fingerprint][fingerprint] · [2026 predictor assignment][predictors]

## 2. Arizona’s 2026 Other vote includes disqualified write-ins

The 2026 results guide admits valid named write-ins and expressly excludes separately reported invalid ballots. The aggregation code assigns every source row coded `O` to Other. Arizona distinguishes **unofficial** write-ins, its category for invalid marks, from **unassigned** marks awaiting adjudication. Across nine House races, the manifest credits **3,972 unofficial marks** and **437 unassigned marks** to Other. The final disposition of those 437 cannot be inferred from this snapshot. [Results definition][returns-rule] · [Aggregation code][aggregation] · [Arizona procedures, chapter 10, pp. 243–245][az-manual]

**AZ-03 provides a direct test.** Maricopa County reported 3,306 write-in marks, then broke them out as 2,020 for qualified Republican write-in Jacob Parkman and 1,286 marked “NOT QUALIFIED.” Both numbers are separately identifiable in the repo’s source. Its Other total includes the 1,286 alongside the 9,068 and 7,782 votes for the two eligible minor-party candidates. [Maricopa canvass, AZ-03][maricopa] · [State results][az3-state] · [Pinned candidate rows][az-rows]

| AZ-03 outcome | Repository | Applying the documented eligibility rule |
|---|---:|---:|
| Democratic | 130,716 | 130,716 |
| Republican | 2,020 | 2,020 |
| Other | 18,136 | **16,850** |
| Counted candidate votes | 150,872 | **149,586** |

**Correction.** Preserve the published raw lines and raw contest total for reconciliation. Classify each line’s eligibility before summing candidate votes, and keep unresolved marks separately identifiable. In AZ-03 this raises the estimated `No Vote` count by **1,286** because the repository defines it as district citizen voting-age population (CVAP) minus counted candidate votes. Parkman’s votes correctly coexist with zero Republican ballot nominees.

## 3. Where the 2026 snapshot differs from election-office returns

The documented release freezes a Call the Map download and specifies two ranked-choice supplements. I matched the download’s SHA-256 to the documented hash and compared all **1,488 retained publisher rows** across the ten fields in the manifest. They agree. Re-adding the candidate lines also reproduces the reported totals for all **435 tabulated districts**. FL-10 is the unpolled exception. These checks establish what the file reproduces. State records show where it falls short as a benchmark for completed voting. [Snapshot policy and exceptions][snapshot] · [Publisher data dictionary][publisher] · [Pinned manifest][manifest]

| Area | Verified difference | Consequence for use |
|---|---|---|
| **Massachusetts** | Compared with the state’s nine district tables, the snapshot contains **89,871 fewer Democratic votes** across MA-02, MA-05, and MA-07, and **21,240 fewer Other votes** across all nine districts. The state reports “All Others” separately from blanks. In MA-02 it reports 234,345 for McGovern and 5,409 All Others, versus 198,782 and zero in the snapshot. [State tables][ma-all] · [MA-02 detail][ma2] | The difference of **111,111** candidate votes statewide carries directly into the estimated No Vote count. In MA-02 alone that residual is **40,972 too high** against the state return, or **7.05 percentage points** of the repo’s district CVAP. The repo faithfully copied the feed. The state pages do not establish when every comparison figure first became public. |
| **Florida** | **24 of 27** tabulated districts differ from certified returns. Repository minus state is **−576 Democratic, −121 Republican, +2,404 Other**, a net **+1,707** counted votes. In FL-05 the two major-party counts match, while the feed has 697 write-ins and the state has 26 for William Upham. [Official district results][fl-all] · [FL-05 detail][fl5] · [Certification timeline][fl-time] | Florida certified returns on November 17. The repo’s November 21 download retained earlier publisher counts marked `called`, as documented. A certified-results comparison should use the state figures. FL-10 correctly has four blank outcomes for its unpolled contest. |
| **Maine 2** | The pinned feed has 170,360 Republican, 164,855 Democratic, and zero write-ins. Municipal first choices included **123 declared write-ins**. The state ranked-choice tabulator’s opening round recorded **1,243 write-ins**, including undeclared write-ins, alongside 170,710 Republican and 165,178 Democratic votes. [State explanation][me-release] · [Tabulator summary][me-csv] · [Breakdown of the two definitions][me-rounds] | Maine came from the main feed. The guide specifies first choices for the explicitly supplemented contests, Alaska and DC. The Maine snapshot differs from each of the state’s tabulations. An official comparison needs a named round and a write-in definition before substituting counts. |
| **DC delegate** | The documented November 13 supplement contains **221,110** votes for three named candidates. By November 20, the same publisher showed **230,188** named-candidate votes. [Supplement definition][dc-policy] · [Publisher’s return][dc-ddhq] | The November 13 count and its limited write-in coverage follow the explicit exception. Updating it would create a newer snapshot. The ballot-roster error in section 1 is independent of these vote totals. |
| **California** | **39 of 52** district party totals match the compared state file. In the other 13, the later provisional file adds a net **11,370** candidate votes. [California election-office media files][ca-media] | The compared state file was stamped November 20 at approximately 10:32 p.m. Pacific, after the audited commit at 05:02 UTC on November 21. The difference is compatible with counts updating. |

## 4. The 2024 setup and two documentation corrections

The official 2024 House counts, statewide presidential counts, and presidential CVAP shares reproduce the repository’s recorded checksums. The original House map has **434 tabulated contests** and two unpolled contests, FL-20 and OK-03. The 2024 roster contains **1,069** eligible nominees. Annual district incumbent flags total **187 Democratic, 196 Republican, and zero Other** in 2024, and **183, 176, and one** in 2026. A flag records whether any nominee in that party group was serving on the relevant election eve, including service in a different district. [House returns][clerk24] · [Presidential returns][fec24] · [Checksums][checksums] · [Membership and roster rules][roster-rule]

| 2024 House shares on 2026 boundaries | What the published outputs do |
|---|---|
| **290 unchanged, tabulated districts** | Carry forward the 2024 nominees and counts. All 870 Democratic, Republican, and Other counts reconcile to the stored shares using district CVAP. Observed write-in votes can coexist with zero named nominees in a party group. |
| **144 redrawn districts** | Use 2026 nominees with incumbency measured on **November 4, 2024**. Applying the actual 2026 incumbency date would change flags in **22** of these districts. AL-01’s Jerry Carl correctly gets 1 in hypothetical 2024 and 0 in actual 2026. |
| **FL-20 and OK-03** | Use the sole incumbent 2024 winners, Sheila Cherfilus-McCormick and Frank Lucas. The redrawn FL-20 scenario transfers absent-party predictions to No Vote. OK-03 retained its footprint and keeps its small unadjusted Democratic and Other predictions. |

The boundary classifications and adjustments were checked against Census block overlaps and the tracked raw and final shares. These checks verify how the **146 modeled rows** were constructed. They cannot establish the vote that would have occurred in a hypothetical contest. The audit used the published model output without an independent Stan refit. [Scenario and structural-zero rules][scenarios] · [Published final shares][final24] · [Jerry Carl’s House service][carl]

- **Alabama, display rounding.** The handoff example prints **0.411615** for presidential No Vote. The underlying statewide figure is 1,584,579 ÷ 3,849,669 = 0.411614349…, which rounds to **0.411614**. Only the displayed example needs editing. [Handoff example][al-example] · [Recorded covariate checksum][checksums]
- **LA-01, withdrawal citation.** The corrections table correctly excludes Margueritte Swanson. Its linked FEC candidate list still lists her without a withdrawal annotation. The contemporary Louisiana voter guide explicitly records her withdrawal and supports the existing decision. [Correction row][la-row] · [FEC list, p. 31][la-fec] · [Louisiana voter guide][la-guide]

## 5. Which sources to use

**For a completed-election benchmark, prioritize a versioned state canvass for each district. For a study of what was known on November 21, keep the pinned Call the Map release.** Both datasets are useful. Publishing them separately preserves the timing of the original evaluation and lets a later user reproduce the score against completed counts. The FEC directs users to the state election offices for certification. At the audit date, the House Clerk’s national index listed 2026 nominees and the 2024 results volume. [State election office directory][state-offices] · [FEC guidance][fec-guidance] · [House Clerk index][clerk-index]

| Field | Preferred source and reason |
|---|---|
| **2026 district vote counts** | Use each state’s official general-election canvass once certified. Florida publishes downloadable Excel and delimited files. Massachusetts district tables publish candidate totals, All Others and blanks as distinct columns. California’s media files give machine-readable counts during the canvass. Record the update time and certification status of the version used. [Florida downloads][fl-download] · [Massachusetts results][ma-all] · [California files][ca-media] |
| **Write-in eligibility and ranked-choice rounds** | Use the jurisdiction’s detailed tabulation when a summary feed loses the distinction that matters. Maricopa identifies qualified versus disqualified marks. Maine publishes its round summary and cast-vote records. Alaska’s detailed report specifies the treatment of unresolved write-ins and is already the repo’s appropriate source. For a refreshed DC benchmark, consult DCBOE’s delegate results for the required round and write-in coverage. [Maricopa canvass][maricopa] · [Maine files][me-index] · [Alaska report][ak-rcv] · [DC official results][dc-results] |
| **Who was on the ballot** | Keep the October Clerk list as the national starting point. Resolve exceptions using the election office’s final ballot, qualified write-in list, and dated withdrawals or disqualifications. DC publishes ballot-order and write-in lists separately. This establishes exactly who belongs in `nominee_count`, even when a write-in later receives valid votes. [Clerk nominees][clerk26] · [DC official election documents][dc-index] |
| **Who was an incumbent** | Match each eligible nominee to a dated congressional membership roll. The Clerk’s alphabetical House list dated **November 2, 2026** is an exact-date cross-check for the annual roster. Preserve that PDF and its hash because the URL can change. Use oath and vacancy records for succession, and the election-eve Senate roll if a House nominee served there. For rebased 2024, retain the repo’s reconstructed **November 4, 2024** membership reference. [November 2 House roll][house-roll] · [Vacancies and oaths][vacancies] · [Repository membership method][roster-history] |
| **2024 historical totals, map and denominator** | Keep the Clerk’s 2024 House results and the FEC’s presidential workbook as the national reference checks on the MIT tables. Retain the Census district block files and the repo’s unrounded citizen-adult population for its defined shares. The repo’s No Vote residual depends on that population, so a state’s published ballot-turnout percentage answers a different question. [House returns][clerk24] · [FEC workbook][fec-xlsx] · [Census block files][census-map] · [2024 outcome definitions][outcomes24] |

**Independent incumbency check.** Matching the eligible 2026 nominees to the November 2 Clerk roll reproduced all **1,308 district-party flags**. In FL-20, for example, Debbie Wasserman Schultz correctly qualifies through her service in FL-25. The checked PDF’s SHA-256 is `7bd0cdceaf879020e738d7fe8d828e52a3c810606a5677abaab5bf24b4acb6a2`. [Election-eve membership roll][house-roll]

For any revised return, retain the raw line, source URL, count timestamp, publication status, round where applicable, and inclusion decision. This makes a later vote update distinguishable from a change in which marks qualify. District-level state comparisons here cover all **88 tabulated contests in California, Florida, and Massachusetts**, with targeted checks elsewhere. The nationwide 2026 checks covered roster membership, incumbency, source transcription, and arithmetic.

[commit]: https://github.com/robertocerinaprojects/polling-without-people/commit/7f8d796604b48c54cf5a2efb4e2c38913e7807a8
[roster-rule]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/01_frame/docs/08_house_slates.md#L7-L37
[clerk26]: https://clerk.house.gov/member_info/electionInfo/2026/120-nominations.pdf
[dc-ballot]: https://www.dcboe.org/getContentAsset/0918c479-a00c-4f4e-95d0-3b867ce33a21/5ebbd046-860b-4ee1-81c8-43d0e3bc446e/Federal.pdf?language=en
[dc-writeins]: https://www.dcboe.org/getContentAsset/baa7b20c-9cbd-45fe-9842-986da48d2123/5ebbd046-860b-4ee1-81c8-43d0e3bc446e/2026-General-Election-WRITE-IN-CANDIDATES-07222026.pdf?language=en
[corrections]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/01_frame/docs/08_house_slate_corrections.csv
[fingerprint]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/01_frame/scripts/08_prepare_house_slates.py#L262-L269
[predictors]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/03_mrp/scripts/01_prepare_house_inputs.R#L26-L38
[returns-rule]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/03_mrp/docs/01_prepare_house_inputs.md#L54-L69
[aggregation]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/03_mrp/scripts/01_prepare_house_inputs.R#L48-L73
[az-manual]: https://apps.azsos.gov/election/files/epm/2025/Election-Procedures-Manual-2025--FINAL-12-22-25.pdf#page=258
[maricopa]: https://elections.maricopa.gov/asset/jcr%3A228c42d5-7b4c-4e34-a9de-6384bcc80032/11-03-2026-0%20BOS%20CANVASS%20SUMMARY.pdf
[az3-state]: https://app.enhancedvoting.com/results/public/Arizona/elections/110326GeneralElection/ballot-items/248c0000-c0a3-7204-1287-08df11bc03cf
[az-rows]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/03_mrp/docs/01_house_2026_source_votes.csv#L49-L54
[snapshot]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/03_mrp/docs/01_prepare_house_inputs.md#L71-L104
[publisher]: https://www.callthemap.com/results/data
[manifest]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/03_mrp/docs/01_house_2026_source_votes.csv
[ma-all]: https://electionstats.state.ma.us/elections/search/year_from:2026/year_to:2026
[ma2]: https://electionstats.state.ma.us/elections/view/173571/
[fl-all]: https://floridaelectionwatch.gov/FederalOffices/USRepresentative
[fl5]: https://floridaelectionwatch.gov/ContestResultsByCounty/140050
[fl-time]: https://floridaelectionwatch.gov/Timeline/EN/
[me-release]: https://www3.maine.gov/sos/news/ranked-choice-voting-tabulation-results-announced-maine-congressional-district-2
[me-csv]: https://www1.maine.gov/sos/sites/maine.gov.sos/files/inline-files/Nov26%20CG2%20RCV%20Summary%20Report%2020261112_0.csv
[me-rounds]: https://fairvote.org/ranked-choice-voting-confirms-lepage-win-in-maine-2nd-district/
[dc-policy]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/03_mrp/docs/01_prepare_house_inputs.md#L89-L94
[dc-ddhq]: https://votes.decisiondeskhq.com/races/2026-11-03/district-of-columbia-us-house-at-large-general-election
[ca-media]: https://media.sos.ca.gov/
[clerk24]: https://clerk.house.gov/member_info/electionInfo/2024/statistics2024.pdf
[fec24]: https://www.fec.gov/resources/cms-content/documents/2024presgeresults.pdf
[checksums]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/docs/validation/e393b7f2-frame-rebuild/product_sha256.csv#L60-L62
[scenarios]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/01_frame/docs/09_model_house_votes.md#districts-on-the-2026-map
[final24]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/01_frame/data/output/09_house_final_shares_cd120.csv
[carl]: https://history.house.gov/People/Listing/C/CARL%2C-Jerry-L--%28C001054%29/
[al-example]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/get_us_2024_xframe_data.md#L52-L60
[la-row]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/01_frame/docs/08_house_slate_corrections.csv#L13
[la-fec]: https://www.fec.gov/resources/cms-content/documents/2024congressgecands.pdf#page=31
[la-guide]: https://lailluminator.com/voter-guide/2024-louisiana-voter-guide/
[state-offices]: https://www.fec.gov/introduction-campaign-finance/how-to-research-public-records/state-election-offices/
[fec-guidance]: https://www.fec.gov/introduction-campaign-finance/election-results-and-voting-information/
[clerk-index]: https://clerk.house.gov/Members/ViewElectionInformation
[fl-download]: https://floridaelectionwatch.gov/Downloads/
[me-index]: https://www1.maine.gov/sos/elections-voting/election-results-data
[ak-rcv]: https://www.elections.alaska.gov/enr/26GENR/results/RCV-USRep.pdf
[dc-results]: https://electionresults.dcboe.org/election_results/2026-General-Election
[dc-index]: https://www.dcboe.org/elections/2026-elections
[house-roll]: https://clerk.house.gov/committee_info/oal.pdf
[vacancies]: https://clerk.house.gov/Members/ViewVacancies
[roster-history]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/01_frame/docs/08_house_slates.md#which-years-lineup-enters-the-model
[fec-xlsx]: https://www.fec.gov/documents/5645/2024presgeresults.xlsx
[census-map]: https://www.census.gov/geographies/mapping-files/2027/dec/rdo/120-congressional-district-bef.html
[outcomes24]: https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/01_frame/docs/09_model_house_votes.md#outcome-and-predictors

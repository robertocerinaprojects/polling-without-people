# Which parties ran for the House?

For each election we count the distinct eligible named nominees for each district's regular November House election. A district with two Democrats in a top-two election offers a choice between candidates. A district with one Democrat running unopposed offers one named choice. We record that difference. The classification counts candidate names once even when the same name has more than one party line.

The 2024 counts describe contests on 119th Congress boundaries. The 2026 counts describe the actual November 3 contests on 120th Congress boundaries. Each list includes the 435 voting seats and the District of Columbia delegate. Special elections for the remainder of a prior Congress and the other territories are outside this frame. Both the candidate's qualification and the election cycle matter, even when the district label reads the same.

## Sources and review

The Office of the Clerk of the U.S. House of Representatives compiles an official list of nominees from state sources for each Congress. The editions used here were published October 18, 2024, and October 8, 2026. The Python script verifies the SHA-256 of each PDF, uses the House and DC delegate sections, and reads the district, candidate name and party. Each distinct nominee receives one major-party or Other designation. New York fusion nominees count once under their major party. Minnesota Democratic–Farmer–Labor and North Dakota Democratic–Nonpartisan League nominees count as Democrats. Other includes independents and minor parties. [2024 Clerk nominees](https://clerk.house.gov/member_info/electionInfo/2024/119-nominations.pdf) · [2026 Clerk nominees](https://clerk.house.gov/member_info/electionInfo/2026/120-nominations.pdf)

The October lists sometimes include candidates who withdrew or qualified only for write-in votes. During the source review we compared each voting district’s D, R and Other nominee counts with the regular-election listings from The Green Papers. We checked DC against its federal sample ballots. The review used candidate listings and excluded write-in-only and scattering entries. [2024 regular House contests](https://www.thegreenpapers.com/G24/House.phtml?v=a) · [2026 regular House contests](https://www.thegreenpapers.com/G26/House.phtml?v=a) · [2024 DC federal ballot](https://dcboe.org/getmedia/b9b39289-a2e4-4410-87d6-a0d5fb20ff58/General-24-Federal.pdf) · [2026 DC federal ballot](https://dcboe.org/getContentAsset/0918c479-a00c-4f4e-95d0-3b867ce33a21/5ebbd046-860b-4ee1-81c8-43d0e3bc446e/Federal.pdf?language=en)

The script reapplies the tracked corrections on every run. Each row gives the year, state, district, candidate, party label, action, reason and source. There are 16 changes for 2024 and one for 2026. For example, Florida's Michael Gist withdrew from FL-06 after the 2026 ballots were printed. The election office ruled votes for him ineligible, so his row appears in the candidate audit with `included=0`. The script then verifies a fingerprint of the sorted district keys and the three counts against the reviewed result for each year. [Reviewed corrections and their sources](08_house_slate_corrections.csv)

An eligible candidate can receive votes under multiple ballot labels. Each such nominee contributes one to the lineup. Step 07 separately includes valid write-ins when it counts votes, so a district can report Other votes even with `n_other=0`.

## Which year's lineup enters the model?

Step 09 fits observed 2024 returns using the 2024 roster. For redrawn districts it predicts on the 2026 geography using the 2026 roster. FL-20, for example, had one Democratic nominee and no tabulated election in 2024. Its redrawn 2026 seat had one Democrat, one Republican and one Other. OK-03 kept its footprint and had an unpolled 2024 contest with one Republican nominee. Step 09 uses that 2024 lineup to estimate its missing result. Districts with an identical footprint and observed 2024 counts carry those counts forward. [Step 09 projection rules](09_model_house_votes.md#districts-on-the-2026-map)

## District-level counts

| Eligible named party options | 2024 districts | 2026 districts |
|---|---:|---:|
| Democratic, Republican, Other | 127 | 171 |
| Democratic and Republican | 272 | 246 |
| Democratic and Other | 4 | 5 |
| Republican and Other | 4 | 0 |
| Democratic only | 13 | 13 |
| Republican only | 16 | 1 |
| Other only | 0 | 0 |
| **Total** | **436** | **436** |

In 2024, 22 seats had a single nominee (9 D and 13 R). Another seven had several nominees all from one major party (4 D and 3 R). In 2026, five seats had a single nominee (all D). Nine had several nominees all from one major party (8 D and 1 R). There were 1,069 qualifying nominees in 2024 and 1,161 in 2026. These totals include the uncontested seats whose 2024 House vote outcomes are unavailable for fitting.

## Running the script

From the repository root run `python3 01_frame/scripts/08_prepare_house_slates.py`. Python's standard library and the Poppler `pdftotext` executable suffice. The first run downloads `119-nominations.pdf` and `120-nominations.pdf` to `01_frame/data/input/`. Later runs verify and reuse those files. The state names and FIPS codes use the existing Census source manifest. [State identifiers](02_pl_2020_sources.csv)

The annual tables `01_frame/data/intermediate/08_house_slates_2024.csv` and `08_house_slates_2026.csv` have one row per district. Read `STATEFP` and `CDFP` as text to preserve leading zeros. State at-large seats use `00` and DC uses `98`. The counts `n_dem`, `n_rep` and `n_other` give eligible nominees in each group. The `slate` column records the groups present, in D/R/O order. For example, these two 2024 districts both had `slate=D`.

| District | n_dem | n_rep | n_other | unopposed | same_party_multiple |
|---|---:|---:|---:|---:|---:|
| CA-12 | 2 | 0 | 0 | 0 | 1 |
| FL-20 | 1 | 0 | 0 | 1 | 0 |

The candidate audit `01_frame/data/output/08_house_slate_nominees.csv` records one row per year, state, district and candidate name, including reviewed removals. It preserves the source party text, harmonized group, inclusion flag, decision and source URL. Step 09 reads the two annual district tables. Candidate names and the inclusion decisions are available here to trace a district count back to its sources.

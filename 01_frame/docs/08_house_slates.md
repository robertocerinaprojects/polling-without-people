# Which parties ran for the House?

For each election we count the distinct eligible named nominees for each district's regular November House election. A district with two Democrats in a top-two election offers a choice between candidates. A district with one Democrat running unopposed offers one named choice. We record that difference. The classification counts candidate names once even when the same name has more than one party line.

The 2024 counts describe contests on 119th Congress boundaries. The 2026 counts describe the actual November 3 contests on 120th Congress boundaries. Each list includes the 435 voting seats and the District of Columbia delegate. Special elections for the remainder of a prior Congress and the other territories are outside this frame. Both the candidate's qualification and the election cycle matter, even when the district label reads the same.

## Sources and review

The Office of the Clerk of the U.S. House of Representatives compiles an official list of nominees from state sources for each Congress. The editions used here were published October 18, 2024, and October 8, 2026. The Python script verifies the SHA-256 of each PDF, uses the House and DC delegate sections, and reads the district, candidate name and party. Each distinct nominee receives one major-party or Other designation. New York fusion nominees count once under their major party. Minnesota Democratic–Farmer–Labor and North Dakota Democratic–Nonpartisan League nominees count as Democrats. Other includes independents and minor parties. [2024 Clerk nominees](https://clerk.house.gov/member_info/electionInfo/2024/119-nominations.pdf) · [2026 Clerk nominees](https://clerk.house.gov/member_info/electionInfo/2026/120-nominations.pdf)

The October lists can include subsequently withdrawn nominees and qualified write-ins, or omit an amended nomination. We independently compared the three **counts** in every voting district to the regular-election candidate listings from The Green Papers, omitting entries marked write-in/scattering and excluding special elections. The comparison used candidate metadata only. The DC Board of Elections federal ballots provide the independent check for DC. The source-referenced corrections table records all differences affecting the counts. Its 2024 records cover Colorado write-ins, Iowa's final certification, a Louisiana withdrawal, amended or additional New York and North Carolina candidates, and a Virginia name absent from the final list. In 2026 one Florida candidate withdrew after ballots were printed. The election office announced votes cast for him would not count. [2024 regular House contests](https://www.thegreenpapers.com/G24/House.phtml?v=a) · [2026 regular House contests](https://www.thegreenpapers.com/G26/House.phtml?v=a) · [2024 DC federal ballot](https://dcboe.org/getmedia/b9b39289-a2e4-4410-87d6-a0d5fb20ff58/General-24-Federal.pdf) · [2026 DC federal ballot](https://dcboe.org/getContentAsset/0918c479-a00c-4f4e-95d0-3b867ce33a21/5ebbd046-860b-4ee1-81c8-43d0e3bc446e/Federal.pdf?language=en) · [Reviewed amendments](08_house_slate_corrections.csv)

Write-in-only candidates do not create a printed candidate option. Step 07 can still credit valid write-ins to a major candidate or to Other. Ballot configuration describes the choices presented to voters. It does not force an estimated vote share to zero. An uncontested nomination exists even if the jurisdiction did not conduct a poll for that office. A nomination alone supplies no count of ballots cast. Step 09 uses the 2026 lineup when it predicts a redrawn district such as FL-20. OK-03 keeps its footprint and had an unopposed Republican in 2024, so its prediction uses that original lineup. [Districts on the 2026 map](09_model_house_votes.md#districts-on-the-2026-map)

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

The script writes two tables under `01_frame/data/intermediate/` named `08_house_slates_2024.csv` and `08_house_slates_2026.csv`. Each has one row per district, with string identifiers `STATEFP` and `CDFP`, nominee counts `n_dem`, `n_rep`, `n_other`, the combination `slate` in D/R/O order, a single-nominee indicator `unopposed`, and a `same_party_multiple` indicator for multiple nominees all in one harmonized group. State at-large districts use `00`. DC uses `98`. Replacing either source or changing the correction table requires rechecking the district-level counts and their recorded fingerprint.

The candidate audit `01_frame/data/output/08_house_slate_nominees.csv` identifies the candidates, source party text, harmonized group, inclusion decision and source URL. Removed nominees remain visible with `included=0`. The script checks both sets of 436 keys and all reviewed D/R/O counts before replacing the outputs. The model consumes the counts. It never consumes 2026 candidate vote totals, vote shares, or election-winner labels.

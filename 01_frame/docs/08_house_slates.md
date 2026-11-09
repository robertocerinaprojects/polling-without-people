# Which parties ran for the House?

For each election we count the distinct eligible named nominees for each district's regular November House election. A district with two Democrats in a top-two election offers a choice between candidates. A district with one Democrat running unopposed offers one named choice. We record that difference. We also ask whether any nominee for each party was serving in Congress immediately before that election. A candidate can hold office while running in a different district. Each person counts once even when the same name appears on multiple ballot lines.

The 2024 counts describe contests on 119th Congress boundaries. The 2026 counts describe the actual November 3 contests on 120th Congress boundaries. Each list includes the 435 voting seats and the District of Columbia delegate. Special elections for the remainder of a prior Congress and the other territories are outside this frame. Both the candidate's qualification and the election cycle matter, even when the district label reads the same.

## Sources and review

The Office of the Clerk of the U.S. House of Representatives compiles an official list of nominees from state sources for each Congress. The editions used here were published October 18, 2024, and October 8, 2026. The Python script verifies the SHA-256 of each PDF, uses the House and DC delegate sections, and reads the district, candidate name, party and service mark. Each distinct nominee receives one major-party or Other designation. New York fusion nominees count once under their major party. Minnesota Democratic–Farmer–Labor and North Dakota Democratic–Nonpartisan League nominees count as Democrats. Other includes independents and minor parties. [2024 Clerk nominees](https://clerk.house.gov/member_info/electionInfo/2024/119-nominations.pdf) · [2026 Clerk nominees](https://clerk.house.gov/member_info/electionInfo/2026/120-nominations.pdf)

The October lists sometimes include candidates who withdrew or qualified only for write-in votes. During the source review we compared each voting district’s D, R and Other nominee counts with the regular-election listings from The Green Papers. We checked DC against its federal sample ballots. The review used candidate listings and excluded write-in-only and scattering entries. [2024 regular House contests](https://www.thegreenpapers.com/G24/House.phtml?v=a) · [2026 regular House contests](https://www.thegreenpapers.com/G26/House.phtml?v=a) · [2024 DC federal ballot](https://dcboe.org/getmedia/b9b39289-a2e4-4410-87d6-a0d5fb20ff58/General-24-Federal.pdf) · [2026 DC federal ballot](https://dcboe.org/getContentAsset/0918c479-a00c-4f4e-95d0-3b867ce33a21/5ebbd046-860b-4ee1-81c8-43d0e3bc446e/Federal.pdf?language=en)

The script reapplies the tracked corrections on every run. Each row gives the year, state, district, candidate, party label, action, reason and source. There are 16 changes for 2024 and one for 2026. For example, Florida's Michael Gist withdrew from FL-06 after the 2026 ballots were printed. The election office ruled votes for him ineligible, so his row appears in the candidate audit with `included=0`. The script then verifies a fingerprint of the sorted district keys and the three nominee counts and the three party incumbency flags against the reviewed result for each year. [Reviewed corrections and their sources](08_house_slate_corrections.csv)

An eligible candidate can receive votes under multiple ballot labels. Each such nominee contributes one to the lineup. Step 07 separately includes valid write-ins when it counts votes, so a district can report Other votes even with `n_other=0`.

## Which parties fielded a sitting member?

Each district row has three binary columns: `incumbent_dem`, `incumbent_rep` and `incumbent_other`. A party gets **1** if any eligible nominee in that district already sat in Congress on the eve of the general election. It gets **0** if it had no such nominee, including when it fielded nobody. Count DC’s delegate as a sitting member. Use the party on the ballot and the district the candidate is running in, even if the member previously represented a different district.

The Clerk marks an incumbent with an asterisk next to the candidate’s name. We read that mark from the House or DC delegate nominee row, before stripping punctuation from the name. A double dagger identifies someone who served in a previous Congress. Those nominees get 0. A single dagger records House service during the outgoing Congress; a status like that requires checking the service dates. None of the included House or DC delegate nominees in either edition carries a single dagger. Footnotes naming a retiring or defeated member do not enter the candidate table. [2024 Clerk list and legend](https://clerk.house.gov/member_info/electionInfo/2024/119-nominations.pdf) · [2026 Clerk list and legend](https://clerk.house.gov/member_info/electionInfo/2026/120-nominations.pdf)

The 2024 list describes the 118th Congress before November 5. The 2026 list describes the 119th Congress before November 3. The House vacancy and succession records show no change between either October list’s publication and its election eve. For the four 2024 nominees added from certified ballots, the corrections table records an explicit 0 and the membership source used to check it. Removed nominees remain traceable in the audit and contribute to neither the district counts nor its incumbency flags. [118th Congress membership and changes](https://clerk.house.gov/member_info/olm-118.pdf) · [118th Congress vacancies](https://history.house.gov/dropdowntemplate?htmlContentID=36507224029&id=36507224009) · [119th Congress vacancies](https://history.house.gov/Institution/Vacancies-Successors/Vacancies-Successors/) · [Reviewed ballot corrections](08_house_slate_corrections.csv)

Membership in either chamber qualifies. Neither election included a sitting U.S. senator among the eligible House nominees. The check used the Senate calendars for both election eves. [November 4, 2024 Senate roll](https://www.govinfo.gov/content/pkg/CCAL-118scal-2024-11-04/html/CCAL-118scal-2024-11-04-pt1.htm) · [November 2, 2026 Senate roll](https://www.govinfo.gov/content/pkg/CCAL-119scal-2026-11-02/html/CCAL-119scal-2026-11-02-pt1.htm)

| Election and district | Eligible nominees illustrating the rule | Dem | Rep | Other |
|---|---|---:|---:|---:|
| 2024 AL-01 | Sitting Republican Barry Moore moved from AL-02 to face Democrat Tom Holmes. | 0 | 1 | 0 |
| 2024 CA-34 | Democrats Jimmy Gomez and David Kim ran. Gomez was sitting. | 1 | 0 | 0 |
| 2024 CA-12 | Democrats Lateefah Simon and Jennifer Tran ran. Both were newcomers to Congress. | 0 | 0 | 0 |
| 2026 CA-40 | Republicans Ken Calvert and Young Kim were both sitting members. | 0 | 1 | 0 |
| 2026 CA-06 | Sitting member Kevin Kiley ran as an independent against Democrat Richard Pan. | 0 | 0 | 1 |

We cross-checked each party’s district flag against The Green Papers’ candidate and sitting-member listings. For NJ-10 in 2024, the House succession record confirms LaMonica McIver took office in September, before the regular election. For DC, the 2024 Clerk roster identifies Eleanor Holmes Norton as the incumbent delegate. Its 2026 edition records in a footnote that she did not run. The script checks the district flags alongside the candidate counts on every run. [2024 district listings](https://www.thegreenpapers.com/G24/House.phtml?v=a) · [2026 district listings](https://www.thegreenpapers.com/G26/House.phtml?v=a) · [McIver’s House service](https://history.house.gov/dropdowntemplate?htmlContentID=36507224029&id=36507224009) · [Norton’s House service](https://history.house.gov/People/Detail/19016)

In a same-party contest the two candidates’ votes already feed the same party’s House outcome. Incumbency is a separate question about the people on that ballot. In the reviewed rosters, 187 districts fielded a sitting Democrat, 196 a sitting Republican and zero a sitting Other in 2024. The corresponding 2026 district counts were 183, 176 and one. Step 09 uses a common incumbency coefficient so that a 2026 Other nominee can use evidence from sitting Democrats and Republicans in 2024. [Model and interpretation](09_model_house_votes.md#candidate-incumbency)

## Which year's lineup enters the model?

Step 09 fits the 434 tabulated 2024 contests with their 2024 rosters. On the 2026 map, it carries counts in 290 identical tabulated districts and uses the actual 2026 lineup in 144 redrawn districts.

Two 2024 seats had a declared winner and no tabulated general-election vote. Step 09 simulates a one-nominee contest on **both maps** with the winner’s 2024 party and service status. In FL-20, Sheila Cherfilus-McCormick was a sitting Democrat. In OK-03, Frank D. Lucas was a sitting Republican. Both winners therefore give their own party `incumbent=1` and the other parties `incumbent=0`. FL-20’s actual 2026 roster lists three party groups. Its simulated contest uses only the 2024 Democrat and the full population of the selected footprint. [Reviewed winners, official returns and service records](09_unpolled_house_winners_2024.csv) · [Step 09 projection rules](09_model_house_votes.md#districts-on-the-2026-map)

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

The candidate audit `01_frame/data/output/08_house_slate_nominees.csv` records one row per year, state, district and candidate name, including reviewed removals. It preserves the source party text, harmonized group, inclusion flag, decision and source URL. The fields `clerk_service_mark`, `incumbent` and `incumbent_source` explain how each nominee contributed to the party flag. A blank mark means the Clerk listed the candidate without a service symbol. The value `not_listed` identifies a ballot addition whose status was reviewed separately. Step 09 uses the annual district counts and checks this candidate audit against the two declared winners. Its final file has four rows per district. For example, both 2024 CA-34 Democratic nominees contribute to one Democratic row with `nominee_count=2` and `incumbent=1`. [District-by-party covariates](09_model_house_votes.md#reading-the-district-by-party-covariates)

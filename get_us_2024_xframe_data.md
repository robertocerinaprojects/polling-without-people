# Data handoff

Download the three published files below or find them in a clone under
`01_frame/data/output/10_handoff/`. You can use them without running the pipeline.

| Download | Contents |
| --- | --- |
| [district_election_inputs_cd120.csv](https://raw.githubusercontent.com/robertocerinaprojects/polling-without-people/main/01_frame/data/output/10_handoff/district_election_inputs_cd120.csv) | 1,744 rows, with four vote choices per 2026 congressional district, including DC. Each row carries the 2024 district House share and statewide presidential share for that choice, plus the House lineup, incumbency, and ballot presence. |
| [pums_cd_cells.rds](https://raw.githubusercontent.com/robertocerinaprojects/polling-without-people/main/01_frame/data/output/10_handoff/pums_cd_cells.rds) | 497,550 positive-population cells from the 2020–2024 ACS PUMS on the 2026 district map. `N` is the sum of allocated citizen-adult weights. |
| [ces_2024_harmonized.rds](https://raw.githubusercontent.com/robertocerinaprojects/polling-without-people/main/01_frame/data/output/10_handoff/ces_2024_harmonized.rds) | 58,627 eligible 2024 CES respondents with the seven mother-frame cell keys and the outcomes `vote_house_2024` and `vote_pres_2024`. Refusals and uncertain vote answers are missing. For respondents who selected Hispanic as their primary race, usable follow-up race selections take precedence over imputation. |

Keep the filenames when copying the files to the receiving repository’s data
import location. Use `data/input/` if it has none.

To rebuild the files from the saved outputs of Steps 05–07 and 09, run this
command from the repository root.

```sh
Rscript 01_frame/scripts/10_prepare_handoff.R
```

The harmonized survey file is derived from Schaffner, Shih, Ansolabehere, and
Pope (2025), *Cooperative Election Study Common Content, 2024*, Harvard Dataverse,
V9, released under CC0 1.0. [Source dataset](https://doi.org/10.7910/DVN/X11EP6)

## Election results

`vote_choice` contains Democratic, Republican, Other, or No Vote, matching the response labels in the CES. Both result columns are fractions from 0 to 1 of estimated citizen adults.

- `vote_house_2024` is the final district share from `09_house_final_shares_cd120.csv`. `lineup` records the party groups on the House ballot. For example, `DR` means Democratic and Republican nominees. The lineup repeats across the four choices.
- `vote_pres_2024` is the statewide share for the same choice, repeated across districts in the state. [Step 07 returns](01_frame/docs/07_prepare_area_returns.md)

### House lineups and incumbency

| `prediction_source` | Districts | `lineup_year` | Lineup used |
| --- | ---: | ---: | --- |
| `observed_same_footprint` | 290 | 2024 | Actual 2024 nominees in unchanged districts with tabulated returns. |
| `model_redrawn` | 144 | 2026 | The nominees on the 2026 ballot are used for the hypothetical 2024 contest on the 2026 map. |
| `model_unopposed_2024` | 2 | 2024 | The sole declared 2024 winner is used in each hypothetical contest. Redrawn FL-20 uses Democrat Sheila Cherfilus-McCormick and OK-03 uses Republican Frank D. Lucas. Both were incumbents. |

| Field | Meaning on a district and choice row |
| --- | --- |
| `on_ballot` | `1` if the scenario lineup includes at least one eligible nominee in that party group, otherwise `0`. |
| `incumbent` | `1` if at least one eligible nominee in that group was serving in Congress on November 4, 2024, including members who served in a different district. Otherwise `0`. The same 2024 date applies to every lineup. |

These two fields are blank for No Vote. [Lineup and incumbency rules](01_frame/docs/08_house_slates.md#which-years-lineup-enters-the-model) · [Step 09 scenarios](01_frame/docs/09_model_house_votes.md#districts-on-the-2026-map)

Read `state_fips` and `district_fips` as text to preserve leading zeros. Use both FIPS keys and `vote_choice` to identify a result row.

## Population and survey data

The seven shared cell keys are `state_fips`, `district_fips`, `age_cat`, `gender_cat`, `race_cat`, `hispanic_cat`, and `educ_cat`. Step 10 renames `STATEFP` and `CDFP120` in both exports to match the CSV. The mother frame also carries `state_name`, a display label determined by `state_fips`. The two FIPS keys identify the district. The CES outcomes refer to respondents’ original 2024 ballots, and their district keys use the 2026 map. Use both FIPS keys to link a district’s result rows to its population cells or respondents. The CES outcome columns store choice labels, and the CSV outcome columns store shares indexed by `vote_choice`. [Mother-frame construction](01_frame/docs/06_build_pums_cells.md) · [CES vote definitions](01_frame/docs/05_vote_rules.md)

## Sample rows

### District election inputs

All nine columns from the handoff CSV, in file order. Shares are rounded for display.

| State FIPS | District FIPS | State | Choice | `vote_house_2024` | `vote_pres_2024` | Lineup | Incumbent | On ballot |
| --- | --- | --- | --- | ---: | ---: | --- | ---: | ---: |
| `01` | `01` | Alabama | Democratic | 0.185604 | 0.200644 | DR | 0 | 1 |
| `01` | `01` | Alabama | Republican | 0.367481 | 0.379933 | DR | 1 | 1 |
| `01` | `01` | Alabama | Other | 0.000000 | 0.007809 | DR | 0 | 0 |
| `01` | `01` | Alabama | No Vote | 0.446915 | 0.411614 | DR | | |
| ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ |

### Mother frame

| State FIPS | District FIPS | State | Age | Gender | Race | Hispanic ethnicity | Education | `N` |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| `01` | `01` | Alabama | 18-22 | Male | White | Hispanic | No HS | 59.17 |
| `01` | `01` | Alabama | 18-22 | Male | White | Hispanic | HS grad | 141.26 |
| `01` | `01` | Alabama | 18-22 | Male | White | Hispanic | Some college | 22.27 |
| ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ |

### Harmonized CES

| State FIPS | District FIPS | Age | Gender | Race | Hispanic ethnicity | Education | `vote_house_2024` | `vote_pres_2024` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `42` | `02` | 43-47 | Female | Black | Not Hispanic | HS grad | Democratic | Democratic |
| `36` | `08` | 53-57 | Male | Other/Multi | Hispanic | 4-year | Democratic | Democratic |
| `06` | `30` | 23-27 | Female | White | Hispanic | HS grad | No Vote | No Vote |
| ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ | ⋮ |

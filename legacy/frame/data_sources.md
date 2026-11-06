# Raw data files

This document catalogs all raw data files needed to run the Stratification Frame pipeline. Files are grouped by source. Some are used directly by pipeline scripts; others are supplementary reference materials (codebooks, questionnaires) useful for interpreting the data.

## Census Bureau / IPUMS

| Filename | Content | Source | Source URL | Attribution | Used by |
|---|---|---|---|---|---|
| usa_00003.csv.gz | American Community Survey Public Use Microdata Sample (ACS PUMS) — individual-level demographic records for the 2020-2024 pooled sample | IPUMS USA (custom extract of US Census Bureau's ACS 2024 5-year) | https://usa.ipums.org/usa/ | Steven Ruggles, Sarah Flood, Matthew Sobek, Daniel Backman, Grace Cooper, Julia A. Rivera Drew, Stephanie Richards, Renae Rodgers, Jonathan Schroeder, and Kari C.W. Williams. IPUMS USA: Version 16.0 [2024 ACS PUMS Microdata 5-year]. Minneapolis, MN: IPUMS, 2025. https://doi.org/10.18128/D010.V16.0 | Script 01 (load), Script 02 (filter), Script 03 (recode) |
| tab20_zcta520_tabblock20_natl.txt | 2020 ZCTA-to-block relationship file: maps every 2020 Census block to its containing ZCTA | U.S. Census Bureau 2020 Relationship Files | https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/ | US Census Bureau | Script 08 |
| 2020_Census_Tract_to_2020_PUMA.txt | 2020 tract-to-PUMA relationship file: maps every 2020 Census tract to its containing PUMA | U.S. Census Bureau 2020 Relationship Files | https://www.census.gov/programs-surveys/geography/guidance/geo-areas/pumas.html | US Census Bureau | Script 04 |
| NationalCD119.txt | 119th Congress (2024) Block Assignment File — block → 2024 CD mapping for all states | U.S. Census Bureau 119th Congressional District Block Equivalency Files | https://www.census.gov/geographies/mapping-files/2025/dec/rdo/119-congressional-district-bef.html | US Census Bureau | Script 12 |

## Geocorr

| Filename | Content | Source | Source URL | Attribution | Used by |
|---|---|---|---|---|---|
| geocorr2022_2610104623.csv | PUMA-to-CD crosswalk from Geocorr with 119th Congress (2024) CD boundaries and 2022 PUMAs | Missouri Census Data Center (Geocorr 2022) | https://mcdc.missouri.edu/applications/geocorr2022.html | Missouri Census Data Center | Script 04 |

Note: the filename contains the Geocorr session ID (2610104623). Retained as generated to preserve the query record.

## State Block Assignment Files (7 redistricted states)

| Filename | Content | Source | Source URL | Attribution | Used by | State |
|---|---|---|---|---|---|---|
| PLANC2333.csv | Texas 2026 BAF (block → 2026 CD) | Redistricting Data Hub | https://redistrictingdatahub.org/data/download-data/ | Redistricting Data Hub | Scripts 04, 08 | Texas |
| ab604.csv | California 2026 BAF | Redistricting Data Hub | https://redistrictingdatahub.org/data/download-data/ | Redistricting data hub | Scripts 04, 08 | California |
| HB1_Missouri_Congressional_Districts_2025_BEF.xlsx | Missouri 2025 BEF | MSDIS (Missouri Spatial Data Information Service) | https://data-msdis.opendata.arcgis.com/search?tags=hb1 | Missouri Spatial Data Information Service  | Scripts 04, 08 | Missouri |
| NCGA_CCM-2.csv | North Carolina 2026 BAF (CCM-2 plan) | Redistricting Data Hub | https://redistrictingdatahub.org/data/download-data/ | Redistricting data hub | Scripts 04, 08 | North Carolina |
| October 31 2025 CD BAF.xlsx | Ohio 2025 (Oct 31) BAF | Redistricting Data Hub | https://redistrictingdatahub.org/data/download-data/ | Redistricting data hub | Scripts 04, 08 | Ohio |
| ut_cong_adopted_2025_baf.csv | Utah 2025 adopted BAF | Redistricting Data Hub | https://redistrictingdatahub.org/data/download-data/ | Redistricting data hub | Scripts 04, 08 | Utah |
| EOGPCRP2026.csv | Florida 2026 BAF (EOGPCRP plan) | Redistricting Data Hub | https://redistrictingdatahub.org/data/download-data/ | Redistricting data hub | Scripts 04, 08 | Florida |

## MIT Election Lab

| Filename | Content | Source | Source URL | Attribution | Used by |
|---|---|---|---|---|---|
| 1976-2024-house.tab | 1976-2024 U.S. House election results by state × CD × candidate | MIT Election Data and Science Lab (Harvard Dataverse) | https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/IG0UN2 | MIT Election Data and Science Lab. 2017. “U.S. House 1976&ndash;2024.” Harvard Dataverse. https://doi.org/10.7910/DVN/IG0UN2. | Script 16 |
| 1976-2024-president.csv | 1976-2024 U.S. presidential election results by state | MIT Election Data and Science Lab (Harvard Dataverse) | https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/42MVDX | MIT Election Data and Science Lab. 2017. “U.S. President 1976&ndash;2024.” Harvard Dataverse. https://doi.org/10.7910/DVN/42MVDX. | Script 17 |
| codebook-us-house-1976-2024.md | Codebook for the 1976-2024 House data | MIT Election Data and Science Lab (Harvard Dataverse) | https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/IG0UN2 | MIT Election Data and Science Lab. 2017. “U.S. House 1976&ndash;2024.” Harvard Dataverse. https://doi.org/10.7910/DVN/IG0UN2. | Script 16 (reference) |
| codebook-us-president-1976-2020.md | Codebook for the 1976-2020 presidential data (schema unchanged through 2024, applicable to 1976-2024-president.csv) | MIT Election Data and Science Lab (Harvard Dataverse) | https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/42MVDX | MIT Election Data and Science Lab. 2017. “U.S. President 1976&ndash;2024.” Harvard Dataverse. https://doi.org/10.7910/DVN/42MVDX. | Script 17 (reference) |

## CES

| Filename | Content | Source | Source URL | Attribution | Used by |
|---|---|---|---|---|---|
| CCES24_Common_OUTPUT_vv_topost_final.csv | Cooperative Election Study Common Content 2024 in CSV format — respondent-level survey data with demographics, geography, vote choice, and weights | Cooperative Election Study 2024 (Harvard Dataverse) | https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/X11EP6 | Schaffner, Brian, Marissa Shih, Stephen Ansolabehere, and Jeremy Pope. 2025. “Cooperative Election Study Common Content, 2024.” Harvard Dataverse. https://doi.org/10.7910/DVN/X11EP6. | Script 06 (load), Script 07 (harmonize), Script 08 (geographic audit), Scripts 12+, 13 |
| CCES24_Common_OUTPUT_vv_topost_final.dta | Cooperative Election Study Common Content 2024 Content in Stata format (same data as CSV; provided for users who prefer Stata) | Cooperative Election Study 2024 (Harvard Dataverse) | https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/X11EP6 | Schaffner, Brian, Marissa Shih, Stephen Ansolabehere, and Jeremy Pope. 2025. “Cooperative Election Study Common Content, 2024.” Harvard Dataverse. https://doi.org/10.7910/DVN/X11EP6. | Reference (same data as CSV) |
| CES_2024_GUIDE_vv.pdf | CES 2024 user guide / codebook — methodology, variable descriptions, weighting details | Cooperative Election Study 2024 (Harvard Dataverse) | https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/X11EP6 | Schaffner, Brian, Marissa Shih, Stephen Ansolabehere, and Jeremy Pope. 2025. “Cooperative Election Study Common Content, 2024.” Harvard Dataverse. https://doi.org/10.7910/DVN/X11EP6. | Reference for Scripts 06, 07, 13 |
| CCES24_Common_pre.docx | CES 2024 pre-wave questionnaire (exact question wording for pre-election wave variables) | Cooperative Election Study 2024 (Harvard Dataverse) | https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/X11EP6 | Schaffner, Brian, Marissa Shih, Stephen Ansolabehere, and Jeremy Pope. 2025. “Cooperative Election Study Common Content, 2024.” Harvard Dataverse. https://doi.org/10.7910/DVN/X11EP6. | Reference for Scripts 06, 13 |
| CCES24_Common_post.docx | CES 2024 post-wave questionnaire (exact question wording for post-election wave variables) | Cooperative Election Study 2024 (Harvard Dataverse) | https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/X11EP6 | Schaffner, Brian, Marissa Shih, Stephen Ansolabehere, and Jeremy Pope. 2025. “Cooperative Election Study Common Content, 2024.” Harvard Dataverse. https://doi.org/10.7910/DVN/X11EP6. | Reference for Scripts 06, 13 |
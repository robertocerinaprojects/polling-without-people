# Build a PUMA-to-congressional-district crosswalk for the 2026 election.
# Run from the repository root: Rscript 01_frame/scripts/02_build_puma_cd_crosswalk.R
# Method and worked examples: 01_frame/docs/02_build_puma_cd_crosswalk.md

# Each output row gives the probability of assigning a citizen adult in a
# Public Use Microdata Area (PUMA) to one 120th Congress district. STATEFP
# and PUMA5CE identify the PUMA. CVAP means citizen voting-age population.
# Sections 1–9 assemble the inputs and review geographic exceptions. Section 10
# splits citizen-adult estimates within block groups. Section 11 turns those
# contributions into probabilities that sum to one within each PUMA.

library(dplyr)

check <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

helpers_dir <- here::here("01_frame", "scripts", "helpers")
source(file.path(helpers_dir, "02_census_inputs.R"), local = TRUE)
source(file.path(helpers_dir, "02_block_geography.R"), local = TRUE)
source(file.path(helpers_dir, "02_cvap_audit_notes.R"), local = TRUE)
source(file.path(helpers_dir, "02_cvap_geography.R"), local = TRUE)
source(file.path(helpers_dir, "02_allocation_inputs.R"), local = TRUE)
source(file.path(helpers_dir, "02_crosswalk_audits.R"), local = TRUE)

# The 50 states and DC share these identifiers in PUMS and Census files.
# Listed FIPS codes: https://www2.census.gov/geo/docs/reference/state.txt
target_states <- sprintf(
  "%02d", c(1, 2, 4, 5, 6, 8:13, 15:42, 44:51, 53:56)
)
allowed_states <- c(target_states, "60", "66", "69", "72", "78")
output_dir <- here::here("01_frame", "data", "output")

# Sections 1–2: Read the district assigned to every 2020 block ----
# Keep the 50 states and DC. Census uses ZZ for blocks outside a defined
# district. These blocks stay in the table so we can audit their population.
block_cd <- read_block_districts(target_states, allowed_states, output_dir)

# Section 3: Identify the PUMA containing each block's 2020 tract ----
block_cd <- attach_block_pumas(block_cd, target_states, allowed_states, output_dir)

# Sections 4–5: Match 2020 Census population counts by block GEOID ----
# All-age counts check the match against state totals. The 18+ counts get
# the same check and later help split the block-group citizen-adult estimates.
block_cd <- attach_block_population(block_cd, target_states, output_dir)

# Section 6: Match missing New York estimates to Census Errata 148 ----
# Only these block groups have a documented reason for a missing estimate.
cvap_sources <- read_cvap_and_ny_errata()
national_cvap_source <- cvap_sources$national_cvap
ny_suppression <- audit_ny_suppression(block_cd, cvap_sources)
ny_missing <- ny_suppression$missing

# Section 7: Locate the affected New York PUMAs and districts ----
# If every block of an affected PUMA is in one district, its allocation is known.
audit_ny_puma_extent(block_cd, ny_suppression)

# Section 8: Match Connecticut block groups across county definitions ----
# The CVAP block groups use planning regions where the 2020 block map uses old counties.
ct_candidate_audit <- audit_ct_block_group_ids(block_cd, national_cvap_source)

# Section 9: Match block groups and choose an allocation method ----
allocation_inputs <- prepare_allocation_inputs(
  block_cd, national_cvap_source, ct_candidate_audit, ny_missing,
  target_states, output_dir
)
bg_2020_cells <- allocation_inputs$bg_2020_cells
bg_target_cells <- allocation_inputs$bg_target_cells
allocation_readiness <- allocation_inputs$allocation_readiness
rm(allocation_inputs)

# Section 10: How much of a block group's CVAP belongs to each district? ----
# A part is the intersection of a block group, a PUMA and a district.
# The ACS gives one citizen-adult estimate per block group. For a split group
# we estimate each part's share using its 2020 Census count of all adults.
parts <- bg_target_cells |>
  left_join(
    allocation_readiness |>
      select(
        STATEFP, bg_cvap, allocation_case,
        block_group_cvap = cvap_for_allocation, block_group_adults = vap20
      ),
    by = c("STATEFP", "bg_cvap"),
    relationship = "many-to-one"
  )
check_contribution_inputs(parts, expected_rows = nrow(bg_target_cells))

allocate_block_group_cvap <- function(method, block_group_cvap, part_adults,
                                      block_group_adults) {
  zero <- method %in% c("zero_cvap", "structural_zero_reviewed", "exclude_unassigned")
  contained <- method == "direct_containment"
  split <- method == "adult_proportions"

  # Suppressed ACS estimates stay missing. A contained group goes wholly to
  # its one assigned district, even if its 2020 adult count was zero.
  contribution <- rep(NA_real_, length(method))
  contribution[zero] <- 0
  contribution[contained] <- block_group_cvap[contained]
  contribution[split] <- block_group_cvap[split] * part_adults[split] /
    block_group_adults[split]
  contribution
}

bg_cvap_contributions <- parts |>
  mutate(
    cvap_contribution = allocate_block_group_cvap(
      allocation_case, block_group_cvap, part_adults = vap20,
      block_group_adults = block_group_adults
    )
  ) |>
  select(
    STATEFP, bg_cvap, PUMA5CE, CDFP, source_block_links, pop20, vap20,
    coverage_only, allocation_case, cvap_contribution
  )

# Make sure the pieces add back to each block group's allocatable estimate.
contributed_observed_cvap <- audit_block_group_contributions(
  bg_cvap_contributions, allocation_readiness, ny_missing, output_dir
)

# Section 11: What fraction of a PUMA's citizen adults live in each district? ----
# Determine containment from all original blocks, including empty blocks and
# blocks coded ZZ. A PUMA qualifies only if every block has the same district.
puma_geography <- bg_2020_cells |>
  group_by(STATEFP, PUMA5CE) |>
  summarise(
    source_blocks = sum(blocks),
    unassigned_blocks = sum(blocks[CDFP == "ZZ"]),
    assigned_districts = n_distinct(CDFP[CDFP != "ZZ"]),
    .groups = "drop"
  ) |>
  mutate(
    structural_containment =
      assigned_districts == 1L & unassigned_blocks == 0L
  )

# Preserve every original assigned PUMA-district intersection.
assigned_intersections <- bg_2020_cells |>
  filter(CDFP != "ZZ") |>
  distinct(STATEFP, PUMA5CE, CDFP) |>
  arrange(STATEFP, PUMA5CE, CDFP)

puma_cd_cvap <- bg_cvap_contributions |>
  filter(CDFP != "ZZ") |>
  group_by(STATEFP, PUMA5CE, CDFP) |>
  summarise(
    known_cvap_subtotal = sum(cvap_contribution, na.rm = TRUE),
    district_cvap = sum_cvap_or_na(cvap_contribution),
    .groups = "drop"
  )

check_district_aggregation(
  assigned_intersections, puma_cd_cvap, contributed_observed_cvap
)

# Sum across the assigned districts to get each PUMA denominator. The known
# subtotal is available for audits even when the full CVAP is unknown.
puma_cvap_totals <- puma_cd_cvap |>
  group_by(STATEFP, PUMA5CE) |>
  summarise(
    known_puma_cvap_subtotal = sum(known_cvap_subtotal),
    puma_cvap = sum_cvap_or_na(district_cvap),
    .groups = "drop"
  )

puma_missing_counts <- bg_cvap_contributions |>
  filter(CDFP != "ZZ") |>
  group_by(STATEFP, PUMA5CE) |>
  summarise(
    missing_block_groups = n_distinct(
      bg_cvap[is.na(cvap_contribution)]
    ),
    .groups = "drop"
  )

puma_allocation_audit <- puma_geography |>
  left_join(
    puma_cvap_totals,
    by = c("STATEFP", "PUMA5CE"),
    relationship = "one-to-one"
  ) |>
  left_join(
    puma_missing_counts,
    by = c("STATEFP", "PUMA5CE"),
    relationship = "one-to-one"
  ) |>
  mutate(
    weight_method = case_when(
      structural_containment ~ "structural_single_district",
      missing_block_groups == 0L &
        is.finite(puma_cvap) & puma_cvap > 0 ~ "cvap_share",
      TRUE ~ "review_required"
    )
  )

blocked_pumas <- puma_allocation_audit |>
  filter(weight_method == "review_required" | is.na(missing_block_groups))
blocked_path <- file.path(output_dir, "02_puma_allocation_blocked.csv")

if (nrow(blocked_pumas) > 0L) {
  readr::write_csv(blocked_pumas, blocked_path)
  print(blocked_pumas, n = Inf, width = Inf)
  stop("Some PUMAs lack usable allocation inputs. See ", blocked_path, call. = FALSE)
}

weight_inputs <- assigned_intersections |>
  left_join(
    puma_cd_cvap,
    by = c("STATEFP", "PUMA5CE", "CDFP"),
    relationship = "one-to-one"
  ) |>
  left_join(
    puma_allocation_audit |>
      select(STATEFP, PUMA5CE, puma_cvap, weight_method),
    by = c("STATEFP", "PUMA5CE"),
    relationship = "many-to-one"
  )

# Every block in one assigned district gives probability 1 (including the
# two NY PUMAs with suppressed CVAP). Otherwise use the share of assigned
# PUMA CVAP in this district. Retain districts whose share is zero.
district_probability <- function(method, district_cvap, puma_cvap) {
  contained <- method == "structural_single_district"
  split <- method == "cvap_share"
  probability <- rep(NA_real_, length(method))
  probability[contained] <- 1
  probability[split] <- district_cvap[split] / puma_cvap[split]
  probability
}

puma_cd_crosswalk <- weight_inputs |>
  transmute(
    STATEFP, PUMA5CE, CDFP,
    allocation_weight = district_probability(
      weight_method, district_cvap, puma_cvap
    ),
    weight_method
  ) |>
  arrange(STATEFP, PUMA5CE, CDFP)

# Each PUMA's probabilities must sum to one. Publish the checked RDS and
# completed audit only after the weight checks pass.
puma_allocation_audit <- audit_district_weights(
  puma_cd_crosswalk, puma_allocation_audit, assigned_intersections, target_states
)
publish_crosswalk(puma_cd_crosswalk, puma_cd_cvap, puma_allocation_audit,
                  output_dir, blocked_path)

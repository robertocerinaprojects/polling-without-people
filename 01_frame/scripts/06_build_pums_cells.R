# Build citizen-adult population cells and compare the CES matching keys.
# Run from repository root: Rscript 01_frame/scripts/06_build_pums_cells.R
# Method and output fields: 01_frame/docs/06_build_pums_cells.md
library(dplyr)

build_pums_cells <- function(data_dir = file.path("01_frame", "data")) {
  intermediate <- file.path(data_dir, "intermediate")
  output <- file.path(data_dir, "output")
  person_key <- c("SAMPLE", "SERIAL", "PERNUM")
  demographic <- c("age_cat", "gender_cat", "race_cat", "hispanic_cat", "educ_cat")
  area_key <- c("STATEFP", "CDFP120")
  cell_key <- c(area_key, demographic)
  close_weight <- function(x, reference) {
    all(is.finite(x) & is.finite(reference) &
        abs(x - reference) <= 1e-12 * pmax(1, abs(reference)))
  }

  allocation <- readRDS(file.path(intermediate, "pums_cd_allocation.rds"))
  people <- readRDS(file.path(intermediate, "pums_demographics.rds"))
  ces <- readRDS(file.path(intermediate, "ces_demographics_harmonized.rds"))
  reference <- read.csv(file.path(output, "03_pums_allocation_by_state.csv"),
                        colClasses = c(STATEFP = "character"))
  stopifnot(all(c(person_key, "STATEFIP", "CDFP", "allocated_person_weight") %in%
                  names(allocation)), all(c(person_key, demographic) %in% names(people)),
            all(c("caseid", cell_key) %in% names(ces)),
            all(c("STATEFP", "person_records", "allocated_rows", "input_weight",
                  "allocated_weight") %in% names(reference)))

  # A missing PUMS demographic would require an explicit frame category.
  stopifnot(nrow(people) > 0L, !anyNA(people[c(person_key, demographic)]),
            !vctrs::vec_duplicate_any(people[person_key]),
            !anyNA(ces$caseid), !anyDuplicated(ces$caseid), !anyNA(ces[area_key]))
  for (field in demographic) {
    labels <- levels(ces[[field]])
    source <- people[[field]]
    source_labels <- if (is.factor(source)) levels(source) else unique(as.character(source))
    if (!length(labels) || !setequal(source_labels, labels)) {
      stop("Different CES/PUMS category labels in ", field, call. = FALSE)
    }
    # Standardize factor order as well as labels for subsequent joins.
    people[[field]] <- factor(source, levels = labels)
  }

  # Match columns as a tuple. Each allocation row maps to exactly one person;
  # the same person can supply a fraction of their weight to several districts.
  person <- vctrs::vec_match(allocation[person_key], people[person_key])
  stopifnot(!anyNA(person), all(tabulate(person, nbins = nrow(people)) > 0L))
  n_people <- nrow(people)
  people <- people[demographic]
  allocation <- allocation[c("STATEFIP", "CDFP", "allocated_person_weight")]
  stopifnot(is.numeric(allocation$STATEFIP),
            all(is.finite(allocation$STATEFIP) &
                allocation$STATEFIP == trunc(allocation$STATEFIP)),
            is.character(allocation$CDFP), !anyNA(allocation$CDFP),
            all(grepl("^[0-9]{2}$", allocation$CDFP)),
            all(is.finite(allocation$allocated_person_weight) &
                allocation$allocated_person_weight > 0))
  # Step 02's verified plan covers 50 states plus DC (435 seats plus DC 11/98).
  reference <- reference[order(reference$STATEFP), ]
  stopifnot(!anyDuplicated(reference$STATEFP), nrow(reference) == 51L,
            setequal(sprintf("%02d", sort(unique(allocation$STATEFIP))), reference$STATEFP))
  rows_by_state <- split(seq_len(nrow(allocation)), factor(allocation$STATEFIP,
                         levels = as.integer(reference$STATEFP)))

  # Expand demographics for just one state at a time to limit peak memory.
  state_cells <- vector("list", nrow(reference))
  for (i in seq_len(nrow(reference))) {
    rows <- rows_by_state[[i]]
    ids <- person[rows]
    district <- allocation$CDFP[rows]
    w <- allocation$allocated_person_weight[rows]
    stopifnot(length(rows) == reference$allocated_rows[i],
              n_distinct(ids) == reference$person_records[i],
              !vctrs::vec_duplicate_any(data.frame(person = ids, district = district)))
    chunk <- bind_cols(tibble(CDFP120 = district), people[ids, , drop = FALSE])
    chunk$allocated_person_weight <- w
    cells <- chunk |>
      group_by(across(all_of(c("CDFP120", demographic)))) |>
      summarise(N = sum(allocated_person_weight), .groups = "drop") |>
      mutate(STATEFP = reference$STATEFP[i], .before = 1)
    stopifnot(close_weight(sum(cells$N), reference$input_weight[i]),
              close_weight(sum(cells$N), reference$allocated_weight[i]))
    state_cells[[i]] <- cells
  }
  frame <- bind_rows(state_cells)
  districts <- distinct(frame, STATEFP, CDFP120)
  dc <- districts$CDFP120[districts$STATEFP == "11"]
  stopifnot(sum(reference$person_records) == n_people, nrow(districts) == 436L,
            identical(dc, "98"), identical(names(frame), c(cell_key, "N")),
            !vctrs::vec_duplicate_any(frame[cell_key]), all(frame$N > 0),
            close_weight(sum(frame$N), sum(reference$input_weight)))

  # Every survey case contributes once to a group. An unknown ethnicity
  # remains missing; the CVAP for that person's exact profile is unknown.
  stopifnot(all(vapply(ces[area_key], is.character, logical(1))),
            all(grepl("^[0-9]{2}$", ces$STATEFP)),
            all(grepl("^[0-9]{2}$", ces$CDFP120)),
            any(ces$STATEFP == "11" & ces$CDFP120 == "98"),
            !anyNA(vctrs::vec_match(ces[area_key], districts)))
  coverage <- ces |>
    group_by(across(all_of(cell_key))) |>
    summarise(ces_respondents = n(), .groups = "drop") |>
    left_join(frame, by = cell_key, na_matches = "never") |>
    mutate(
      coverage_status = case_when(
        if_any(all_of(cell_key), is.na) ~ "missing_ces_key",
        is.na(N) ~ "no_positive_pums_cell",
        TRUE ~ "matched_positive_N"
      ),
      N = if_else(coverage_status == "no_positive_pums_cell", 0, N)
    )
  stopifnot(!vctrs::vec_duplicate_any(coverage[cell_key]),
            sum(coverage$ces_respondents) == nrow(ces),
            all(is.na(coverage$N) == (coverage$coverage_status == "missing_ces_key")))

  frame_path <- file.path(intermediate, "pums_cd_cells.rds")
  audit_path <- file.path(output, "06_ces_pums_cell_coverage.csv")
  temporary_frame <- tempfile(".06-cells-", tmpdir = intermediate)
  temporary_audit <- tempfile(".06-coverage-", tmpdir = output)
  on.exit(unlink(c(temporary_frame, temporary_audit)), add = TRUE)
  saveRDS(frame, temporary_frame)
  readr::write_csv(coverage, temporary_audit)
  if (!file.rename(temporary_audit, audit_path)) stop("Could not save ", audit_path)
  if (!file.rename(temporary_frame, frame_path)) stop("Could not save ", frame_path)
  cat("PUMS people:", n_people, "\nPositive population cells:", nrow(frame),
      "\nState/district pairs including DC:", nrow(districts),
      "\nAllocated CVAP:", format(sum(frame$N), scientific = FALSE), "\n")
  print(coverage |> group_by(coverage_status) |>
          summarise(ces_respondents = sum(ces_respondents), cells = n(), .groups = "drop"))
  cat("Population cells:", frame_path, "\nCES coverage audit:", audit_path, "\n")
  invisible(frame_path)
}

if (sys.nframe() == 0L) build_pums_cells()

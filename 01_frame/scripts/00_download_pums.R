# Download the full IPUMS 2020-2024 ACS five-year person extract.
# Run from the repository root: Rscript 01_frame/scripts/00_download_pums.R [--refresh]
# main() follows the download from request to receipt. The checks it calls are below it.
# A normal run verifies and reuses a saved extract. --refresh requests a new one.
# Snapshots live in 01_frame/data/input/ipums_pums/. Script 01 checks the selected
# snapshot against 01_frame/docs/00_pums_source.json before using it for analysis.
# For recovery instructions, see 01_frame/docs/00_download_pums.md.

check <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

main <- function() {
  # Define the extract ----
  args <- commandArgs(trailingOnly = TRUE)
  refresh <- identical(args, "--refresh")
  check(length(args) == 0L || refresh,
        "Usage: Rscript 01_frame/scripts/00_download_pums.R [--refresh]")

  project_root <- here::here()
  check(normalizePath(getwd()) == normalizePath(project_root),
        "Run this script from the repository root.")

  # Request these 24 columns for everyone in the sample.
  # Script 01 later selects citizens aged 18 and over.
  variables <- c(
    "YEAR", "MULTYEAR", "SAMPLE", "SERIAL", "CBSERIAL", "HHWT", "CLUSTER",
    "STATEFIP", "PUMA", "CPUMA1020", "STRATA", "GQ", "HHINCOME", "PERNUM",
    "PERWT", "SEX", "AGE", "RACE", "RACED", "HISPAN", "HISPAND", "CITIZEN",
    "EDUC", "EDUCD"
  )

  # Ask for one CSV row per person, with household fields repeated on each person's row.
  # https://tech.popdata.org/ipumsr/reference/define_extract_micro.html
  definition <- ipumsr::define_extract_micro(
    collection = "usa",
    description = "polling-without-people: full 2020-2024 ACS five-year PUMS",
    # The API identifies the 2020-2024 ACS five-year sample as us2024c.
    # The downloaded SAMPLE column uses a numeric code.
    # https://usa.ipums.org/usa-action/samples/sample_ids
    samples = "us2024c",
    variables = variables,
    data_format = "csv",
    data_structure = "rectangular",
    rectangular_on = "P"
  )
  request_json_path <- tempfile(fileext = ".json")
  on.exit(unlink(request_json_path), add = TRUE)
  ipumsr::save_extract_as_json(definition, request_json_path)
  file_sha256 <- function(path) digest::digest(file = path, algo = "sha256")
  request_sha256 <- file_sha256(request_json_path)

  # Select the local snapshot ----
  store <- file.path(project_root, "01_frame", "data", "input", "ipums_pums")
  dir.create(store, recursive = TRUE, showWarnings = FALSE)
  current_snapshot_path <- file.path(store, "current_snapshot.txt")
  lock_dir <- file.path(store, ".download-lock")
  this_run_holds_lock <- FALSE

  # Creating this directory reserves the download for one process.
  acquire_lock <- function() {
    check(dir.create(lock_dir, showWarnings = FALSE),
          paste("Cannot acquire the IPUMS download lock:", lock_dir,
                "If a previous process was interrupted, see 00_download_pums.md."))
    this_run_holds_lock <<- TRUE
    writeLines(c(as.character(Sys.info()[["nodename"]]), as.character(Sys.getpid())),
               file.path(lock_dir, "owner.txt"))
  }
  on.exit(if (this_run_holds_lock) unlink(lock_dir, recursive = TRUE), add = TRUE)

  if (refresh || !file.exists(current_snapshot_path)) acquire_lock()
  # Another run may have saved a snapshot since our first check.
  if (refresh || !file.exists(current_snapshot_path)) {
    check(nzchar(Sys.getenv("IPUMS_API_KEY")), "IPUMS_API_KEY is unavailable.")
    available_samples <- ipumsr::get_sample_info("usa")
    selected_sample <- available_samples[available_samples$name == "us2024c", , drop = FALSE]
    check(nrow(selected_sample) == 1L &&
            selected_sample$description[[1]] == "2020-2024, ACS 5-year",
          "The requested sample is unavailable or its description has changed.")

    snapshot_id <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_", Sys.getpid())
    snapshot_dir <- file.path(store, snapshot_id)
    check(dir.create(snapshot_dir), "Could not create a new snapshot directory.")
    check(file.copy(request_json_path, file.path(snapshot_dir, "request.json")),
          "Could not save the requested extract definition.")

    # Write the whole folder name before making it visible to another run.
    temporary_pointer_path <- tempfile(tmpdir = store)
    writeLines(snapshot_id, temporary_pointer_path)
    check(file.rename(temporary_pointer_path, current_snapshot_path),
          "Could not save the snapshot pointer.")
  }

  snapshot_id <- readLines(current_snapshot_path, warn = FALSE)
  check(length(snapshot_id) == 1L && grepl("^[0-9]{8}T[0-9]{6}_[0-9]+$", snapshot_id),
        "Invalid local snapshot pointer; inspect it before proceeding.")
  snapshot_dir <- file.path(store, snapshot_id)
  saved_request_path <- file.path(snapshot_dir, "request.json")
  check(file.exists(saved_request_path) && file_sha256(saved_request_path) == request_sha256,
        "The requested settings differ from this snapshot. Use --refresh for a new request.")
  receipt_path <- file.path(snapshot_dir, "download_manifest.csv")
  files_dir <- file.path(snapshot_dir, "files")

  # Reuse a completed download ----
  # The receipt identifies the two files even after the download links expire.
  receipt <- NULL
  if (file.exists(receipt_path)) {
    receipt <- read_download_receipt(receipt_path, request_sha256)
    saved_paths <- file.path(files_dir, receipt$file)
    file_present <- file.exists(saved_paths)
    for (i in which(file_present)) {
      check(file.info(saved_paths[i])$size == as.numeric(receipt$bytes[i]) &&
              file_sha256(saved_paths[i]) == receipt$sha256[i],
            paste("Stored file differs from its receipt:", receipt$file[i],
                  "Inspect the change; --refresh creates a separate snapshot."))
    }
    if (all(file_present)) {
      cat("Verified and reused the stored IPUMS files; no API request made.\n")
      cat("Snapshot:", snapshot_dir, "\n")
      cat("Script 01 verifies this snapshot against the reviewed source specification.\n")
      return(invisible(NULL))
    }
    cat("A stored source file is missing; recovering the same extract.\n")
  }

  # Resume or submit the IPUMS request ----
  if (!this_run_holds_lock) {
    acquire_lock()
    # If another run changed the snapshot or finished the download, start the check again.
    check(identical(snapshot_id, readLines(current_snapshot_path, warn = FALSE)) &&
            identical(!is.null(receipt), file.exists(receipt_path)),
          "The selected download changed during verification. Rerun Script 00.")
  }
  check(nzchar(Sys.getenv("IPUMS_API_KEY")), "IPUMS_API_KEY is unavailable.")
  check(nzchar(Sys.which("gzip")), "The gzip command is required to check the download.")
  dir.create(files_dir, showWarnings = FALSE)
  extract_number <- resume_or_submit_extract(snapshot_dir, definition, receipt)
  cat("Checking IPUMS USA extract:", extract_number, "\n")
  extract <- ipumsr::get_extract_info(paste0("usa:", extract_number))

  # Keep the returned definition for inspection even if its settings fail a check.
  returned_json_path <- tempfile(fileext = ".json")
  on.exit(unlink(returned_json_path), add = TRUE)
  ipumsr::save_extract_as_json(extract, returned_json_path)
  returned_definition <- jsonlite::read_json(returned_json_path)
  check(file.copy(returned_json_path, file.path(snapshot_dir, "returned_definition.json"),
                  overwrite = TRUE), "Could not save the returned definition.")
  check_returned_definition(returned_definition, variables)

  check(extract$status %in% c("queued", "started", "produced", "completed"),
        paste("Extract status is", extract$status, "- inspect it on IPUMS."))
  if (extract$status != "completed") {
    # After a 30-minute timeout, the next run can resume the saved extract number.
    extract <- ipumsr::wait_for_extract(extract, max_delay_seconds = 30, timeout_seconds = 1800)
  }

  # Download and verify both files ----
  links <- extract$download_links[c("ddi_codebook", "data")]
  has_url <- vapply(links, function(link) {
    is.list(link) && is.character(link$url) && length(link$url) == 1L && nzchar(link$url)
  }, logical(1))
  check(length(has_url) == 2L && all(has_url), paste(
    "This extract has no usable download links, possibly because it expired.",
    "Use --refresh to request a separate new snapshot."
  ))
  filenames <- vapply(links, function(link) basename(link$url), character(1))
  check(!anyDuplicated(filenames) && all(grepl("^[A-Za-z0-9_.-]+$", filenames)),
        "Unexpected source filenames in the API response.")
  saveRDS(extract, file.path(snapshot_dir, "download_metadata.rds"))

  # Keep incoming files separate so an interrupted recovery preserves the surviving copy.
  staging_dir <- file.path(snapshot_dir, "download_in_progress")
  dir.create(staging_dir, showWarnings = FALSE)
  ipumsr::download_extract(extract, download_dir = staging_dir, overwrite = TRUE)
  staged_paths <- file.path(staging_dir, filenames)
  check(all(file.exists(staged_paths)) && all(file.info(staged_paths)$size > 0),
        "The codebook or microdata download is missing or empty.")
  file_hashes <- vapply(staged_paths, file_sha256, character(1))
  file_sizes <- file.info(staged_paths)$size

  # IPUMS may supply a size, a checksum, both, or neither for each download.
  provider_size_checked <- rep(FALSE, length(links))
  provider_sha256_checked <- rep(FALSE, length(links))
  for (i in seq_along(links)) {
    link <- links[[i]]
    if (!is.null(link$bytes)) {
      check(file_sizes[i] == as.numeric(link$bytes), "Downloaded byte count differs from IPUMS.")
      provider_size_checked[i] <- TRUE
    }
    if (!is.null(link$sha256)) {
      check(tolower(link$sha256) == file_hashes[i], "Downloaded SHA-256 differs from IPUMS.")
      provider_sha256_checked[i] <- TRUE
    }
  }

  if (!is.null(receipt)) {
    # Match by role so the receipt's row order does not affect recovery.
    receipt_rows <- match(names(links), receipt$role)
    check(all(filenames == receipt$file[receipt_rows]) &&
            all(file_hashes == receipt$sha256[receipt_rows]) &&
            all(file_sizes == as.numeric(receipt$bytes[receipt_rows])),
          "Recovered files differ from the previous download receipt.")
  }
  check_downloaded_columns(
    data_path = staged_paths[names(links) == "data"],
    codebook_path = staged_paths[names(links) == "ddi_codebook"],
    variables = variables
  )

  # Save the checked files and their receipt ----
  destinations <- file.path(files_dir, filenames)
  for (i in seq_along(staged_paths)) {
    if (!is.null(receipt) && file.exists(destinations[i])) {
      check(file_sha256(destinations[i]) == file_hashes[i],
            "A surviving source file changed during recovery.")
      unlink(staged_paths[i])
    } else {
      check(file.rename(staged_paths[i], destinations[i]), "Could not promote a checked download.")
    }
  }
  unlink(staging_dir, recursive = TRUE)

  # Recovery keeps the original receipt. A new download gets one after both files pass.
  if (is.null(receipt)) {
    receipt <- data.frame(
      role = names(links), file = unname(filenames), bytes = file_sizes,
      sha256 = unname(file_hashes), extract_number = extract_number, sample = "us2024c",
      request_sha256 = request_sha256,
      downloaded_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      provider_size_checked = provider_size_checked,
      provider_sha256_checked = provider_sha256_checked
    )
    temporary_receipt <- tempfile(tmpdir = snapshot_dir)
    readr::write_csv(receipt, temporary_receipt)
    check(file.rename(temporary_receipt, receipt_path), "Could not save the download receipt.")
  }
  cat("\nDownload, compression and 24-column schema checks passed.\n")
  cat("Snapshot:", snapshot_dir, "\n")
  cat("Receipt:", receipt_path, "\n")
  print(receipt[, c("role", "file", "bytes", "sha256")], row.names = FALSE)
  cat("\nDownload complete; analysis outputs have not been changed.\n")
  cat("Next: Script 01 checks the selected snapshot against 00_pums_source.json.\n")
}

# Read the receipt for a saved download ----
read_download_receipt <- function(path, request_sha256) {
  receipt <- readr::read_csv(
    path, col_types = readr::cols(.default = readr::col_character()), show_col_types = FALSE
  )
  invalid <- "Invalid local download manifest; inspect it before proceeding."
  required_fields <- c("role", "file", "bytes", "sha256", "extract_number",
                       "sample", "request_sha256", "downloaded_utc")
  check(all(required_fields %in% names(receipt)) && nrow(receipt) == 2L && !anyNA(receipt), invalid)

  check(!anyDuplicated(receipt$role) && setequal(receipt$role, c("ddi_codebook", "data")), invalid)
  check(!anyDuplicated(receipt$file) && all(grepl("^[A-Za-z0-9_.-]+$", receipt$file)), invalid)
  check(all(grepl("^[a-f0-9]{64}$", receipt$sha256)), invalid)
  check(all(grepl("^[0-9]+$", receipt$extract_number)) &&
          length(unique(receipt$extract_number)) == 1L, invalid)
  file_sizes <- as.numeric(receipt$bytes)
  check(all(is.finite(file_sizes) & file_sizes > 0), invalid)
  check(all(receipt$sample == "us2024c") && all(receipt$request_sha256 == request_sha256), invalid)
  receipt
}

# Submit once and keep the extract number for retries ----
resume_or_submit_extract <- function(snapshot_dir, definition, receipt) {
  number_path <- file.path(snapshot_dir, "extract_number.txt")
  started_path <- file.path(snapshot_dir, "submission_started.txt")
  if (!file.exists(number_path)) {
    check(is.null(receipt), "Completed receipt exists but its extract number file is missing.")
    check(!file.exists(started_path), paste(
      "An earlier submission has no saved extract number.",
      "Inspect your IPUMS extract history before retrying; see the companion document."
    ))
    # IPUMS can accept a request even if its response never reaches us. Write the
    # marker first so a retry asks us to check the extract history before submitting again.
    writeLines(format(Sys.time(), tz = "UTC", usetz = TRUE), started_path)
    submitted <- ipumsr::submit_extract(definition)
    extract_number <- as.character(submitted$number)
    check(length(extract_number) == 1L && grepl("^[0-9]+$", extract_number),
          "The API returned no usable extract number.")
    temporary_number <- tempfile(tmpdir = snapshot_dir)
    writeLines(extract_number, temporary_number)
    check(file.rename(temporary_number, number_path), "Could not save the submitted extract number.")
    saveRDS(submitted, file.path(snapshot_dir, "submitted_extract.rds"))
    cat("Submitted IPUMS USA extract:", extract_number, "\n")
  }

  extract_number <- readLines(number_path, warn = FALSE)
  check(length(extract_number) == 1L && grepl("^[0-9]+$", extract_number),
        "Invalid saved extract number.")
  if (!is.null(receipt)) {
    check(all(receipt$extract_number == extract_number), "Receipt and extract number disagree.")
  }
  extract_number
}

# Check the settings IPUMS returned ----
check_returned_definition <- function(returned, variables) {
  # IPUMS may list only the base variables in its response. The CSV and codebook
  # must still contain the three detailed columns. https://usa.ipums.org/usa-action/faq
  required_names <- setdiff(variables, c("RACED", "HISPAND", "EDUCD"))
  received_names <- names(returned$variables)
  missing_names <- setdiff(required_names, received_names)
  unexpected_names <- setdiff(received_names, variables)
  check(!anyDuplicated(received_names) &&
          length(missing_names) == 0L && length(unexpected_names) == 0L,
        paste("Returned API variable definitions differ. Missing base names:",
              paste(missing_names, collapse = ", "), "; unexpected names:",
              paste(unexpected_names, collapse = ", ")))

  # Unused options can be absent or empty. An explicit FALSE also disables a switch.
  empty_setting <- function(x) {
    is.null(x) || length(unlist(x, recursive = TRUE, use.names = FALSE)) == 0L
  }
  disabled_switch <- function(x) empty_setting(x) || identical(x, FALSE)
  check(identical(returned$collection, "usa") &&
          identical(returned$dataFormat, "csv") &&
          identical(names(returned$dataStructure), "rectangular") &&
          identical(returned$dataStructure$rectangular$on, "P") &&
          setequal(names(returned$samples), "us2024c") &&
          length(returned$samples) == 1L &&
          disabled_switch(returned$dataQualityFlags),
        "Returned sample or layout differs; inspect returned_definition.json.")

  # IPUMS may mark a variable as preselected. Check settings that affect who
  # appears in the extract or how their data are coded.
  for (settings in returned$variables) {
    check(empty_setting(settings$caseSelections) && empty_setting(settings$attachedCharacteristics) &&
            disabled_switch(settings$adjustMonetaryValues) && disabled_switch(settings$dataQualityFlags),
          "Returned definition includes a selection or variable transformation.")
  }
}

# Check the downloaded CSV and its codebook ----
check_downloaded_columns <- function(data_path, codebook_path, variables) {
  check(grepl("\\.gz$", data_path), "Expected compressed microdata.")
  gzip_result <- system2("gzip", c("-t", "--", shQuote(data_path)), stdout = TRUE, stderr = TRUE)
  check(is.null(attr(gzip_result, "status")), "gzip integrity check failed.")

  codebook <- ipumsr::read_ipums_ddi(codebook_path)
  codebook_columns <- ipumsr::ipums_var_info(codebook)$var_name
  csv_columns <- names(readr::read_csv(
    data_path, n_max = 0L, name_repair = "minimal", show_col_types = FALSE,
    col_types = readr::cols(.default = readr::col_character())
  ))
  check(!anyDuplicated(csv_columns) && !anyDuplicated(codebook_columns) &&
          setequal(csv_columns, variables) && setequal(codebook_columns, variables),
        "CSV/codebook columns differ from the requested 24-variable schema.")
}

main()

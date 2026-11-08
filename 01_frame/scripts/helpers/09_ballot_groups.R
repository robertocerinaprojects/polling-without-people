# Count each Step 08 nominee once. Columns are D, R, Other in that order.
# The four groups describe party competition; two Democrats facing one
# another are in the D-only party group even though voters can choose a name.
house_ballot_groups <- function(slate) {
  counts <- as.matrix(slate)
  if (ncol(counts) != 3L || !(is.numeric(counts) || is.logical(counts)) ||
      any(!is.finite(counts)) || any(counts < 0 | counts != floor(counts)) ||
      any(rowSums(counts) == 0L)) {
    stop("Expected three nonnegative candidate counts D, R, Other and at least one nominee per district.")
  }
  democratic <- counts[, 1L] > 0
  republican <- counts[, 2L] > 0
  other <- counts[, 3L] > 0
  both <- democratic & republican
  one <- xor(democratic, republican)
  group <- rep(NA_character_, nrow(counts))
  group[both & !other] <- "D_vs_R"
  group[both & other] <- "D_vs_R_vs_Other"
  group[one & !other] <- "main_party_uncontested"
  group[one & other] <- "main_party_missing"
  # The same direction contrast applies within both one-major-party groups.
  # Other-only has no estimable group and no directional contrast.
  direction <- as.integer(democratic) - as.integer(republican)
  direction[!democratic & !republican] <- NA_integer_
  data.frame(
    ballot_group = factor(group, levels = c("D_vs_R", "D_vs_R_vs_Other",
                          "main_party_uncontested", "main_party_missing")),
    major_party_direction = direction
  )
}

# Explicit indicators preserve D versus R as the reference independently
# of session contrast options. Other-only rows stay available to the audits.
house_ballot_design <- function(groups) {
  g <- groups$ballot_group
  if (anyNA(g)) stop("Other-only districts have no fitted ballot group.")
  data.frame(threeParty = as.integer(g == "D_vs_R_vs_Other"),
             mainPartyUncontested = as.integer(g == "main_party_uncontested"),
             mainPartyMissing = as.integer(g == "main_party_missing"),
             majorPartyDirection = groups$major_party_direction)
}

# CES Common Content 2024, release V9. The questionnaire defines the
# response codes. Our priority order is in 01_frame/docs/05_vote_rules.md.

vote_input_types <- function() {
  numeric_items <- c("CC24_412", "CC24_410", "CC24_401", "CC24_367_voted",
                     "CC24_364a", "CC24_367", "CC24_364b", "CC24_363",
                     "inputstate_post", "cdid119_post")
  pre_party <- paste0("HouseCand", 1:5, "Party")
  fields <- c(numeric_items, pre_party, paste0(pre_party, "_post"))
  types <- c(rep(list(readr::col_integer()), length(numeric_items)),
             rep(list(readr::col_character()), 2L * length(pre_party)))
  stats::setNames(types, fields)
}

# House responses 1–5 pick a slot on this respondent's ballot, not a party.
# Look up that slot on the roster shown in the same wave as the question.
decode_house_ballot <- function(answer, party_roster, no_vote_codes) {
  choice <- rep(NA_character_, length(answer))
  rows <- which(answer %in% 1:5)
  party <- trimws(party_roster[cbind(rows, answer[rows])])
  party[party %in% c("", "NA", "__NA__", "-1")] <- NA_character_
  other_party <- !is.na(party) & !party %in% c("Democratic", "Republican")
  party[other_party] <- "Other"

  choice[rows] <- party
  choice[answer %in% 10L] <- "Other"
  choice[answer %in% no_vote_codes] <- "No Vote"
  choice
}

# Keep the source as well as the outcome. A missing answer passes the
# respondent to the next question; an explicit No Vote resolves the office.
first_usable_vote <- function(stages) {
  n <- length(stages[[1L]])
  choice <- rep(NA_character_, n)
  source <- rep("unresolved", n)
  for (stage in names(stages)) {
    answer <- stages[[stage]]
    use <- is.na(choice) & !is.na(answer)
    choice[use] <- answer[use]
    source[use] <- stage
  }
  list(
    choice = factor(choice, levels = c("Democratic", "Republican", "Other", "No Vote")),
    source = source
  )
}

# Locate the 2024 House contest for the wave that supplied the answer. A
# mover reporting an early vote in the pre-election survey keeps the pre-wave
# district, even if they gave a different residence in the post-election survey.
attach_house_contest_2024 <- function(ces, source) {
  post_wave <- source %in% c("post_choice", "post_nonvoter")
  state <- ifelse(post_wave, ces$inputstate_post, ces$inputstate)
  cd <- ifelse(post_wave, ces$cdid119_post, ces$cdid119)
  resolved <- source != "unresolved"
  stopifnot(!anyNA(state[resolved]), !anyNA(cd[resolved]), all(cd[resolved] >= 1L))

  # CES uses district 1 for each at-large state and for DC. The Census uses
  # 00 for the at-large House seats and 98 for DC's delegate.
  at_large <- state %in% c(2L, 10L, 38L, 46L, 50L, 56L)
  dc <- state %in% 11L
  stopifnot(all(cd[resolved & (at_large | dc)] == 1L))
  cd[at_large] <- 0L
  cd[dc] <- 98L

  ces$house_vote_state_2024 <- ifelse(resolved, sprintf("%02d", state), NA_character_)
  ces$house_vote_cd119_2024 <- ifelse(resolved, sprintf("%02d", cd), NA_character_)
  contest <- ifelse(dc, "DC delegate", "US House representative")
  ces$house_contest_2024 <- ifelse(resolved, contest, NA_character_)
  ces
}

derive_ces_votes <- function(ces) {
  stopifnot(all(c("inputstate", "cdid119", names(vote_input_types())) %in% names(ces)))

  # Turnout questions can supply No Vote for either office. Other answers
  # to these questions give no office-specific candidate choice.
  post_nonvoter <- pre_nonvoter <- rep(NA_character_, nrow(ces))
  post_nonvoter[ces$CC24_401 %in% 1:4] <- "No Vote"
  pre_nonvoter[ces$CC24_363 %in% 5L] <- "No Vote"

  # House: a post-election choice outranks the general turnout question.
  # An already-cast pre-election vote outranks a pre-election preference.
  slots <- paste0("HouseCand", 1:5, "Party")
  pre_roster <- as.matrix(ces[slots])
  post_roster <- as.matrix(ces[paste0(slots, "_post")])
  house <- first_usable_vote(list(
    post_choice = decode_house_ballot(ces$CC24_412, post_roster, no_vote_codes = c(11L, 12L)),
    post_nonvoter = post_nonvoter,
    pre_reported = decode_house_ballot(ces$CC24_367_voted, pre_roster, no_vote_codes = 99L),
    pre_preference = decode_house_ballot(ces$CC24_367, pre_roster, no_vote_codes = 99L),
    pre_nonvoter = pre_nonvoter
  ))

  # President: all three questions identify Harris as 1 and Trump as 2.
  # The remaining response codes differ across questions. An unlisted code
  # (including an unsure response) leaves the next answer available.
  post_codes <- c(
    `1` = "Democratic", `2` = "Republican", `3` = "Other", `4` = "Other",
    `5` = "Other", `6` = "Other", `8` = "Other", `9` = "No Vote"
  )
  early_codes <- c(`1` = "Democratic", `2` = "Republican", `3` = "Other", `5` = "No Vote")
  preference_codes <- c(`1` = "Democratic", `2` = "Republican", `3` = "Other", `4` = "No Vote")
  president <- first_usable_vote(list(
    post_choice = unname(post_codes[as.character(ces$CC24_410)]),
    post_nonvoter = post_nonvoter,
    pre_reported = unname(early_codes[as.character(ces$CC24_364a)]),
    pre_preference = unname(preference_codes[as.character(ces$CC24_364b)]),
    pre_nonvoter = pre_nonvoter
  ))

  ces$house_vote_2024 <- house$choice
  ces$house_vote_2024_source <- house$source
  ces$pres_vote_2024 <- president$choice
  ces$pres_vote_2024_source <- president$source
  attach_house_contest_2024(ces, house$source)
}

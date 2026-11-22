# CES Common Content 2024, release V9. The questionnaire defines the
# response codes. Our priority order is in 01_frame/docs/05_vote_rules.md.

vote_input_types <- function() {
  numeric_items <- c("CC24_412", "CC24_410", "CC24_401", "CC24_367_voted",
                     "CC24_364a", "CC24_367", "CC24_364b", "CC24_363",
                     "inputstate_post", "cdid119_post")
  pre_party <- paste0("HouseCand", 1:5, "Party")
  text_items <- c("CC24_410_t", "CC24_412_t", "CC24_367_voted_t", "CC24_367_t")
  character_items <- c(pre_party, paste0(pre_party, "_post"), text_items)
  fields <- c(numeric_items, character_items)
  types <- c(rep(list(readr::col_integer()), length(numeric_items)),
             rep(list(readr::col_character()), length(character_items)))
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

# Interpret clear statements entered in the Other box. Keep the matches
# specific so that a candidate name or party label retains its vote.
classify_other_vote <- function(text) {
  text <- tolower(gsub("[‘’]", "'", text))
  text <- stringr::str_squish(text)
  text <- sub("[.!?]+$", "", text)
  nonvote <- paste0(
    "^(i )?(did not|didn'?t) vote( (as uncontested|in this race|for (this (race|position|office)|a representative)|house of representatives))?$",
    "|[.!] i did not vote for a representative$|^i voted the down ticket$",
    "|^(i )?abstain(ed)?( (because|since) .+)?$|^no vote in this category$"
  )
  refusal <- paste0(
    "\\b(prefer (not to|to not) (say|answer|disclose)|rather not (say|answer)|refuse to (answer|say|disclose))\\b",
    "|\\b(don'?t|do not) (want|wish|care) to (say|answer|disclose|share)\\b",
    "|\\bdo not feel comfortable saying\\b|\\b(don'?t|never) tell\\b",
    "|\\b(secret ballot|not (saying|telling|disclosing|divulging|going to disclose)|business only)\\b",
    "|\\b(none of your business|not your business|no one'?s business|nobody'?s business|nunya ?biz|nunya ?business)\\b",
    "|^none ?ya( biz.*)?$",
    "|\\b(vote is (my personal business|private)|voted is private|keep private|will not answer|will not say|never say who)\\b",
    "|^(private( information)?|that('s| is) private( information)?|privacy protection|my business|mu business|my secret|it'?s a secret|non.?disclo(u)?sure|undisclosing|don'?t disclose|can'?t say|can not say|you do not need to know|i'm tired of answering this question)$"
  )
  unsure <- paste0(
    "^(i )?(don'?t know|do not know|idk|not sure|unsure|undecided|uncertain|no preference|no idea)( yet)?$",
    "|^(i )?(don'?t know (the name|who i voted for)|forgot( exactly)? who i voted for)$",
    "|^(i )?(don'?t|can'?t|couldn'?t) remember( (the )?name| because of having provisional ballot)?$",
    "|^n/a$",
    "|\\b(didn'?t know enough about the candidates)\\b"
  )
  ifelse(grepl(nonvote, text, perl = TRUE), "No Vote",
         ifelse(grepl(refusal, text, perl = TRUE) | grepl(unsure, text, perl = TRUE),
                "unresolved", "Other"))
}

apply_vote_response <- function(choice, answer, unsure_codes, other_code, text) {
  choice[answer %in% unsure_codes] <- "unresolved"
  other <- answer %in% other_code
  choice[other] <- classify_other_vote(text[other])
  choice
}

# Skipped questions allow a fallback. Explicit refusals and uncertainty
# resolve the outcome as missing before a lower-priority answer can replace it.
first_usable_vote <- function(stages) {
  n <- length(stages[[1L]])
  choice <- rep(NA_character_, n)
  source <- rep("unresolved", n)
  for (stage in names(stages)) {
    answer <- stages[[stage]]
    use <- is.na(choice) & !is.na(answer)
    choice[use] <- answer[use]
    source[use & answer != "unresolved"] <- stage
  }
  list(
    choice = factor(choice, levels = c("Democratic", "Republican", "Other", "No Vote")),
    source = source
  )
}

decode_post_votes <- function(ces) {
  slots <- paste0("HouseCand", 1:5, "Party_post")
  house <- decode_house_ballot(ces$CC24_412, as.matrix(ces[slots]), c(11L, 12L))
  codes <- c(
    `1` = "Democratic", `2` = "Republican", `3` = "Other", `4` = "Other",
    `5` = "Other", `6` = "Other", `8` = "Other", `9` = "No Vote"
  )
  president <- unname(codes[as.character(ces$CC24_410)])
  list(
    House = apply_vote_response(house, ces$CC24_412, 13L, 10L, ces$CC24_412_t),
    President = apply_vote_response(president, ces$CC24_410, integer(), 8L, ces$CC24_410_t)
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
  post <- decode_post_votes(ces)
  house <- first_usable_vote(list(
    post_choice = post$House,
    post_nonvoter = post_nonvoter,
    pre_reported = apply_vote_response(
      decode_house_ballot(ces$CC24_367_voted, pre_roster, 99L),
      ces$CC24_367_voted, 98L, 10L, ces$CC24_367_voted_t
    ),
    pre_preference = apply_vote_response(
      decode_house_ballot(ces$CC24_367, pre_roster, 99L),
      ces$CC24_367, 98L, 10L, ces$CC24_367_t
    ),
    pre_nonvoter = pre_nonvoter
  ))

  # President: all three questions identify Harris as 1 and Trump as 2.
  # The remaining response codes differ across questions.
  early_codes <- c(`1` = "Democratic", `2` = "Republican", `3` = "Other",
                   `4` = "unresolved", `5` = "No Vote")
  preference_codes <- c(`1` = "Democratic", `2` = "Republican", `3` = "Other",
                         `4` = "No Vote", `5` = "unresolved")
  president <- first_usable_vote(list(
    post_choice = post$President,
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

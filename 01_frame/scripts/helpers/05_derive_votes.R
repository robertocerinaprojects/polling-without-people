# CES Common Content 2024 V9. Use the questionnaire's response codes and the
# project's priority order documented in 01_frame/docs/05_vote_rules.md.
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

derive_ces_votes <- function(ces) {
  stopifnot(all(c("inputstate", "cdid119", names(vote_input_types())) %in% names(ces)))
  # A nonresponse, unsure answer or missing party label permits the next
  # source in the priority order. Keep a genuine third-party choice as Other.
  missing_answer <- rep(NA_character_, nrow(ces))
  house_choice <- function(item, post) {
    suffix <- if (post) "_post" else ""
    roster <- as.matrix(ces[paste0("HouseCand", 1:5, "Party", suffix)])
    choice <- missing_answer
    named <- which(item %in% 1:5)
    party <- trimws(roster[cbind(named, item[named])])
    party[party %in% c("", "NA", "__NA__", "-1")] <- NA_character_
    choice[named] <- ifelse(party %in% c("Democratic", "Republican"), party,
                            ifelse(is.na(party), NA_character_, "Other"))
    choice[item %in% 10L] <- "Other"
    no_vote <- if (post) c(11L, 12L) else 99L
    choice[item %in% no_vote] <- "No Vote"
    choice
  }

  post_nonvoter <- pre_nonvoter <- missing_answer
  post_nonvoter[ces$CC24_401 %in% 1:4] <- "No Vote"
  pre_nonvoter[ces$CC24_363 %in% 5L] <- "No Vote"

  # The post and the two pre presidential questions have different codes
  # for No Vote. The post item also names specific third-party candidates.
  president_choice <- function(item, mapping) unname(mapping[as.character(item)])
  dem <- "Democratic"
  repub <- "Republican"
  pres_post <- president_choice(ces$CC24_410, c(`1` = dem, `2` = repub,
    `3` = "Other", `4` = "Other", `5` = "Other", `6` = "Other",
    `8` = "Other", `9` = "No Vote"))
  pres_early <- president_choice(ces$CC24_364a, c(`1` = dem, `2` = repub,
    `3` = "Other", `5` = "No Vote"))
  pres_pref <- president_choice(ces$CC24_364b, c(`1` = dem, `2` = repub,
    `3` = "Other", `4` = "No Vote"))

  resolve <- function(post, early, preference) {
    stages <- list(post_choice = post, post_nonvoter = post_nonvoter,
                   pre_reported = early, pre_preference = preference,
                   pre_nonvoter = pre_nonvoter)
    choice <- missing_answer
    source <- rep("unresolved", nrow(ces))
    for (stage in names(stages)) {
      use <- is.na(choice) & !is.na(stages[[stage]])
      choice[use] <- stages[[stage]][use]
      source[use] <- stage
    }
    list(choice = factor(choice, levels = c(dem, repub, "Other", "No Vote")),
         source = source)
  }

  house <- resolve(house_choice(ces$CC24_412, TRUE),
                   house_choice(ces$CC24_367_voted, FALSE),
                   house_choice(ces$CC24_367, FALSE))
  pres <- resolve(pres_post, pres_early, pres_pref)
  ces$house_vote_2024 <- house$choice
  ces$house_vote_2024_source <- house$source
  ces$pres_vote_2024 <- pres$choice
  ces$pres_vote_2024_source <- pres$source

  # The post ballot roster follows the post residence. The baseline residence
  # and its modeled 2026 district remain available for demographic matching.
  post <- house$source %in% c("post_choice", "post_nonvoter")
  state <- ifelse(post, ces$inputstate_post, ces$inputstate)
  cd <- ifelse(post, ces$cdid119_post, ces$cdid119)
  resolved <- house$source != "unresolved"
  stopifnot(!anyNA(state[resolved]), !anyNA(cd[resolved]), all(cd[resolved] >= 1L))
  at_large <- state %in% c(2L, 10L, 38L, 46L, 50L, 56L)
  dc <- state %in% 11L
  stopifnot(all(cd[resolved & (at_large | dc)] == 1L))
  ces$house_vote_state_2024 <- ifelse(resolved, sprintf("%02d", state), NA_character_)
  cd[at_large] <- 0L
  cd[dc] <- 98L
  ces$house_vote_cd119_2024 <- ifelse(resolved, sprintf("%02d", cd), NA_character_)
  ces$house_contest_2024 <- ifelse(resolved, ifelse(dc, "DC delegate", "US House representative"),
                                   NA_character_)
  ces
}
